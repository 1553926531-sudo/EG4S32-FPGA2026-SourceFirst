
import math
import re


REQUIRED_CLOCKS = {'clock: clk50', 'clock: audio_clock/pll_inst.clkc[2]',
                   'clock: pixel_clock/pll_inst.clkc[2]'}


def parse_timing(detail, summary):
    rows, problems = [], []
    for section in re.split(r'Timing constraint:\s*', detail)[1:]:
        name = section.splitlines()[0].strip()
        match = re.search(r'(\d+) errors detected\s*:\s*(\d+) setup errors.*?(\d+) hold errors', section)
        if not match:
            problems.append(f'Timing section lacks aggregate error count: {name}')
            continue
        setup = [float(v) for v in re.findall(r'Slack \(setup check\):\s*([-\d.]+)', section)]
        hold = [float(v) for v in re.findall(r'Slack \(hold check\):\s*([-\d.]+)', section)]
        row = dict(constraint=name, errors=int(match[1]), setup_errors=int(match[2]),
                   hold_errors=int(match[3]), min_reported_setup_slack_ns=min(setup, default=None),
                   min_reported_hold_slack_ns=min(hold, default=None))
        rows.append(row)
        if row['errors'] or row['setup_errors'] or row['hold_errors'] or any(v < 0 for v in setup + hold):
            problems.append(f'Timing failed: {name}')
    missing = REQUIRED_CLOCKS - {row['constraint'] for row in rows}
    if missing:
        problems.append('Missing clock-domain timing report: ' + ', '.join(sorted(missing)))
    if not any(row['constraint'] == 'Input delay' for row in rows):
        problems.append('Missing SDRAM input timing section')
    if not any(row['constraint'] == 'Output delay' for row in rows):
        problems.append('Missing SDRAM output timing section')
    lines = summary.splitlines()
    global_slacks = None
    if len(lines) >= 3:
        fields = lines[2].split()
        try:
            if len(fields) >= 3 and fields[2] == 'media_player_top':
                values = [float(fields[0]), float(fields[1])]
                if all(math.isfinite(value) for value in values):
                    global_slacks = dict(setup_wns_ns=values[0], hold_wns_ns=values[1])
                    if min(values) < 0:
                        problems.append('Global timing summary contains negative slack')
        except ValueError:
            pass
    if global_slacks is None:
        problems.append('Missing verifiable global timing summary')
    return dict(timing=rows, timing_summary=global_slacks, timing_problems=problems,
                timing_passed=bool(rows) and not problems)
