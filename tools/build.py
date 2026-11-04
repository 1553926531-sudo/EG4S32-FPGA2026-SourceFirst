
from cli_zh import EnglishArgumentParser, run
from datetime import datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from td_timing import parse_timing
from keep_directives import restore

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TD = Path('C:/Anlogic/TD_5.6.5_SP3_151.449/bin/td_commands_prompt.exe')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = EnglishArgumentParser(description='Build with TD only. Does not access or program hardware, Flash, or the TF card.')
    p.add_argument('--td', type=Path, default=DEFAULT_TD, help='Anlogic TD command-line executable')
    p.add_argument('--build-root', type=Path, default=Path(tempfile.gettempdir()) / 'tf_hdmi_build', help='Short output directory for TD projects; avoids the Windows path-length limit')
    p.add_argument('--map', type=Path, help='Verilog map from export_map.py, with matching JSON')
    p.add_argument('--validation-map', action='store_true', help='Offline validation only: synthetic sector map; never use with a real card')
    p.add_argument('--synthesis-only', action='store_true', help='Synthesis only, without placement or routing')
    a = p.parse_args()
    if a.map and a.validation_map:
        p.error('Do not combine --map and --validation-map')
    if not a.td.is_file():
        raise FileNotFoundError(f'TD executable not found: {a.td}')
    build_tools = {f'tools/{name}': sha(ROOT / 'tools' / name)
                   for name in ('build.py', 'export_map.py', 'td_timing.py', 'keep_directives.py')}
    stamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    job = a.build_root.resolve() / ('offline_' + stamp if a.validation_map else 'native_' + stamp)
    job.mkdir(parents=True)
    sources = []
    original_sources = {}
    for f in sorted((ROOT / 'rtl').glob('*.mif')):
        shutil.copyfile(f, job / f.name)
        original_sources[f'rtl/{f.name}'] = sha(f)
    for f in sorted((ROOT / 'rtl').glob('*.v')):
        if f.name != 'media_extent_map.v':
            (job / f.name).write_text(restore(f.read_text(encoding='ascii')), encoding='ascii')
            original_sources[f'rtl/{f.name}'] = sha(f)
            if f.name in ('ui_font_zh_sync.v', 'media_storage.v', 'ui_panel_text.v'):
                source = (job / f.name).read_text(encoding='ascii')
                prefix, count = ('ui_font', 2) if f.name == 'ui_font_zh_sync.v' else ('storage_rom', 3)
                for bank in range(count):
                    source = source.replace(f'"{prefix}_{bank}.mif"', f'"{(job / f"{prefix}_{bank}.mif").as_posix()}"')
                source = source.replace('"ui_panel_text.mif"', f'"{(job / "ui_panel_text.mif").as_posix()}"')
                (job / f.name).write_text(source, encoding='ascii')
            sources.append(job / f.name)
    mapped = job / 'media_extent_map.v'
    if a.validation_map:
        from export_map import emit_rom
        emit_rom([(0, 2048, 20000)], 20000, 0x12345678, mapped)
        mapping = {'purpose': 'Synthetic allocation for offline checks only; never use with a real card'}
    elif a.map:
        from export_map import emit_rom
        data = json.loads(a.map.with_suffix('.json').read_text(encoding='utf-8'))
                                                                                   
        emit_rom(data['extents'], data['sectors'], data['header']['header_crc'], mapped)
        if mapped.read_bytes() != a.map.read_bytes():
            raise ValueError('Map Verilog and JSON disagree; rerun the read-only exporter')
        mapping = data
    else:
                                                                            
                                                                    
        shutil.copyfile(ROOT / 'rtl/media_extent_map.v', mapped)
        mapping = {'mode': 'runtime FAT32/exFAT discovery', 'fixed_extents_used': False}
    mapping_files = {}
    if a.map:
        for path in (a.map, a.map.with_suffix('.json'), a.map.with_suffix('.card.json')):
            if path.is_file():
                relative = path.resolve().relative_to(ROOT).as_posix()
                mapping_files[relative] = sha(path)
    sources.append(mapped)
    for name in ('media_player.adc', 'media_player.sdc'):
        shutil.copyfile(ROOT / name, job / name)
        sources.append(job / name)
    project = job / 'project'
                                                                              
                                                                          
                                                                             
    physical_options = {'route.effort': 'high', 'route.fix_hold': 'off'}
    commands = [f'create_project -family EG4 -device EG4S20BG256 media_player {{{project.as_posix()}}}',
                *(f'add_files {{{f.as_posix()}}}' for f in sources),
                'top_module media_player_top',
                *(f'set_param {key.replace(".", " ")} {value} -run phy_1 -projmngr'
                  for key, value in physical_options.items()),
                'launch_runs syn_1', 'wait_run syn_1']
    if not a.synthesis_only:
        commands += ['launch_runs phy_1', 'wait_run phy_1']
    commands += ['close_project', 'puts "MEDIA_BUILD_RETURNED"', 'exit 0']
    tcl = job / 'build.tcl'
    tcl.write_text('\n'.join(commands) + '\n', encoding='ascii')
    log = job / 'build.log'
    with log.open('w', encoding='utf-8') as stream:
        r = subprocess.run([str(a.td)], input=f'source {{{tcl.as_posix()}}}\n',
                           stdout=stream, stderr=subprocess.STDOUT, cwd=job,
                           text=True, encoding='utf-8', errors='replace', timeout=1800)
    text = log.read_text(encoding='utf-8', errors='replace')
                                                                     
                                                                              
    bits = list((project / 'media_player_Runs' / 'phy_1').glob('*.bit'))
    errors = [x for x in text.splitlines() if re.search(r'\bERROR\s*:|\bError:', x)]
    detail_files = sorted(project.rglob('*_phy.timing'))
    summary_files = sorted(project.rglob('*_phy.tsm'))
    timing_result = parse_timing(
        detail_files[0].read_text(encoding='utf-8', errors='replace') if len(detail_files) == 1 else '',
        summary_files[0].read_text(encoding='utf-8', errors='replace') if len(summary_files) == 1 else '')
    timing, timing_passed = timing_result['timing'], timing_result['timing_passed']
    tools_changed = [name for name, digest in build_tools.items() if sha(ROOT / name) != digest]
    source_changes = [name for name, digest in original_sources.items() if sha(ROOT / name) != digest]
    evidence_files = ([log, tcl] + list(job.glob('*.mif')) + detail_files + summary_files
                      + sorted(project.rglob('run.log')))
    manifest = dict(created=datetime.now().astimezone().isoformat(), exit_code=r.returncode,
                    build_marker='MEDIA_BUILD_RETURNED' in text, tool_errors=errors,
                    validation_only=a.validation_map, synthesis_only=a.synthesis_only,
                    sources={f.name: sha(f) for f in sources}, original_sources=original_sources,
                    original_sources_changed=source_changes, mapping=mapping,
                    tool_options=physical_options, evidence_version=2,
                    build_tool_sha256=build_tools, build_tools_changed=tools_changed,
                    mapping_files_sha256=mapping_files,
                    evidence_sha256={f.relative_to(job).as_posix(): sha(f) for f in evidence_files},
                    bitstreams={str(b.relative_to(job)): sha(b) for b in bits},
                    **timing_result,
                    hardware_tested=False, downloaded=False, flash_written=False)
    (job / 'build_manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding='utf-8')
    print(json.dumps({'job': str(job), 'exit_code': r.returncode, 'errors': errors,
                      'bitstreams': list(manifest['bitstreams']), 'marker': manifest['build_marker'],
                      'timing_passed': timing_passed,
                      'setup_errors': sum(row['setup_errors'] for row in timing),
                      'hold_errors': sum(row['hold_errors'] for row in timing)}, indent=2))
    if r.returncode or errors or tools_changed or source_changes or not manifest['build_marker'] or (not a.synthesis_only and (not bits or not timing_passed)):
        print(text[-4500:])
        raise SystemExit(1)


if __name__ == '__main__':
    run(main)
