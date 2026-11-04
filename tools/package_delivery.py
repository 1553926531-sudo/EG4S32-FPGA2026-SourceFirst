from hashlib import sha256
import zipfile


def stream_sha(stream):
    digest = sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b''):
        digest.update(block)
    return digest.hexdigest()


def file_sha(path):
    with path.open('rb') as stream:
        return stream_sha(stream)


def create_archive(files, archive):
    manifest = {name: file_sha(path) for name, path in files.items()}
    manifest_text = ''.join((f'{digest}  {name}\n' for name, digest in manifest.items()))
    with archive.open('xb') as stream:
        with zipfile.ZipFile(stream, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
            for name, path in files.items():
                zf.write(path, name)
            zf.writestr('FILE_MANIFEST.sha256', manifest_text)
    with zipfile.ZipFile(archive, 'r') as zf:
        expected = set(files) | {'FILE_MANIFEST.sha256'}
        if len(zf.namelist()) != len(expected) or set(zf.namelist()) != expected:
            raise RuntimeError('ZIP member list mismatch')
        if zf.read('FILE_MANIFEST.sha256').decode('utf-8') != manifest_text:
            raise RuntimeError('ZIP internal hash manifest mismatch')
        for name, path in files.items():
            with zf.open(name) as stream:
                if stream_sha(stream) != manifest[name]:
                    raise RuntimeError(f'ZIP member readback failed: {name}')
            if file_sha(path) != manifest[name]:
                raise RuntimeError(f'Source changed during packaging: {name}')
    return dict(files=len(files), archive_sha256=file_sha(archive), manifest_text=manifest_text)
