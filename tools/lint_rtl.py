
import json
import hashlib
from datetime import datetime
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools/_deps'))
import pyslang as s


def main():
    dependencies = sorted((ROOT / 'rtl').glob('*.v')) + [Path(__file__)]
    def hashes():
        return {f.relative_to(ROOT).as_posix(): hashlib.sha256(f.read_bytes()).hexdigest()
                for f in dependencies}
    before = hashes()
    started = datetime.now().astimezone().isoformat()
    params = {}
    for name in ('pixel_pll.v', 'audio_pll.v'):
        text = (ROOT / 'rtl' / name).read_text()
        area = text[text.index('EG_PHY_PLL #('):text.index(') pll_inst')]
        params.update(re.findall(r'\.(\w+)\(([^\n,]+)\)', area))
    stub = '`timescale 1ns/1ps\nmodule EG_LOGIC_BUFG(input i, output o);assign o=i;endmodule\n'
    stub += 'module EG_PHY_PLL #(\n' + ',\n'.join(f'parameter {k}={v}' for k, v in params.items())
    stub += ''') (input refclk,reset,stdby,load_reg,psclk,psdown,psstep,
input [2:0] psclksel,input dclk,dcs,dwe,input [7:0] di,input [5:0] daddr,
input fbclk,output extlock,psdone,output [7:0] \\do ,output [4:0] clkc);endmodule
module EG_PHY_SDRAM_2M_32(input clk,ras_n,cas_n,we_n,input [10:0] addr,
input [1:0] ba,inout [31:0] dq,input cs_n,dm0,dm1,dm2,dm3,cke);endmodule
module EG_LOGIC_BRAM #(
parameter DATA_WIDTH_A=9, DATA_WIDTH_B=DATA_WIDTH_A,
parameter ADDR_WIDTH_A=10, ADDR_WIDTH_B=ADDR_WIDTH_A,
parameter DATA_DEPTH_A=2**ADDR_WIDTH_A, DATA_DEPTH_B=2**ADDR_WIDTH_B,
parameter BYTE_ENABLE=0, BYTE_A=1, BYTE_B=1, parameter MODE="DP",
parameter REGMODE_A="NOREG", REGMODE_B="NOREG",
parameter WRITEMODE_A="NORMAL", WRITEMODE_B="NORMAL",
parameter RESETMODE="SYNC", DEBUGGABLE="NO", PACKABLE="NO",
parameter FORCE_KEEP="OFF", INIT_FILE="NONE", FILL_ALL="NONE",
parameter IMPLEMENT="9K") (
input [DATA_WIDTH_A-1:0] dia, input [ADDR_WIDTH_A-1:0] addra,
input cea,ocea,clka,wea,rsta,input [BYTE_A-1:0] bea,
input [DATA_WIDTH_B-1:0] dib, input [ADDR_WIDTH_B-1:0] addrb,
input ceb,oceb,clkb,web,rstb,input [BYTE_B-1:0] beb,
output [DATA_WIDTH_A-1:0] doa, output [DATA_WIDTH_B-1:0] dob);
endmodule
module EG_LOGIC_MULT #(
parameter INPUT_WIDTH_A=18, INPUT_WIDTH_B=18, OUTPUT_WIDTH=36,
parameter INPUTFORMAT="SIGNED", INPUTREGA="ENABLE", INPUTREGB="ENABLE",
parameter OUTPUTREG="ENABLE", IMPLEMENT="AUTO", SRMODE="ASYNC") (
input [INPUT_WIDTH_A-1:0] a, input [INPUT_WIDTH_B-1:0] b,
input cea,ceb,cepd,clk,rstan,rstbn,rstpdn,output [OUTPUT_WIDTH-1:0] p);
endmodule
'''
    options = s.ast.CompilationOptions()
                                                                           
                                                                         
    options.flags |= s.ast.CompilationFlags.AllowUseBeforeDeclare
    comp = s.ast.Compilation(s.Bag([options]))
    comp.addSyntaxTree(s.syntax.SyntaxTree.fromText(stub))
    for path in sorted((ROOT / 'rtl').glob('*.v')):
        comp.addSyntaxTree(s.syntax.SyntaxTree.fromFile(str(path)))
    diagnostics = comp.getAllDiagnostics()
    report = s.DiagnosticEngine.reportAll(comp.sourceManager, diagnostics)
    out = ROOT / 'verification'
    out.mkdir(exist_ok=True)
    (out / 'rtl_semantic.log').write_text(report, encoding='utf-8')
    after = hashes()
    changed = [name for name in before if after.get(name) != before[name]]
    passed = not comp.hasIssuedErrors and 'error:' not in report and not changed
    summary = dict(tool='pyslang 12.1.0', passed=passed,
                   compiler_options=['AllowUseBeforeDeclare (TD Verilog compatibility)'],
                   started=started, completed=datetime.now().astimezone().isoformat(),
                   source_sha256=before, source_changed=changed, evidence_version=2,
                   diagnostics=len(diagnostics),
                   warning_categories=dict(sorted(__import__('collections').Counter(
                       re.findall(r'\[(-W[^\]]+)\]', report)).items())),
                   note='Vendor cells use interface stubs; this does not replace physical timing or board tests.')
    (out / 'rtl_semantic.json').write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding='utf-8')
    print(json.dumps({k:v for k,v in summary.items() if k != 'source_sha256'}, ensure_ascii=False))
    if not passed:
        print('\n'.join(line for line in report.splitlines() if 'error:' in line))
        raise SystemExit(1)


if __name__ == '__main__':
    main()
