#!/usr/bin/env python3
"""Compare shape switching before/after an isolated E5 cache purge on a real ANE.

Builds the runtime encoder directly, without replacing the app or its models.
Each probe has a unique executable name and therefore a private Core ML cache.
Only those probe caches are removed. Run serially with no other inference/builds.
"""
import argparse
from array import array
import json
import os
from pathlib import Path
import re
import shutil
import statistics
import subprocess
import tempfile
import uuid

REPO = Path(__file__).resolve().parents[2]
RUNTIME = REPO / 'Packages/StetEngine/Vendor/FunASRPackage/RuntimeSource'


def run_probe(label, source, model, root, purge):
    executable = root / f'stet-residency-{label}-{uuid.uuid4().hex}'
    subprocess.run([
        'xcrun', 'clang++', '-std=c++17', '-O2', '-fobjc-arc',
        '-framework', 'CoreML', '-framework', 'Foundation', '-I', str(RUNTIME),
        str(Path(__file__).with_name('residency_probe.mm')), str(source),
        '-o', str(executable),
    ], check=True)
    output = root / label
    output.mkdir()
    cache = Path.home() / 'Library/Caches' / executable.name
    with (output / 'stderr.log').open('w') as errors:
        process = subprocess.Popen([str(executable), str(model), str(output)],
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                   stderr=errors, text=True)
        try:
            warmup = process.stdout.readline()
            if not warmup.startswith('warmup_ms='):
                raise RuntimeError(f'{label}: warmup failed; see {output / "stderr.log"}')
            print(label, warmup.strip(), flush=True)
            if purge:
                e5cache = cache / 'com.apple.e5rt.e5bundlecache'
                if not e5cache.is_dir():
                    raise RuntimeError(f'Probe cache missing: {e5cache}; refusing to purge anything else')
                shutil.rmtree(e5cache)
            remaining, _ = process.communicate(input='\n', timeout=900)
            if process.returncode:
                raise RuntimeError(f'{label} failed with exit {process.returncode}')
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            # This randomly named cache belongs only to the probe created above.
            if cache.exists():
                shutil.rmtree(cache)
    (output / 'timings.log').write_text(warmup + remaining)
    timings = [float(value) for value in re.findall(r' ms=([\d.]+)', remaining)]
    if len(timings) != 24:
        raise RuntimeError(f'Expected 24 predictions, got {len(timings)}')
    return {'warmup_ms': float(warmup.split('=')[1]), 'prediction_ms': timings,
            'median_ms': statistics.median(timings), 'max_ms': max(timings)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--baseline-ref', default='HEAD')
    parser.add_argument('--purge-probe-cache', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=False)
    env_xcode = '/Applications/Xcode.app/Contents/Developer'
    os.environ.setdefault('DEVELOPER_DIR', env_xcode)
    with tempfile.TemporaryDirectory(prefix='stet-residency-build-') as temp:
        baseline = Path(temp) / 'baseline.mm'
        baseline.write_bytes(subprocess.check_output([
            'git', 'show', f'{args.baseline_ref}:{RUNTIME.relative_to(REPO)}/stet_funasr_coreml.mm',
        ], cwd=REPO))
        result = {'purged_probe_cache': args.purge_probe_cache}
        for label, source in [('before', baseline), ('after', RUNTIME / 'stet_funasr_coreml.mm')]:
            result[label] = run_probe(label, source, args.model.resolve(), args.output.resolve(),
                                      args.purge_probe_cache)
        differences = []
        for frames in [40, 100, 200, 400]:
            tensors = []
            for label in ['before', 'after']:
                tensor = array('f')
                tensor.frombytes((args.output / label / f'{frames}.f32').read_bytes())
                tensors.append(tensor)
            if len(tensors[0]) != frames * 1024 or len(tensors[1]) != frames * 1024:
                raise RuntimeError('Incorrect embedding shape')
            differences.append(max(abs(a - b) for a, b in zip(*tensors)))
        result['max_embedding_difference'] = max(differences)
        (args.output / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(result, indent=2), flush=True)
        assert result['max_embedding_difference'] < 0.001, 'Embedding regression'
        assert result['after']['max_ms'] < 2000, 'Foreground inference stalled'


if __name__ == '__main__':
    main()
