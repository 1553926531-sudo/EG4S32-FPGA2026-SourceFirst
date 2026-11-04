
from datetime import datetime
import hashlib
import io
import json
from pathlib import Path
import sys
import time
import unittest

from cli_zh import EnglishArgumentParser, run

ROOT = Path(__file__).resolve().parents[1]


def source_hashes():
    files = (sorted((ROOT / 'tools').glob('*.py')) + sorted((ROOT / 'tests').glob('test_*.py'))
             + [ROOT / 'media_player.adc'])
    return {path.relative_to(ROOT).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in files}


def main():
    parser = EnglishArgumentParser(description='Run offline host regression and save timestamps, input hashes, and complete results.')
    parser.parse_args()
    before = source_hashes()
    started = datetime.now().astimezone().isoformat()
    timer = time.monotonic()
    log = io.StringIO()
    suite = unittest.defaultTestLoader.discover(str(ROOT / 'tests'), pattern='test_*.py')
    result = unittest.TextTestRunner(stream=log, verbosity=2).run(suite)
    after = source_hashes()
    changed = [name for name in set(before) | set(after) if before.get(name) != after.get(name)]
    passed = result.wasSuccessful() and result.testsRun > 0 and not changed
    out = ROOT / 'verification'
    out.mkdir(exist_ok=True)
    report = dict(started=started, completed=datetime.now().astimezone().isoformat(),
                  seconds=round(time.monotonic() - timer, 3), tests=result.testsRun,
                  failures=len(result.failures), errors=len(result.errors), skipped=len(result.skipped),
                  passed=passed, source_sha256=before, source_changed=changed, evidence_version=2)
    (out / 'host_regression.log').write_text(log.getvalue(), encoding='utf-8')
    (out / 'host_regression.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(log.getvalue())
    print(f'Host regression: {result.testsRun} tests, passed={passed}, failures={len(result.failures)}, errors={len(result.errors)}')
    if changed:
        print('Sources changed during test: ' + ', '.join(changed))
    if not passed:
        raise SystemExit(1)


if __name__ == '__main__':
    run(main)
