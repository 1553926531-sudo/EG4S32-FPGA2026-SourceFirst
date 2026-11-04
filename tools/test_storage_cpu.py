
from pathlib import Path
import json
import random
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/revision_20261103_native_files/cpu'


def signed(n):
    return n if n < 0x80000000 else n - 0x100000000


def main():
    import argparse,hashlib
    global OUT
    parser=argparse.ArgumentParser()
    parser.add_argument('--program-bits',type=int,choices=[14,32],default=32)
    args=parser.parse_args()
    OUT=OUT.with_name('cpu'+str(args.program_bits))
    OUT.mkdir(parents=True, exist_ok=True)
    code, expected = [], []
    def i(op, rd, f, rs, value):
        return ((value & 4095) << 20) | rs << 15 | f << 12 | rd << 7 | op
    def li(rd, value):
        value &= 0xffffffff
        hi = (value + 2048) & 0xfffff000
        code.extend([hi | rd << 7 | 0x37, i(0x13, rd, 0, rd, value)])
    def store(rs, base=4, offset=0, f=2):
        code.append(((offset >> 5) & 127) << 25 | rs << 20 | base << 15 | f << 12 | (offset & 31) << 7 | 0x23)
    li(4, 0x20000000)
    li(5, 0x10000000)
    rng = random.Random(20261103)
    boundary = [0, 1, 2, 31, 32, 0x7fffffff, 0x80000000, 0xffffffff]
    for n in range(256 if args.program_bits==14 else 640):
        a = boundary[n % 8] if n < 64 else rng.getrandbits(32)
        b = boundary[n // 8] if n < 64 else rng.getrandbits(32)
        li(1, a); li(2, b)
        f, top = n % 8, (n // 8) % 3
        if top == 1:
            sa, sb = signed(a), signed(b)
            q = -1 if not b else int(abs(sa) // abs(sb)) * (-1 if (sa < 0) != (sb < 0) else 1)
            result = [a*b, (sa*sb) >> 32, (sa*b) >> 32, (a*b) >> 32,
                      q, a//b if b else 0xffffffff,
                      sa-q*sb if b else sa, a % b if b else a][f]
            funct7 = 1
        else:
            alternate = top == 2
            result = [a-b if alternate else a+b, a << (b & 31), int(signed(a) < signed(b)),
                      int(a < b), a ^ b, signed(a) >> (b & 31) if alternate else a >> (b & 31), a | b, a & b][f]
            funct7 = 32 if alternate and f in (0, 5) else 0
        code.append(funct7 << 25 | 2 << 20 | 1 << 15 | f << 12 | 3 << 7 | 0x33)
        store(3); expected.append(result & 0xffffffff)
    for n in range(128):
        a = rng.getrandbits(32); li(2, a)
        store(2, 5, 0, 2)
        offset, f = n % 4, [0, 4, 1, 5, 2][n % 5]
        if f in (1, 5): offset &= 2
        if f == 2: offset = 0
        code.append(i(3, 3, f, 5, offset))
        value = a >> (offset*8)
        if f in (0, 4): value &= 255
        if f == 0 and value & 128: value -= 256
        if f in (1, 5): value &= 65535
        if f == 1 and value & 32768: value -= 65536
        store(3);expected.append(value & 0xffffffff)
    for f in [0, 1, 4, 5, 6, 7]:
        for a, b in [(0,0),(0xffffffff,1),(1,0xffffffff),(0x80000000,0x7fffffff)]:
            li(1,a);li(2,b);li(3,123)
            take = {0:a==b,1:a!=b,4:signed(a)<signed(b),5:signed(a)>=signed(b),6:a<b,7:a>=b}[f]
                                                
            code.append(2 << 20 | 1 << 15 | f << 12 | 8 << 7 | 0x63)
            code.append(i(0x13,3,0,3,7))
            store(3);expected.append(123 if take else 130)
    for n in range(64):
        before = rng.getrandbits(32); value = rng.getrandbits(32)
        li(1, before);store(1,5)
        li(2,value)
        f = n % 2; shift = n % 4 if f == 0 else (n % 4) & 2
        store(2,5,shift,f)
        code.append(i(3,3,2,5,0));store(3)
        mask = (255 if f == 0 else 65535) << (shift*8)
        expected.append(((before & ~mask) | ((value << (shift*8)) & mask)) & 0xffffffff)
    for n in range(96):
        a=rng.getrandbits(32);imm=rng.randrange(-2048,2048);f=n%8
        li(1,a)
        encoded=imm
        if f in (1,5):
            shift=n%32;encoded=shift | (1024 if f==5 and n%3==0 else 0)
        result=[a+imm,a<<(encoded&31),int(signed(a)<imm),int(a<(imm&0xffffffff)),a^(imm&0xffffffff),
                signed(a)>>(encoded&31) if encoded&1024 else a>>(encoded&31),a|(imm&0xffffffff),a&(imm&0xffffffff)][f]
        code.append(i(0x13,3,f,1,encoded));store(3);expected.append(result&0xffffffff)
                                                                         
    here=len(code)*4;code.append(0x12345000 | 3<<7 | 0x17);store(3);expected.append(here+0x12345000)
                                                                                 
    here=len(code)*4;code.append(8<<20 | 3<<7 | 0x6f);code.append(i(0x13,3,0,0,-1))
    store(3);expected.append(here+4)
    target=(len(code)+3)*4;li(1,target|1)
    here=len(code)*4;code.append(i(0x67,3,0,1,0));store(3);expected.append(here+4)
    li(3,1);store(3,4,4)
    code.append(0x0000006f)
    if len(code)*4>2**args.program_bits:raise ValueError('Program does not fit PC')
    (OUT / 'program.hex').write_text(''.join(f'{v:08x}\n' for v in code))
    (OUT / 'expected.hex').write_text(''.join(f'{v:08x}\n' for v in expected))
    iv=ROOT/'tools/_iverilog/bin/iverilog.exe'
    target=OUT/'cpu.vvp'
    subprocess.run([str(iv),'-g2005','-s','tb_storage_cpu',f'-Ptb_storage_cpu.PROGRAM_BITS={args.program_bits}','-o',str(target),str(ROOT/'rtl/eg_memory.v'),
                    str(ROOT/'rtl/storage_cpu.v'),str(ROOT/'tests/tb_storage_cpu.v')],check=True)
    r=subprocess.run([str(iv.with_name('vvp.exe')),str(target),f'+words={len(code)}',f'+checks={len(expected)}'],
                     cwd=OUT,capture_output=True,text=True,timeout=120)
    passed=r.returncode==0 and 'PASS storage CPU' in r.stdout
    inputs=[ROOT/'rtl/storage_cpu.v',ROOT/'rtl/eg_memory.v',ROOT/'tests/tb_storage_cpu.v',Path(__file__),OUT/'program.hex',OUT/'expected.hex']
    (OUT/'result.json').write_text(json.dumps(dict(passed=passed,program_bits=args.program_bits,program_bytes=len(code)*4,
        inputs={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs},stdout=r.stdout,stderr=r.stderr),indent=2))
    print(r.stdout+r.stderr)
    return 0 if passed else 1


if __name__=='__main__':
    raise SystemExit(main())
