
from cli_zh import EnglishArgumentParser, run
import hashlib
from datetime import datetime
import json
import os
from pathlib import Path
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
TESTS = {'header_check': ['rtl/eg_memory.v', 'rtl/image_scaler.v', 'rtl/media_sequencer_v2.v', 'tests/tb_header_check.v'], 'sequencer_v2': ['rtl/eg_memory.v', 'rtl/image_scaler.v', 'rtl/media_sequencer_v2.v', 'verification/seq_v2_map.v', 'tests/tb_sequencer_v2.v'], 'v3_seek': ['rtl/eg_memory.v', 'rtl/image_scaler.v', 'rtl/media_sequencer.v', 'rtl/media_sequencer_v2.v', 'rtl/media_dispatch.v', 'verification/v3_seek_map.v', 'tests/tb_v3_seek.v'], 'v3_media': ['rtl/eg_memory.v', 'rtl/image_scaler.v', 'rtl/media_sequencer.v', 'rtl/media_sequencer_v2.v', 'rtl/media_dispatch.v', 'verification/v3_fixture_map.v', 'tests/tb_v3_media.v'], 'sd_dma': ['rtl/eg_memory.v', 'rtl/tf_native_media_reader.v', 'tests/tb_sd_dma.v'], 'top_compile': ['tests/tb_top_compile.v', 'rtl/eg_memory.v', 'rtl/audio_waveform.v', 'rtl/stream_fifo.v', 'rtl/sdram.v', 'rtl/sdram_burst.v', 'rtl/frame_store.v', 'rtl/pixel_pll.v', 'rtl/audio_pll.v', 'rtl/media_hdmi_lut.v', 'rtl/sii9134_i2c_writer.v', 'rtl/tf_native_media_reader.v', 'rtl/media_sequencer.v', 'rtl/media_sequencer_v2.v', 'rtl/image_scaler.v', 'rtl/media_dispatch.v', 'rtl/media_ui_ctrl.v', 'rtl/ui_player_panel.v', 'rtl/video_scan_enhanced.v', 'rtl/ui_font_zh.v', 'rtl/ui_font_zh_sync.v', 'rtl/ui_osd_layout.v', 'rtl/status_uart.v', 'rtl/media_extent_map.v', 'rtl/i2s_player.v', 'rtl/media_player_top.v'], 'player_scan': ['rtl/eg_memory.v', 'rtl/audio_waveform.v', 'rtl/ui_font_zh.v', 'rtl/ui_font_zh_sync.v', 'rtl/ui_osd_layout.v', 'rtl/ui_player_panel.v', 'rtl/video_scan_enhanced.v', 'tests/tb_player_scan.v'], 'ui': ['rtl/media_ui_ctrl.v', 'tests/tb_media_ui_ctrl.v'], 'ui_start': ['rtl/media_ui_ctrl.v', 'tests/tb_ui_start.v'], 'i2s': ['rtl/i2s_player.v', 'tests/tb_i2s.v'], 'i2s_pause': ['rtl/i2s_player.v', 'tests/tb_i2s_pause.v'], 'i2s_epoch': ['rtl/i2s_player.v', 'tests/tb_i2s_epoch.v'], 'audio_flush': ['rtl/eg_memory.v', 'rtl/stream_fifo.v', 'rtl/i2s_player.v', 'tests/tb_audio_flush.v'], 'i2s_volume': ['rtl/i2s_player.v', 'tests/tb_i2s_volume.v'], 'font_sync': ['rtl/ui_font_zh.v', 'rtl/ui_font_zh_sync.v', 'tests/tb_font_sync.v'], 'fifo': ['rtl/eg_memory.v', 'rtl/stream_fifo.v', 'tests/tb_fifo.v'], 'frame_store': ['rtl/eg_memory.v', 'rtl/stream_fifo.v', 'rtl/sdram.v', 'rtl/sdram_burst.v', 'rtl/frame_store.v', 'tests/sdram_model.v', 'tests/tb_frame_store.v'], 'frame_store_full': ['rtl/eg_memory.v', 'rtl/stream_fifo.v', 'rtl/sdram.v', 'rtl/sdram_burst.v', 'rtl/frame_store.v', 'tests/sdram_model.v', 'tests/tb_frame_store_full.v'], 'scaler': ['rtl/eg_memory.v', 'rtl/image_scaler.v', 'tests/tb_scaler.v'], 'scaler_full': ['rtl/eg_memory.v', 'rtl/image_scaler.v', 'tests/tb_scaler_full.v'], 'waveform': ['rtl/eg_memory.v', 'rtl/audio_waveform.v', 'tests/tb_waveform.v'], 'status_uart': ['rtl/status_uart.v', 'tests/tb_status_uart.v'], 'sdram': ['rtl/sdram.v', 'rtl/sdram_burst.v', 'tests/sdram_model.v', 'tests/tb_sdram.v'], 'video': ['rtl/video_scan.v', 'tests/tb_video.v'], 'sequencer': ['rtl/media_sequencer.v', 'verification/seq_map.v', 'tests/tb_sequencer.v'], 'sequencer_restart': ['rtl/media_sequencer.v', 'verification/seq_map.v', 'tests/tb_sequencer_restart.v'], 'ui_times': ['rtl/media_ui_ctrl.v', 'tests/tb_ui_times.v']}


def main():
    p = EnglishArgumentParser(description='Reproducible Icarus functional simulation, without hardware access.')
    p.add_argument('tests', nargs='*', choices=list(TESTS), help='Test names; omit to run all tests')
    p.add_argument('--iverilog', type=Path, default=ROOT / 'tools/_iverilog/bin/iverilog.exe', help='Icarus Verilog executable; also searches PATH')
    p.add_argument('--timeout', type=int, default=1800, help='Timeout per test in seconds (default: 1800)')
    p.add_argument('--simulator', choices=['icarus','verilator'], default='icarus')
    p.add_argument('--report', type=Path, help='Separate JSON report within verification; use distinct test names for concurrent suites')
    a = p.parse_args()
    ivl = str(a.iverilog) if a.iverilog.is_file() else shutil.which('iverilog')
    if not ivl:
        p.error('Icarus Verilog not found; see README for installation')
    if a.timeout < 1:
        p.error('Timeout must be a positive integer')
    vvp = str(Path(ivl).with_name('vvp.exe' if os.name == 'nt' else 'vvp'))
    out = ROOT / 'verification'
    out.mkdir(exist_ok=True)
    report_file = (ROOT / a.report).resolve() if a.report else out / 'simulation.json'
    if not report_file.is_relative_to(out.resolve()) or report_file.suffix != '.json':
        p.error('The report must be a JSON file inside verification')
    report_file.parent.mkdir(parents=True, exist_ok=True)
    old_report = json.loads(report_file.read_text(encoding='utf-8')) if report_file.exists() else []
    report = {row['test']: row for row in old_report}
    if not a.tests or any(x.startswith(('sequencer','dispatch')) for x in a.tests):
        from seq_fixture import generate
        generate(out)
        from seq_v2_fixture import generate as generate_v2
        generate_v2(out)
    if not a.tests or any(x.startswith('v3_') for x in a.tests):
        from v3_fixture import generate as generate_v3
        generate_v3(out)
    selected = a.tests or list(TESTS)
    for name in selected:
        cmd = [ivl, '-g2005', '-I', str(out), '-I', str(ROOT/'tests'), '-s', 'tb_' + name, '-o', str(out / (name + '.vvp'))]
        if name == 'top_compile':
            TESTS[name] += ['rtl/storage_cpu.v','rtl/media_storage.v','rtl/media_library.v']
        if 'rtl/ui_player_panel.v' in TESTS[name] and 'rtl/ui_panel_text.v' not in TESTS[name]:
            TESTS[name] += ['rtl/ui_panel_text.v']
        cmd += [str(ROOT / f) for f in TESTS[name]]
        dependencies = [ROOT / f for f in TESTS[name]]
        pixel_out = out / 'player_scan_frames'
        if name == 'player_scan':
            dependencies += [ROOT/'tests/tb_ui_raster.v',ROOT/'tools/check_ui_raster.py',
                             out/'ui_font.json',out/'ui_panel_text.json']
            pixel_out.mkdir(exist_ok=True)
        if 'rtl/ui_player_panel.v' in TESTS[name]:
            dependencies += [ROOT / 'rtl/ui_panel_text.hex', ROOT / 'rtl/ui_panel_text.mif']
        if name == 'top_compile':
            for bank in range(3):
                shutil.copy2(ROOT / f'rtl/storage_rom_{bank}.hex', ROOT / f'storage_rom_{bank}.hex')
                dependencies += [ROOT / f'rtl/storage_rom_{bank}.hex']
        if name == 'scaler_full':
            dependencies += [ROOT / 'tests/tb_scaler.v']
        if name in ('dispatch_v2', 'dispatch_legacy'):
            dependencies += [ROOT / ('tests/tb_sequencer_v2.v' if name == 'dispatch_v2' else 'tests/tb_sequencer.v')]
        if name == 'v3_long':
            dependencies += [ROOT / 'tests/tb_v3_media.v']
        if name.startswith('v3_'):
            dependencies += [ROOT / 'tools/v3_fixture.py']
            fixture = 'v3_long' if name == 'v3_long' else 'v3_seek' if name == 'v3_seek' else 'v3_fixture'
            dependencies += [out / (fixture + suffix) for suffix in ('.vh', '.hex')]
        if name.startswith(('sequencer', 'dispatch')):
            dependencies += sorted(out.glob('seq*.vh')) + sorted(out.glob('seq*.hex'))
        def source_hashes():
            return {str(f.relative_to(ROOT)).replace('\\', '/'): hashlib.sha256(f.read_bytes()).hexdigest()
                    for f in dependencies}
                                                                            
                                                                          
        hashes = source_hashes()
        started = datetime.now().astimezone().isoformat()
        start = time.monotonic()
        log = ''
        compile_code = None
        run_code = None
        timed_out = False
        progress_file = out / ('progress_' + name + '.txt')
        if progress_file.exists():
            progress_file.unlink()
        try:
            if a.simulator == 'verilator':
                from run_verilated import compile_model
                                                                           
                                                                           
                compiled = [ROOT/f for f in TESTS[name]]
                if name == 'player_scan':
                    compiled = [f for f in compiled if f.name != 'tb_player_scan.v'] + [ROOT/'tests/tb_ui_raster.v']
                binary = compile_model('tb_ui_raster' if name=='player_scan' else 'tb_'+name,
                                       compiled,out/('verilated_'+name))
                launch = [str(binary)]
                compile_code = 0
            else:
                r = subprocess.run(cmd, capture_output=True, text=True, errors='replace', cwd=ROOT, timeout=60)
                log += r.stdout + r.stderr
                compile_code = r.returncode
                launch = [vvp, str(out / (name + '.vvp'))]
            if name == 'player_scan':
                launch += ['+out='+pixel_out.as_posix()]
            if not compile_code:
                                                                          
                                                                          
                with progress_file.open('w', encoding='utf-8') as progress:
                    r = subprocess.run(launch, stdout=progress,
                                       stderr=subprocess.STDOUT, text=True, errors='replace',
                                       cwd=ROOT, timeout=a.timeout)
                run_code = r.returncode
        except subprocess.TimeoutExpired as exc:
            timed_out = True
            for partial in (exc.stdout, exc.stderr):
                if partial:
                    log += partial.decode(errors='replace') if isinstance(partial, bytes) else partial
            log += '\nFAIL Test timed out\n'
        if progress_file.exists():
            log += progress_file.read_text(encoding='utf-8', errors='replace')
        if name == 'player_scan' and run_code == 0 and 'PASS ui_raster' in log and 'FAIL' not in log:
            oracle = subprocess.run([__import__('sys').executable,str(ROOT/'tools/check_ui_raster.py'),
                                     '--out',str(pixel_out)],capture_output=True,text=True,cwd=ROOT,timeout=120)
            log += oracle.stdout + oracle.stderr
            if oracle.returncode:
                log += '\nFAIL Independent pixel comparison\n'
            else:
                log += '\nPASS player_scan: 15360000 independently checked pixels in fifteen scenes\n'
        final_hashes = source_hashes()
        changed = [f for f, digest in hashes.items() if final_hashes.get(f) != digest]
        if changed:
            log += '\nFAIL Inputs changed during test: ' + ', '.join(changed) + '\n'
        passed = compile_code == 0 and run_code == 0 and 'PASS ' in log and 'FAIL ' not in log and not changed
        (out / ('sim_' + name + '.log')).write_text(log, encoding='utf-8')
        row = dict(test=name, passed=passed, compile_exit=compile_code, run_exit=run_code,
                   simulator=a.simulator,
                   seconds=round(time.monotonic() - start, 3), command=cmd,
                   started=started, completed=datetime.now().astimezone().isoformat(),
                   source_sha256=hashes, source_changed=changed, timed_out=timed_out,
                   evidence_version=2)
        report[name] = row
        report_file.write_text(json.dumps(list(report.values()), indent=2), encoding='utf-8')
        print(json.dumps({k:v for k,v in row.items() if k not in ('command','source_sha256')}), flush=True)
        print(log[-1800:], flush=True)
    if not all(report[name]['passed'] for name in selected):
        raise SystemExit(1)


if __name__ == '__main__':
    run(main)
