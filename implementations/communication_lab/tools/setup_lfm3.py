"""Install pinned, verified local inference assets; no Godot export or global install."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import argparse
import hashlib
import json
import os
import time
import urllib.request
import urllib.error
import zipfile

VARIANT = Path(__file__).resolve().parents[1]
ROOT = VARIANT.parents[1]
MANIFEST = json.loads((VARIANT / 'data/communication/lfm3_manifest.json').read_text(encoding='utf8'))
DEST = ROOT / '.local/lfm3'


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def read_url(url, headers=None):
    request = urllib.request.Request(url, headers={'User-Agent': 'CommunicationLab-LFM3', **(headers or {})})
    with urllib.request.urlopen(request, timeout=45) as response:
        return response.read()


def install_model():
    model = MANIFEST['model']
    target = DEST / model['file']
    if target.exists() and target.stat().st_size == model['bytes'] and digest(target) == model['sha256']:
        print('Model already verified.')
        return
    url = f"https://huggingface.co/{model['repository']}/resolve/{model['revision']}/{model['file']}"
    chunks = DEST / ('chunks-' + model['sha256'][:12])
    chunks.mkdir(exist_ok=True)
    chunk_size = 8 * 1024 * 1024
    count = (model['bytes'] + chunk_size - 1) // chunk_size

    def fetch(index):
        low = index * chunk_size
        high = min(model['bytes'], low + chunk_size) - 1
        path = chunks / str(index)
        if path.exists() and path.stat().st_size == high - low + 1:
            return
        for attempt in range(3):
            try:
                data = read_url(url, {'Range': f'bytes={low}-{high}'})
                if len(data) != high - low + 1:
                    raise RuntimeError('Unexpected model HTTP range size')
                path.write_bytes(data)
                return
            except Exception:
                if attempt == 2:
                    raise
                time.sleep(1)

    print(f"Downloading {model['file']} ({model['bytes']} bytes)", flush=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        for done, _ in enumerate(pool.map(fetch, range(count)), 1):
            if done % 16 == 0:
                print(f'{done}/{count} chunks', flush=True)
    temporary = DEST / ('verified-' + model['sha256'][:12] + '.part')
    with temporary.open('wb') as output:
        for index in range(count):
            output.write((chunks / str(index)).read_bytes())
    if digest(temporary) != model['sha256']:
        raise RuntimeError('Model SHA-256 mismatch; no unverified model was installed')
    os.replace(temporary, target)


def install_runtime():
    runtime = MANIFEST['runtime']
    archive = DEST / runtime['file']
    if not archive.exists() or digest(archive) != runtime['sha256']:
        archive.write_bytes(read_url(runtime['url']))
    if digest(archive) != runtime['sha256']:
        raise RuntimeError('Runtime SHA-256 mismatch')
    destination = (DEST / 'llama').resolve()
    with zipfile.ZipFile(archive) as package:
        for member in package.namelist():
            if not (destination / member).resolve().is_relative_to(destination):
                raise RuntimeError('Unsafe runtime archive path')
        package.extractall(destination)


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', choices=['lfm3', *MANIFEST['comparison_models']], default='lfm3')
    args = parser.parse_args()
    if args.model != 'lfm3':
        MANIFEST['model'] = MANIFEST['comparison_models'][args.model]
    DEST.mkdir(parents=True, exist_ok=True)
    print('Model license:', MANIFEST['model']['license_url'])
    print('Assets stay in', DEST)
    install_runtime()
    install_model()
    model = MANIFEST['model']
    for name in ['LICENSE', 'README.md']:
        url = f"https://huggingface.co/{model['repository']}/resolve/{model['revision']}/{name}"
        license_dir = DEST / ('provenance-' + args.model)
        license_dir.mkdir(exist_ok=True)
        try:
            content = read_url(url)
        except urllib.error.HTTPError as error:
            if error.code != 404 or name != 'LICENSE' or not model.get('source_repository'): raise
            content = read_url(model.get('license_text_url') or f"https://huggingface.co/{model['source_repository']}/resolve/main/LICENSE")
        (license_dir / name).write_bytes(content)
    print(MANIFEST['model']['name'] + ' assets verified. See docs/local_language_integration.md before enabling the experimental profile.')
