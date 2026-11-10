#!/usr/bin/env python3
"""Create a local, checksummed source-package candidate. Does not publish or upload."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

SOURCE_HASH = 'f92f91d01a24fbed6c863495b2ee8c6a6788144a02858b75743f0946668de8a2'
DECODER_HASH = 'cc5057552aa9dddedcda73ea8889854e8a257eb07d0a561b7234465c1e856f22'
PACKAGE = 'FunASRNanoANE-v1.mlpackage'


def digest(path):
    result = hashlib.sha256()
    with path.open('rb') as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b''):
            result.update(chunk)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--package', type=Path, required=True)
    parser.add_argument('--encoder-gguf', type=Path, required=True)
    parser.add_argument('--decoder-gguf', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        raise FileExistsError(args.output)
    if digest(args.encoder_gguf) != SOURCE_HASH:
        raise ValueError('encoder weights do not match the validated v1 source')
    decoder = args.decoder_gguf or args.encoder_gguf.with_name('qwen3-0.6b-q4km.gguf')
    if digest(decoder) != DECODER_HASH:
        raise ValueError('decoder weights do not match the validated v1 pairing')
    if args.package.suffix != '.mlpackage' or not args.package.is_dir():
        raise ValueError('a source .mlpackage is required, not a compiled .mlmodelc')
    files = []
    for path in sorted(args.package.rglob('*')):
        if path.is_symlink():
            raise ValueError('source package must not contain symbolic links')
        if path.is_file():
            files.append({'path': path.relative_to(args.package).as_posix(), 'size': path.stat().st_size,
                          'sha256': digest(path)})
    paths = {entry['path'] for entry in files}
    if not {'Manifest.json', 'Data/com.apple.CoreML/model.mlmodel'}.issubset(paths):
        raise ValueError('incomplete source package')
    manifest = {'schemaVersion': 1, 'modelID': 'funasr-nano-ane-v1', 'contract': 'nano-gguf-ane-v1-buckets',
                'minimumMacOSMajor': 15, 'sourceEncoderSHA256': SOURCE_HASH, 'decoderSHA256': DECODER_HASH,
                'packageDirectory': PACKAGE, 'files': files}
    args.output.mkdir(parents=True)
    shutil.copytree(args.package, args.output / PACKAGE)
    manifest_path = args.output / 'manifest.json'
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
    (args.output / 'README.md').write_text('''# Fun-ASR Nano ANE candidate

Local candidate only; no hosting repository or release has been configured.
Import this directory in Stet's transcription settings. Stet verifies the files,
compiles on the target Mac, prepares all four lengths at the final path, and
activates acceleration when transcription is idle. CPU assets remain required.

Source: https://huggingface.co/FunAudioLLM/Fun-ASR-Nano-GGUF
Weights are derived from FunAudioLLM/Fun-ASR-Nano-2512. Review upstream model
license and attribution requirements before public redistribution.

Validation to date: M4 Pro/macOS 27.2, limited public speech examples and local
stress cases. Other hardware, minimum supported macOS and larger accuracy sets
still require release validation. Initial preparation can take several minutes.
''')
    print(json.dumps({'candidate': str(args.output.resolve()), 'manifest_sha256': digest(manifest_path),
                      'manifest_bytes': manifest_path.stat().st_size,
                      'package_bytes': sum(entry['size'] for entry in files)}, indent=2))


if __name__ == '__main__':
    main()
