
from datetime import datetime
from pathlib import Path
import re
import time

from cli_zh import EnglishArgumentParser, run

LINE = re.compile(rb'TFM ([0-3][0-9A-Fa-f]) ([0-9A-Fa-f]{2}) ([0-9A-Fa-f]{2}) ([0-9A-Fa-f]{8}) ([0-9A-Fa-f]{5})\r?\n?')
COMMON = {0: 'Waiting for system readiness / probing format', 1: 'Requesting sector / probing format',
          2: 'Receiving sector / probing format', 3: 'Waiting for sector completion / probing format', 4: 'Dispatching media',
          5: 'Publishing complete frame', 9: 'Reading audio buffer', 10: 'Sending audio samples',
          15: 'Draining in-flight data and reloading', 31: 'Stopped on fault'}
V2 = {0: 'Waiting for system readiness or a media selection',
      6: 'Scheduling images and continuous audio / waiting for media selection', 8: 'Waiting for clocked audio buffer read',
      13: 'Checking media header', 14: 'Checking audio range',
      16: 'Checking audio capacity', 17: 'Checking sample count', 18: 'Applying media selection',
      19: 'Checking selected audio track', 20: 'Checking track sector span',
      21: 'Checking track sample capacity', 22: 'Applying selected audio track',
      23: 'Checking image descriptor bounds', 24: 'Preparing playback seek',
      25: 'Calculating seek sector and frame', 26: 'Applying audio seek offset',
      27: 'Applying video seek position', 28: 'Restoring complete lyric cue',
      32: 'Filling the neutral background', 33: 'Publishing the neutral background',
      34: 'Waiting for the neutral background to be displayed',
      35: 'Checking media header fields', 36: 'Applying the media header validation result'}
V1 = {6: 'Waiting for frame buffer commit', 7: 'Holding video frame', 8: 'Holding standalone image',
      11: 'Waiting for audio completion', 12: 'Playback cycle complete', 13: 'Checking media layout', 14: 'Checking audio layout'}
ERRORS = {0: 'No reported error', 1: 'Invalid map or sector out of range', 2: 'Card read or initialization failed',
          3: 'Sector CRC or pixel padding error', 4: 'Invalid media format or layout', 5: 'Full image CRC failed',
          6: 'Audio sector CRC failed', 7: 'External link fault', 8: 'Invalid image descriptor',
          9: 'Image scaling failed', 10: 'Invalid audio track metadata',
          11: 'Invalid lyric cue metadata',
          0x41: 'File-system card read failed', 0x42: 'Unsupported volume or invalid boot signature',
          0x43: 'Invalid file-system geometry', 0x44: 'Invalid directory cluster chain',
          0x45: 'Invalid exFAT directory entry checksum or stream length',
          0x46: 'Directory cycle or directory capacity exceeded',
          0x47: 'Media category capacity exceeded', 0x48: 'File exceeds the supported size',
          0x51: 'Missing or unsupported selected file', 0x52: 'Invalid video file header',
          0x53: 'Invalid file offset or file cluster chain', 0x54: 'Invalid BMP format or pixel bounds',
          0x55: 'Invalid WAV container', 0x56: 'Unsupported WAV format or duration',
          0x57: 'Ambiguous or oversized matching lyric file', 0x58: 'Invalid lyric timing or text',
          0x6e: 'Storage CPU trapped on an invalid instruction or access',
          255: 'Invalid internal state'}


def decode_line(line, version='v2'):
    match = LINE.fullmatch(line)
    if not match:
        return None
    state, error, flags, lba, word = (int(value, 16) for value in match.groups())
    states = COMMON | (V2 if version == 'v2' else V1)
    ready_names = ('pixel clock', 'audio clock', 'transmitter configuration', 'card initialization', 'frame store initialization')
    faults = [name for bit, name in ((5, 'frame store'), (6, 'video underrun'), (7, 'audio underrun'))
              if flags & (1 << bit)]
    pending = [name for bit, name in enumerate(ready_names) if not flags & (1 << bit)]
    return (f'Player state: {states.get(state, "Unknown state (code " + str(state) + ")")}; '
            f'Media check: {ERRORS.get(error, "Unknown error (code " + str(error) + ")")}; '
            f'Not ready: {", ".join(pending) or "none"}; '
            f'Link faults: {", ".join(faults) or "none reported"}; '
            f'Logical sector: {lba}; Output pixel count: {word}')


def main():
    parser = EnglishArgumentParser(description='Receive player status in English; sends no serial commands and programs no hardware.')
    inputs = parser.add_mutually_exclusive_group(required=True)
    inputs.add_argument('--port', help='Serial port, for example COM9; receive only, no commands')
    inputs.add_argument('--log', type=Path, help='Parse a saved raw serial log without device access')
    parser.add_argument('--format', choices=('v2', 'v1'), default='v2', help='State engine: v2 covers TFM2/TFM3 (default); v1 is legacy')
    parser.add_argument('--seconds', type=int, default=30, help='Receive duration in seconds, positive integer (default: 30)')
    args = parser.parse_args()
    if args.seconds < 1:
        parser.error('Receive duration must be a positive integer')
    if args.log:
        count = 0
        with args.log.open('rb') as stream:
            for line in stream:
                decoded = decode_line(line, args.format)
                if decoded:
                    print(decoded)
                    count += 1
        if not count:
            raise ValueError('Log contains no complete recognizable player status lines')
        return
    try:
        import serial
    except ImportError:
        raise RuntimeError('Serial dependency missing; run python -m pip install pyserial') from None
    print('Receiving English status. Firmware reports require confirmation on the actual display and audio output.', flush=True)
    count = 0
    partial = b''
    deadline = time.monotonic() + args.seconds
    with serial.Serial(args.port, 1000000, timeout=0.5) as stream:
        while time.monotonic() < deadline:
            data = stream.read(256)
            partial += data
            while b'\n' in partial:
                line, partial = partial.split(b'\n', 1)
                decoded = decode_line(line + b'\n', args.format)
                if decoded:
                    print(datetime.now().strftime('%H:%M:%S') + ' ' + decoded, flush=True)
                    count += 1
            if len(partial) > 1024:
                partial = b''
    if not count:
        raise RuntimeError('No recognizable status received; check port, power, and running firmware version')


if __name__ == '__main__':
    run(main)
