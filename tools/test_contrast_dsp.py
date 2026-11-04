
from pathlib import Path
import hashlib
import json
import subprocess
import time
from run_verilated import compile_model

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'verification/revision_20261103_native_files/contrast_dsp'
VENDOR = Path('C:/Anlogic/TD_5.6.5_SP3_151.449/sim_release/eg/eg_logic_mult.v')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    source = ROOT / 'rtl/video_scan_enhanced.v'
    inputs = [source, VENDOR, Path(__file__)]
    hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    text = source.read_text()
    block = text[text.index('    wire [23:0] adjusted_color;'):text.index('    reg [10:0] pipe_x;')]
                                                                          
    block = block.replace('`ifdef __ICARUS__', '`ifdef TEST_ARITHMETIC')
    prefix = '''(input wire [23:0] source_stage_color,
      input wire [7:0] source_stage_brightness,source_stage_contrast,
      output wire [23:0] result_color);
      wire pclk=0,reset_n=1;
'''
    fixture = '`timescale 1ns/1ps\nmodule contrast_vendor' + prefix + block
    fixture += 'assign result_color=adjusted_color;\nendmodule\n'
    fixture += '`define TEST_ARITHMETIC\nmodule contrast_arithmetic' + prefix + block
    fixture += 'assign result_color=adjusted_color;\nendmodule\n'
    fixture += r'''
module tb_contrast_dsp;
 reg [23:0] color=0;reg [7:0] br=0,ct=0;
 wire [23:0] vendor,arithmetic;
 contrast_vendor v(color,br,ct,vendor);
 contrast_arithmetic a(color,br,ct,arithmetic);
 integer b,c,n,k,value,delta,scaled,want,checks=0;
 initial begin
  for(c=0;c<256;c=c+1)for(b=0;b<256;b=b+1)for(n=0;n<256;n=n+1)begin
   color={8'((n+193)%256),8'((n+79)%256),8'(n)};br=b;ct=c;#1;
   for(k=0;k<3;k=k+1)begin
    value=(color>>(k*8))&255;delta=value-128;
    if(c<64)scaled=delta>>>2;
    else if(c<128)scaled=delta>>>1;
    else if(c==128)scaled=delta;
    else if(c<192)scaled=delta+(delta>>>2);
    else scaled=delta+(delta>>>1);
    want=scaled+b;if(want<0)want=0;if(want>255)want=255;
    if(((vendor>>(k*8))&255)!==want || ((arithmetic>>(k*8))&255)!==want)
     $fatal(1,"FAIL contrast v=%0d br=%0d ct=%0d channel=%0d want=%0d vendor=%h arithmetic=%h",value,b,c,k,want,vendor,arithmetic);
    checks=checks+1;
   end
  end
  $display("PASS contrast all 16777216 value/brightness/contrast combinations, three channels, vendor and arithmetic, checks=%0d",checks);
  $finish;
 end
endmodule
'''
    bench = OUT / 'tb_contrast_dsp.sv'
    bench.write_text(fixture, encoding='ascii')
    target = compile_model('tb_contrast_dsp', [bench, VENDOR], OUT / 'compiled')
    start = time.time()
    result = subprocess.run([str(target)], cwd=ROOT, capture_output=True, text=True, timeout=600)
    changed = [str(p) for p in inputs if hashlib.sha256(p.read_bytes()).hexdigest() != hashes[str(p)]]
    passed = result.returncode == 0 and 'PASS contrast' in result.stdout and 'FAIL' not in result.stdout and not changed
    (OUT / 'run.log').write_text(result.stdout + result.stderr)
    (OUT / 'result.json').write_text(json.dumps(dict(passed=passed, seconds=time.time()-start,
        source_sha256=hashes, source_changed=changed, stdout=result.stdout, stderr=result.stderr), indent=2))
    print(result.stdout, flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
