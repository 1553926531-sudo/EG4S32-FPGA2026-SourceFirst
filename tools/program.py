import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_BIT = ROOT / 'bitstream/media_player.bit'
DEFAULT_SHA = '9f46370b796f8bda3b004b857217137cf4ad5d83ad8c7f857e0859132c8632b5'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description='Program EG4S20 SRAM or persistent configuration Flash with Anlogic TD')
    parser.add_argument('--mode', required=True, choices=['sram', 'flash', 'verify'])
    parser.add_argument('--td', type=Path, default=Path('C:/Anlogic/TD_5.6.5_SP3_151.449/bin/td_commands_prompt.exe'))
    parser.add_argument('--bit', type=Path, default=DEFAULT_BIT)
    parser.add_argument('--sha256')
    parser.add_argument('--timeout', type=int, default=900)
    parser.add_argument('--dry-run', action='store_true', help='Write the command plan without opening the downloader')
    args = parser.parse_args()
    bit = args.bit.resolve()
    if not bit.is_file():
        parser.error('Bitstream file does not exist')
    expected = args.sha256 or (DEFAULT_SHA if bit == DEFAULT_BIT.resolve() else None)
    if not expected or not re.fullmatch('[0-9a-fA-F]{64}', expected):
        parser.error('An alternate bitstream requires --sha256 with its full SHA-256')
    actual = sha(bit)
    if actual.lower() != expected.lower():
        parser.error('Bitstream SHA-256 mismatch')
    if args.timeout < 900:
        parser.error('Use a timeout of at least 900 seconds')
    if not args.dry_run and not args.td.is_file():
        parser.error('TD executable does not exist; specify --td')
    if any(c in bit.as_posix() for c in '{}\n\r'):
        parser.error('The bitstream path contains unsupported Tcl characters')
    operations = dict(sram=['jtag_burst'], flash=['program_spi', 'verify_spi'], verify=['verify_spi'])[args.mode]
    folder = ROOT / 'verification' / ('program_'+datetime.now().strftime('%Y%m%d_%H%M%S_%f')+'_'+args.mode)
    folder.mkdir(parents=True)
    commands = [f'set bit_file {{{bit.as_posix()}}}',
                'if {[catch {read_device_id -level 1 -total 1 -cable 0} id]} {puts stderr "DEVICE_READ_FAILED=$id"; exit 1}',
                'puts "IDENTIFIED=$id"',
                'if {$id ne "EAGLE_S20_BG256"} {puts stderr "DEVICE_MISMATCH"; exit 1}']
    for operation in operations:
        commands.extend([f'if {{[catch {{download -bit $bit_file -mode {operation} -spd 1 -cable 0}} result]}} {{',
                         'puts stderr "PROGRAM_FAILED=$result"', 'exit 1', '}',
                         f'puts "DELIVERY_{operation}_RETURNED=$result"'])
    commands += ['puts "DELIVERY_PROGRAM_RETURNED"', 'exit 0']
    tcl = folder / 'program.tcl'
    tcl.write_text('\n'.join(commands)+'\n', encoding='ascii')
    report = dict(started=datetime.now().astimezone().isoformat(), mode=args.mode,
                  bitstream=str(bit), bitstream_sha256=actual, dry_run=args.dry_run,
                  operations=operations, device_expected='EAGLE_S20_BG256', hardware_accessed=False,
                  passed=False)
    try:
        if args.dry_run:
            report['plan_validated'] = True
        else:
            log_path = folder / 'program.log'
            report['hardware_accessed'] = True
            with log_path.open('x', encoding='utf-8') as log:
                result = subprocess.run([str(args.td.resolve())], input='source {'+tcl.as_posix()+'}\n',
                                        text=True, encoding='utf-8', errors='replace', cwd=ROOT,
                                        stdout=log, stderr=subprocess.STDOUT, timeout=args.timeout)
            text = log_path.read_text(encoding='utf-8')
            checks = dict(exit_zero=result.returncode == 0,
                          identified='IDENTIFIED=EAGLE_S20_BG256' in text,
                          no_errors=not re.search(r'\b(?:ERROR|FATAL|FAILED|failure|DEVICE_MISMATCH)\b', text, re.I),
                          returned='DELIVERY_PROGRAM_RETURNED' in text,
                          bit_unchanged=sha(bit) == actual)
            for operation in operations:
                checks[operation+'_returned'] = f'DELIVERY_{operation}_RETURNED=' in text
                checks[operation+'_finished'] = bool(re.search(r'finish command "download [^\r\n]+-mode '+operation+r' -spd 1 -cable 0"', text))
            report.update(checks=checks, exit_code=result.returncode, log_sha256=sha(log_path), passed=all(checks.values()))
    except (OSError, subprocess.TimeoutExpired) as error:
        report['error'] = str(error)
    report['completed'] = datetime.now().astimezone().isoformat()
    (folder/'result.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report, indent=2))
    print('Evidence directory: '+str(folder))
    return 0 if report.get('plan_validated') or report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
