
from pathlib import Path
import hashlib
import json
import argparse
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/revision_20261103_native_files/pixels'
GLYPHS = json.loads((ROOT / 'verification/ui_font.json').read_text())['rows']
LINES = json.loads((ROOT / 'verification/ui_panel_text.json').read_text())
NAMES = ['Movie A.TFV', 'Second movie.TFV', 'First image.bmp', 'Second image.BMP',
         'A long image filename 03.bmp', 'image 04.bmp', 'image 05.bmp',
         'Ferry.wav', 'Hotel California.wav', 'Third song.wav']


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def scene(n):
    s = dict(page=0, fx=0, media=2, overlay=True, sub=True, wave=True,
             ready=True, opened=True, volume=16, muted=False, error=0,
             brightness=128, cursor=7, mark=256, count=10, videos=2, images=5, item=1)
    if n == 1:
        s.update(page=1, media=0, ready=False, opened=False, count=0, videos=0, images=0, cursor=0)
    elif n == 2:
        s.update(page=1, media=0, opened=False, count=0, videos=0, images=0, cursor=0)
    elif n == 3:
        s.update(page=1, media=0, opened=False, cursor=7)
    elif n == 4:
        s.update(page=1, cursor=9)
    elif n == 6:
        s['sub'] = False
    elif n == 7:
        s['wave'] = False
    elif n == 8:
        s.update(sub=False, wave=False)
    elif n == 9:
        s.update(page=2, fx=1, mark=768)
    elif n == 10:
        s.update(page=3, volume=7)
    elif n == 11:
        s.update(page=3, volume=7, muted=True)
    elif n == 12:
        s['overlay'] = False
    elif n == 13:
        s.update(sub=False, wave=False, brightness=144)
    elif n == 14:
        s.update(media=1, item=0, wave=False, sub=False, error=0x54)
    elif n == 15:
        s.update(media=0, item=1, wave=False, sub=False)
    return s


def render(n):
    s = scene(n)
    a = np.empty((800, 1280, 3), dtype=np.uint8)
    base = np.clip(np.array([0x22, 0x44, 0x66]) + s['brightness'] - 128, 0, 255)
    a[:] = 0 if s['fx'] == 1 else base
    font = np.zeros((800, 1280), dtype=bool)

    def blend(x0, y0, x1, y1, color):
        region = a[y0:y1, x0:x1]
        region[:] = (region >> 1) + (np.array(color, dtype=np.uint8) >> 1)

    def text(value, x, y):
        for i, ch in enumerate(value[:74]):
            if ch not in GLYPHS:
                continue
            rows = np.array(GLYPHS[ch], dtype=np.uint16)
            bits = ((rows[:, None] >> np.arange(15, 7, -1)) & 1).astype(bool)
            glyph = bits.repeat(2, axis=0).repeat(2, axis=1)
            left = x + i * 16
            if 0 <= left and left + 16 <= 1280:
                font[y:y+32, left:left+16] |= glyph

    if not s['overlay']:
        return a
    blend(0, 0, 1280, 84, [0x10, 0x30, 0x60])
    kind = ['VIDEO', 'IMAGE', 'AUDIO'][s['media']]
    status = f"{kind} {s['item']:03d} PAUSE B{s['brightness']:03d} C128"
    status = status.ljust(34) + f"VOL {s['volume']:02d}/16  " + ('MUTED' if s['muted'] else 'SOUND ON')
    text(status, 48, 8)
    text(f"WAVE {'ON' if s['wave'] else 'OFF':3} SUB {'ON' if s['sub'] else 'OFF':3} OSD ON  Z0 FX{s['fx']}", 48, 44)

    if s['page'] == 0:
        if s['wave']:
            y = 360 if s['media'] == 2 else 576
            a[y-1:y+2, 128:1152] = [0, 255, 255]
        if s['sub']:
            ys = [496, 536] if s['media'] == 2 else [584, 624]
            lyric = ''.join(chr(33+i % 94) for i in range(80))
            for row, y in enumerate(ys):
                blend(0, y, 1280, y+32, [0x60, 0x20, 0])
                text(lyric[row*39:row*39+39], 328, y)

                                                               
    blend(32, 96, 1248, 144, [8, 24, 40])
    if s['page'] == 0:
        blend(32, 152, 1248, 248, [8, 24, 40])
    elif s['page'] == 1:
        blend(32, 152, 1248, 776, [8, 24, 40])
    else:
        blend(32, 248, 1248, 432, [8, 24, 40])
    if s['page'] != 1:
        blend(32, 672, 1248, 800, [8, 24, 40])
        if s['error']:
            blend(32, 256, 1248, 288, [8, 24, 40])

    def media_name(ordinal):
        k = 'VIDEO' if ordinal < 2 else 'IMAGE' if ordinal < 7 else 'AUDIO'
        return k.ljust(8) + NAMES[ordinal].ljust(32)

    ordinal = s['item'] + (0 if s['media'] == 0 else 2 if s['media'] == 1 else 7)
    text(media_name(ordinal) if s['opened'] else LINES[1], 48, 104)
    if s['page'] == 1:
        heading = f"FILES {s['cursor']+1 if s['count'] else 0:04d} / {s['count']:04d}    VIDEO > IMAGE > AUDIO"
        text(heading, 48, 168)
        if not s['count']:
            text(LINES[5 if s['ready'] else 6], 48, 288)
        for row in range(8):
            ordinal = (s['cursor'] // 8) * 8 + row
            if ordinal >= s['count']:
                continue
            y = 224 + row * 64
            if ordinal == s['cursor']:
                a[y:y+32, 32:1248] = [0x16, 0x4d, 0x73]
            text(media_name(ordinal), 48, y)
        text(LINES[4], 48, 736)
    else:
        if s['page'] == 0:
            text(LINES[10], 48, 168)
            text(LINES[11], 48, 208)
        elif s['page'] == 2:
            text(LINES[12], 48, 256)
            text(LINES[13], 48, 320)
            text(LINES[14], 48, 384)
        elif s['page'] == 3:
            line = f"VOLUME {s['volume']:02d} / 16   " + ('MUTED   ' if s['muted'] else 'SOUND ON') + '    K1 LOWER  K2 HIGHER  K3 MUTE  K4 BACK'
            text(line, 48, 320)
        if s['error']:
            text(LINES[2][:11] + f"{s['error']:02X}" + LINES[2][13:], 48, 256)
        a[688:704, 128:1152] = [0x38, 0x4a, 0x5a]
        a[688:704, 128:128+s['mark']] = [0x29, 0xc5, 0xc9]
        x = 128 + s['mark']
        a[684:708, x-2:x+3] = [0xff, 0xdd, 0x66]
        now = '01:02:03' if s['page'] == 2 else '00:01:23'
        timeline = now + ' / 00:06:31'
        if s['page'] != 3:
            timeline += LINES[7][19:]
        text(timeline, 48, 720)
        text(LINES[0 if s['page'] == 3 else 8 if s['page'] == 2 else 9], 48, 760)
    a[font] = [255, 255, 255]
    return a


def main():
    global OUT
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, default=OUT)
    OUT = parser.parse_args().out.resolve()
    results = []
    for n in range(1, 16):
        path = OUT / f'rtl_{n:02d}.ppm'
        if not path.is_file():
            results.append(dict(scene=n, passed=False, reason='missing or incomplete capture'))
            continue
        with Image.open(path) as capture:
            if capture.format != 'PPM' or capture.mode != 'RGB' or capture.size != (1280, 800):
                results.append(dict(scene=n, passed=False, reason='invalid capture format or dimensions'))
                continue
            actual = np.asarray(capture)
        expected = render(n)
        different = np.any(actual != expected, axis=2)
        y, x = np.nonzero(different)
        Image.fromarray(expected).save(OUT / f'expected_{n:02d}.png')
        Image.fromarray(actual).save(OUT / f'rtl_{n:02d}.png')
        Image.fromarray(np.where(different[:, :, None], [255, 0, 255], actual // 4).astype(np.uint8)).save(OUT / f'diff_{n:02d}.png')
        row = dict(scene=n, passed=not len(x), pixels=1024000, mismatched_pixels=len(x),
                   rtl_sha256=digest(path), expected_sha256=hashlib.sha256(expected.tobytes()).hexdigest())
        if len(x):
            row['first_mismatch'] = dict(x=int(x[0]), y=int(y[0]), actual=actual[y[0], x[0]].tolist(), expected=expected[y[0], x[0]].tolist())
            row['bounds'] = [int(x.min()), int(y.min()), int(x.max()), int(y.max())]
        results.append(row)
        print(json.dumps(row), flush=True)
    inputs = [ROOT/'rtl'/name for name in ['video_scan_enhanced.v','ui_osd_layout.v','ui_player_panel.v',
              'ui_panel_text.v','ui_panel_text.hex','ui_font_zh_sync.v','audio_waveform.v','eg_memory.v']]
    inputs += [ROOT/'tests/tb_ui_raster.v', Path(__file__), ROOT/'verification/ui_font.json', ROOT/'verification/ui_panel_text.json']
    report = dict(passed=all(row['passed'] for row in results), scenes=results,
                  inputs={str(p.relative_to(ROOT)):digest(p) for p in inputs})
    (OUT/'result.json').write_text(json.dumps(report, indent=2))
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
