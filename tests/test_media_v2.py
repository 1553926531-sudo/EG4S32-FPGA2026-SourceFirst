
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
import wave
import zlib

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from tfm_format import read_bmp_source,verify_package,validate_sector,checked_sector
from media_pack import pack_v2


def original_bmp(path,width,height,top_down=False):
    rows=[];expected=[]
    for y in range(height):
        pixels=[((x+7*y)&255,(3*x+y)&255,(19*x+5*y)&255) for x in range(width)]
        row=b''.join(bytes(p) for p in pixels)
        rows.append(row+b'\0'*((-len(row))%4))
        expected.append(b''.join(bytes(p)+b'\0' for p in pixels)+b'\0'*((-width)%128*4))
    payload=b''.join(rows if top_down else reversed(rows))
    header=b'BM'+struct.pack('<IHHI',54+len(payload),0,0,54)
    header+=struct.pack('<IiiHHIIiiII',40,width,-height if top_down else height,1,24,0,len(payload),0,0,0,0)
    path.write_bytes(header+payload)
    return b''.join(expected)


class MediaV2Tests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='tfm2_');self.d=Path(self.temp.name)
        self.paths=[];self.expected=[]
        for i,(w,h) in enumerate(((1,1),(129,3),(640,480),(2048,1),(1,2048))):
            p=self.d/f'{i}.bmp';self.paths.append(p)
            self.expected.append(original_bmp(p,w,h,bool(i&1)))
        self.wav=self.d/'a.wav';self.pcm=b''.join(struct.pack('<hh',i-150,150-i) for i in range(300))
        with wave.open(str(self.wav),'wb') as w:
            w.setnchannels(2);w.setsampwidth(2);w.setframerate(48000);w.writeframes(self.pcm)
        self.out=self.d/'DEMO.PAK'
        self.h=pack_v2(self.paths[:2],self.paths[2:],self.wav,self.out)

    def tearDown(self):self.temp.cleanup()

    def test_every_original_pixel_orientation_and_padding(self):
        for p,expected in zip(self.paths,self.expected):
            _,_,payload=read_bmp_source(p);self.assertEqual(payload,expected)
        raw=self.out.read_bytes()
        for i,expected in enumerate(self.expected):
            d=validate_sector(raw[(i+1)*512:(i+2)*512])
            self.assertEqual(d[1],i if i<2 else 0x80000000|(i-2))
            self.assertEqual(raw[d[4]*512:(d[4]+d[6])*512],expected)
        pcm=b''.join(raw[s*512:s*512+508] for s in range(self.h['audio_lba'],self.h['sectors']))
        self.assertEqual(pcm[:len(self.pcm)],self.pcm)
        self.assertFalse(any(pcm[len(self.pcm):]))

    def test_corruption_in_each_region_is_rejected(self):
        raw=self.out.read_bytes()
        offsets=[0,512+4,3*512+508,self.h['audio_lba']*512+7,len(raw)-1]
        offsets += [validate_sector(raw[(i+1)*512:(i+2)*512])[4]*512 for i in range(5)]
        for at in offsets:
            bad=bytearray(raw);bad[at]^=1;p=self.d/'bad.pak';p.write_bytes(bad)
            with self.subTest(offset=at),self.assertRaises(ValueError):verify_package(p)

    def test_recomputed_descriptor_cannot_change_identity_or_overlap(self):
        raw=self.out.read_bytes()
        for word,value in ((1,7),(2,0),(2,2049),(4,1),(5,99),(6,999)):
            bad=bytearray(raw);d=list(validate_sector(raw[512:1024]));d[word]=value
            bad[512:1024]=checked_sector(d[:127]);p=self.d/'bad_layout.pak';p.write_bytes(bad)
            with self.subTest(word=word),self.assertRaises(ValueError):verify_package(p)

    def test_recomputed_padding_crc_is_still_rejected(self):
        raw=bytearray(self.out.read_bytes());d=list(validate_sector(raw[512:1024]))
        raw[d[4]*512+4]=1
        d[7]=zlib.crc32(raw[d[4]*512:(d[4]+d[6])*512]);raw[512:1024]=checked_sector(d[:127])
        p=self.d/'bad_padding.pak';p.write_bytes(raw)
        with self.assertRaises(ValueError):verify_package(p)

    def test_no_overwrite_or_empty_collections(self):
        with self.assertRaises(FileExistsError):pack_v2(self.paths[:2],self.paths[2:],self.wav,self.out)
        for frames,images in (([],self.paths),(self.paths,[])):
            with self.assertRaises(ValueError):pack_v2(frames,images,self.wav,self.d/'empty.pak')

    def test_invalid_bmp_and_truncation(self):
        raw=self.paths[1].read_bytes()
        for bad in (raw[:53],raw[:-1],b'XX'+raw[2:]):
            p=self.d/'bad.bmp';p.write_bytes(bad)
            with self.assertRaises(ValueError):read_bmp_source(p)


if __name__=='__main__':
    result=unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(MediaV2Tests))
    (ROOT/'verification/host_tests_v2.json').write_text(json.dumps(dict(tests=result.testsRun,
        failures=len(result.failures),errors=len(result.errors),passed=result.wasSuccessful()),indent=2))
    raise SystemExit(0 if result.wasSuccessful() else 1)
