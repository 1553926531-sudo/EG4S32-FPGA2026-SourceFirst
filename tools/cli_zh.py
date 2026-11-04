
import argparse
import subprocess
import sys


class EnglishArgumentParser(argparse.ArgumentParser):
    def __init__(self, *args, **kwargs):
        kwargs['add_help'] = False
        super().__init__(*args, **kwargs)
        self._positionals.title = 'positional arguments'
        self._optionals.title = 'options'
        self.add_argument('-h', '--help', action='help', help='show this help message and exit')

    def error(self, message):
        self.print_usage(sys.stderr)
        self.exit(2, f'{self.prog}: argument error: {message}\n')


                                                             
ChineseArgumentParser = EnglishArgumentParser


def run(main):
    try:
        main()
    except KeyboardInterrupt:
        print('Operation cancelled by user.', file=sys.stderr)
        raise SystemExit(130) from None
    except subprocess.TimeoutExpired:
        print('Operation failed: external tool timed out.', file=sys.stderr)
        raise SystemExit(1) from None
    except (OSError, ValueError, RuntimeError) as exc:
        labels = ((FileNotFoundError, 'File or path not found'),
                  (FileExistsError, 'Destination exists; refusing to overwrite'),
                  (PermissionError, 'Permission denied or device busy'),
                  (IsADirectoryError, 'Expected a file, found a directory'),
                  (NotADirectoryError, 'Expected a directory, found a file'))
        message = str(exc)
        if isinstance(exc, OSError) and exc.filename:
            label = next((text for kind, text in labels if isinstance(exc, kind)), 'File or device access failed')
            message = f'{label}: {exc.filename}'
        elif isinstance(exc, OSError) and (getattr(exc, 'winerror', None) or exc.errno):
            message = f'File or device operation failed; system code: {getattr(exc, "winerror", None) or exc.errno}'
        print(f'Operation failed: {message}', file=sys.stderr)
        raise SystemExit(1) from None
