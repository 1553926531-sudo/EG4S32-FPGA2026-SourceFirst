
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]


def compile_model(top, sources, out, cwd=ROOT, parameters=None):
    out.mkdir(parents=True, exist_ok=True)
    obj = out / 'obj'
    home = Path(os.environ.get('VERILATOR_ROOT', str(ROOT/'tools/_verilator/verilator')))
    zig = os.environ.get('TF_ZIG', str(ROOT/'tools/_zig/ziglang/zig.exe'))
    env = dict(os.environ, VERILATOR_ROOT=str(home))
    generate = [str(home/'bin/verilator_bin.exe'), '--cc', '--timing', '--main',
                '--top-module', top, '--Mdir', str(obj), '-D__ICARUS__', '-Wno-fatal',
                '-I'+str(ROOT/'verification'), '-I'+str(ROOT/'tests'),
                *[f'-G{k}={v}' for k,v in (parameters or {}).items()], *map(str, sources)]
    with (out/'compile.log').open('w') as log:
        subprocess.run(generate, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=180)
        cpp = list(obj.glob('*.cpp'))
        cpp += [home/'include'/name for name in ['verilated.cpp', 'verilated_timing.cpp', 'verilated_threads.cpp']]
        binary = out/'simulation.exe'
        command = [str(zig), 'c++', '-std=c++20', '-O2', '-DVL_TIME_CONTEXT',
                   '-DVM_TRACE=0', '-I'+str(home/'include'), '-I'+str(obj),
                   *map(str,cpp), '-o', str(binary)]
        subprocess.run(command, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=600)
    return binary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--top', required=True)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--cwd', type=Path, default=ROOT)
    parser.add_argument('--timeout', type=int, default=900)
    parser.add_argument('--simarg', action='append', default=[])
    parser.add_argument('sources', nargs='+')
    args = parser.parse_args()
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=True)
    sources = [ROOT / name for name in args.sources]
    hashes = {str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    binary = compile_model(args.top, sources, out, args.cwd)
    started=time.time()
    with (out/'run.log').open('w') as log:
        result=subprocess.run([str(binary), *args.simarg], cwd=args.cwd, stdout=log,
                              stderr=subprocess.STDOUT, timeout=args.timeout)
    text=(out/'run.log').read_text()
    changed=[name for name,digest in hashes.items() if hashlib.sha256((ROOT/name).read_bytes()).hexdigest()!=digest]
    passed=result.returncode==0 and 'PASS' in text and 'FAIL' not in text and not changed
    (out/'simulator.json').write_text(json.dumps(dict(passed=passed, simulator='Verilator (see run.log for exact build)',
        duration_seconds=time.time()-started, inputs=hashes, changed=changed, exit_code=result.returncode),indent=2))
    print(text,flush=True)
    return 0 if passed else 1


if __name__=='__main__':
    raise SystemExit(main())
