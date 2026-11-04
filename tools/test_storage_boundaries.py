
from pathlib import Path
import hashlib
import json
import shutil
import struct
import subprocess
import time
from test_file_system import Disk, fat_name, ex_name, short_entry, u32
from test_media_library import container
from test_media_storage import bmp, wave, header, descriptor, PIXELS, AUDIO
from run_verilated import compile_model

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/revision_20261103_native_files/storage_boundaries'


def entries(d, name, alias, cluster, size, contiguous=False, directory=False):
    return ex_name(name, cluster, size, contiguous, directory) if d.exfat else fat_name(name, alias, cluster, size, directory)


def install(d, first, raw, contiguous=False):
    span = 512 << d.shift
    clusters = [first + i * (1 if contiguous else 3) for i in range((len(raw)+span-1)//span)]
    d.chain(clusters)
    for i,c in enumerate(clusters):
        for s in range(1<<d.shift):
            off=i*span+s*512
            d.sectors[d.cluster_lba(c)+s]=bytearray(raw[off:off+512].ljust(512,b'\0'))
    return clusters


def save_case(name, d, commands=(), golden=(), names=(), counts=(0,0,0), error=0):
    path=OUT/name;path.mkdir(parents=True,exist_ok=True)
    lbas=sorted(d.sectors)
    data={'lbas':lbas,'disk':[v for lba in lbas for v in struct.unpack('<128I',d.sectors[lba])],
          'commands':commands,'golden':golden,'names':[fid for fid,text in names],
          'name_bytes':[ord(c) if 32<=ord(c)<=126 else ord('?') for fid,text in names for c in text[:32].ljust(32)]}
    for key,values in data.items():
        (path/(key+'.hex')).write_text(''.join(f'{v:08x}\n' for v in values))
    args=[f'+sectors={len(lbas)}',f'+commands={len(commands)//5}',f'+names={len(names)}',f'+mount_error={error}',
          f'+videos={counts[0]}',f'+images={counts[1]}',f'+songs={counts[2]}']
    return path,args


def mapped_case(name, exfat, partition, shift, contiguous=False, corrupt=''):
    d=Disk(exfat,partition,shift)
    raw=container();span=512<<shift
                                                                                                 
    size=max(len(raw),span*3+512*3)
    raw+=bytes((i*29+(i>>9))&255 for i in range(size-len(raw)))
    raw=raw.ljust((len(raw)+511)&~511,b'\0')
    chain=install(d,100,raw,contiguous)
    picture,pixels=bmp(131,3,24);install(d,600,picture)
    sound,samples=wave(1000);install(d,650,sound)
    child,child_pixels=bmp(3,2,32,True);install(d,700,child)
    root=entries(d,'Long movie filename.TFV',b'LONGMO~1TFV',100,len(raw),contiguous)
    root+=entries(d,'Image one.bmp',b'IMAGE1  BMP',600,len(picture))
    root+=entries(d,'A song.wav',b'ASONG   WAV',650,len(sound))
    root+=entries(d,'Sub directory',b'SUBDIR     ',15,span if exfat else 0,exfat,True)
    d.directory([2,9],root)
    d.directory([15],entries(d,'Image two 图像.BMP',b'IMAGE2  BMP',700,len(child)))
    names=[(0,'Long movie filename.TFV'),(128,'Image one.bmp'),(129,'Image two 图像.BMP'),(256,'A song.wav')]
    queries=sorted(set([0,1,(span//512)-1,span//512,2*span//512,2*span//512+1,len(raw)//512-1]))
    queries += [1,span//512,0,len(raw)//512-1,len(raw)//512]
    commands=[];golden=[]
    if corrupt:
        u32(d.sectors[d.fat+(chain[0]//128)],(chain[0]%128)*4,chain[0] if corrupt=='self' else 0xffffffff)
        queries=[0,span//512]
    for lba in queries:
        bad=0x53 if lba*512>=len(raw) or (corrupt and lba>=span//512) else 0
        commands.extend([0,0,lba,0,bad]);golden.extend(struct.unpack('<128I',raw[lba*512:lba*512+512].ljust(512,b'\0')))
    if not corrupt:
        for fid,w,h,p in [(128,131,3,pixels),(129,3,2,child_pixels)]:
            stride=(w+127)//128
            for lba in [0,1,PIXELS,PIXELS+stride*h-1,PIXELS]:
                words=header(1,0) if lba==0 else descriptor(1,w,h) if lba==1 else (p[(lba-PIXELS)//stride][((lba-PIXELS)%stride)*128:((lba-PIXELS)%stride+1)*128]+[0]*128)[:128]
                commands.extend([fid,1,lba,0,0]);golden.extend(words)
        for lba in [0,AUDIO,AUDIO+7,AUDIO+1,AUDIO]:
            words=header(1000,0) if lba==0 else (samples[(lba-AUDIO)*127:(lba-AUDIO+1)*127]+[0]*128)[:128]
            commands.extend([256,2,lba,0,0]);golden.extend(words)
    return save_case(name,d,commands,golden,names,(1,2,1))


def rejection_case(name,exfat,corrupt):
    d=Disk(exfat,0,0);d.directory([2,9],[]);error=0
    if corrupt=='signature':d.sectors[0][510]=0;error=0x42
    elif corrupt=='geometry':u32(d.sectors[0],88 if exfat else 32,33);error=0x43
    elif corrupt=='checksum':
        d.directory([2,9],entries(d,'Image.bmp',b'IMAGE   BMP',40,512))
        d.sectors[d.cluster_lba(2)][2]^=1;error=0x45
    elif corrupt in ('duplicate_directory','directory_limit'):
        count=2 if corrupt=='duplicate_directory' else 64
        root=[]
        for n in range(count):
            cluster=30 if corrupt=='duplicate_directory' else 30+n
            root+=entries(d,f'DIR{n:03d}',f'DIR{n:03d}     '.encode(),cluster,512 if exfat else 0,False,True)
        chains=list(range(200,200+(len(root)*32+32+511)//512))
        d.chain(chains);u32(d.sectors[0],96 if exfat else 44,chains[0]);d.directory(chains,root);error=0x46
    return save_case(name,d,error=error)


def capacity_case(name,exfat,overflow=False):
    d=Disk(exfat,0,0);root=[];names=[]
    for t,ext in enumerate(['TFV','BMP','WAV','LRC']):
        count=(127 if t==3 else 128)+(1 if overflow and t==1 else 0)
        for n in range(count):
            text=f'F{n:07d}.{ext}';fid=t*128+n
            root+=entries(d,text,f'F{n:07d}{ext}'.encode(),40,512)
            if not overflow:names.append((fid,text))
    chains=list(range(200,200+(len(root)*32+32+511)//512))
    d.chain(chains);u32(d.sectors[0],96 if exfat else 44,chains[0]);d.directory(chains,root)
    return save_case(name,d,names=names,counts=(128,128,128),error=0x47 if overflow else 0)


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    sources=[ROOT/'rtl'/n for n in ['eg_memory.v','storage_cpu.v','media_storage.v']]+[ROOT/'tests/tb_storage_boundaries.v']
    tracked=sources+[ROOT/'firmware/storage.c',ROOT/'tools/test_file_system.py',Path(__file__),ROOT/'tools/test_media_library.py']+list((ROOT/'rtl').glob('storage_rom_*.hex'))
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in tracked}
    target=compile_model('tb_storage_boundaries',sources,OUT/'compiled')
    cases=[]
    for exfat in [False,True]:
        fs='exfat' if exfat else 'fat32'
        for part,shift in [(0,0),(2048,0),(0,3),(4096,7)]:
            cases.append(mapped_case(f'{fs}_p{part}_s{shift}',exfat,part,shift,exfat and shift>0))
        for bad in ['self','broken']:
            cases.append(mapped_case(fs+'_'+bad,exfat,2048,0,False,bad))
        for bad in ['signature','geometry','duplicate_directory','directory_limit']+(['checksum'] if exfat else []):
            cases.append(rejection_case(fs+'_'+bad,exfat,bad))
        cases.append(capacity_case(fs+'_capacity511',exfat))
        cases.append(capacity_case(fs+'_capacity_reject',exfat,True))
    results=[]
    for path,args in cases:
        for f in (ROOT/'rtl').glob('storage_rom_*.hex'):shutil.copy2(f,path/f.name)
        start=time.time()
        try:
            r=subprocess.run([str(target),*args],cwd=path,capture_output=True,text=True,timeout=180)
            stdout,stderr,code=r.stdout,r.stderr,r.returncode
        except subprocess.TimeoutExpired as exc:
            stdout=(exc.stdout or b'').decode() if isinstance(exc.stdout,bytes) else exc.stdout or '';stderr='TIMEOUT';code=-1
        changed=[str(p.relative_to(ROOT)) for p in tracked if hashlib.sha256(p.read_bytes()).hexdigest()!=hashes[str(p.relative_to(ROOT))]]
        passed=code==0 and 'PASS storage boundaries' in stdout and 'FAIL' not in stdout and not changed
        record=dict(case=path.name,passed=passed,source_sha256=hashes,source_changed=changed,stdout=stdout,stderr=stderr,seconds=time.time()-start)
        results.append(record);(path/'run.log').write_text(stdout+stderr)
        (OUT/'results.json').write_text(json.dumps(results,indent=2))
        print(path.name,'PASS' if passed else 'FAIL',stdout.strip(),stderr,flush=True)
    return 0 if all(r['passed'] for r in results) else 1


if __name__=='__main__':raise SystemExit(main())
