
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]

def main():
    path = ROOT / 'verification/ui_panel_text.json'
    lines = json.loads(path.read_text(encoding='utf-8'))
    if len(lines) != 16 or any(len(line) > 74 or not line.isascii() for line in lines):
        raise ValueError('Exactly sixteen ASCII lines of at most 74 characters are required')
    data = b''.join(line.encode('ascii').ljust(128, b' ') for line in lines)
    (ROOT / 'rtl/ui_panel_text.hex').write_text(''.join(f'{b:02x}\n' for b in data), encoding='ascii')
    mif = 'DEPTH = 2048;\nWIDTH = 8;\nADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\nCONTENT BEGIN\n'
    mif += ''.join(f'{n:03X} : {b:02X};\n' for n, b in enumerate(data)) + 'END;\n'
    (ROOT / 'rtl/ui_panel_text.mif').write_text(mif, encoding='ascii')

if __name__ == '__main__':
    main()
