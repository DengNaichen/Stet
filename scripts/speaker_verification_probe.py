#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "numpy>=1.26,<3",
#   "sherpa-onnx>=1.13,<2",
# ]
# ///
"""Record enrollment clips and compare speaker-embedding similarities.

Run with ``uv run scripts/speaker_verification_probe.py --help``.
The reported score is cosine similarity, not a calibrated probability.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import statistics
import subprocess
import sys
import tempfile
import urllib.request
import wave
from datetime import datetime
from pathlib import Path
from typing import Any, Sequence


MODEL_NAME = "3dspeaker_speech_campplus_sv_zh-cn_16k-common.onnx"
MODEL_URL = (
    "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
    f"speaker-recongition-models/{MODEL_NAME}"
)
DEFAULT_MODEL_PATH = Path.home() / "Library" / "Caches" / "StetSpeakerProbe" / MODEL_NAME


def cosine_similarity(left: Sequence[float], right: Sequence[float]) -> float:
    if len(left) != len(right) or not left:
        raise ValueError("Embeddings must have the same non-zero dimension")
    numerator = sum(a * b for a, b in zip(left, right))
    left_norm = math.sqrt(sum(value * value for value in left))
    right_norm = math.sqrt(sum(value * value for value in right))
    if left_norm == 0 or right_norm == 0:
        raise ValueError("Embedding has zero magnitude")
    return numerator / (left_norm * right_norm)


def normalized(values: Sequence[float]) -> list[float]:
    magnitude = math.sqrt(sum(value * value for value in values))
    if magnitude == 0:
        raise ValueError("Embedding has zero magnitude")
    return [value / magnitude for value in values]


def centroid(embeddings: Sequence[Sequence[float]]) -> list[float]:
    if not embeddings:
        raise ValueError("No embeddings supplied")
    return normalized([sum(column) / len(embeddings) for column in zip(*embeddings)])


def self_check() -> None:
    assert math.isclose(cosine_similarity([1, 0], [1, 0]), 1.0)
    assert math.isclose(cosine_similarity([1, 0], [0, 1]), 0.0)
    assert cosine_similarity(centroid([[1, 0], [0.8, 0.2]]), [1, 0]) > 0.99
    print("self-check passed")


def require_command(name: str) -> str:
    path = shutil.which(name)
    if not path:
        raise RuntimeError(f"{name} is required but was not found in PATH")
    return path


def runtime_modules() -> tuple[Any, Any]:
    try:
        import numpy as np
        import sherpa_onnx
    except ImportError as error:
        raise RuntimeError(
            "Run this script with uv so numpy and sherpa-onnx are available: "
            "uv run scripts/speaker_verification_probe.py ..."
        ) from error
    return np, sherpa_onnx


def list_devices() -> None:
    ffmpeg = require_command("ffmpeg")
    result = subprocess.run(
        [ffmpeg, "-hide_banner", "-f", "avfoundation", "-list_devices", "true", "-i", ""],
        capture_output=True,
        text=True,
        check=False,
    )
    lines = result.stderr.splitlines()
    try:
        start = next(i for i, line in enumerate(lines) if "AVFoundation audio devices" in line)
    except StopIteration:
        print(result.stderr, file=sys.stderr)
        raise RuntimeError("ffmpeg did not report any AVFoundation audio devices")
    devices = [line for line in lines[start + 1 :] if re.search(r"\[\d+\]", line)]
    if not devices:
        raise RuntimeError(
            "No audio input devices are visible to ffmpeg; grant your terminal microphone access"
        )
    print("\n".join(devices))


def record_clips(device: str, output: Path, count: int, seconds: float) -> None:
    ffmpeg = require_command("ffmpeg")
    output.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    for index in range(1, count + 1):
        destination = output / f"me-{stamp}-{index:02d}.wav"
        input(f"[{index}/{count}] Press Enter, then speak naturally for {seconds:g} seconds...")
        subprocess.run(
            [
                ffmpeg,
                "-hide_banner",
                "-loglevel",
                "error",
                "-n",
                "-f",
                "avfoundation",
                "-i",
                f":{device}",
                "-t",
                str(seconds),
                "-ac",
                "1",
                "-ar",
                "16000",
                "-c:a",
                "pcm_s16le",
                str(destination),
            ],
            check=True,
        )
        print(destination)


def ensure_model(model: Path | None) -> Path:
    if model:
        if not model.is_file():
            raise FileNotFoundError(model)
        return model
    if DEFAULT_MODEL_PATH.is_file():
        return DEFAULT_MODEL_PATH

    DEFAULT_MODEL_PATH.parent.mkdir(parents=True, exist_ok=True)
    partial = DEFAULT_MODEL_PATH.with_suffix(".part")
    print(f"Downloading speaker model to {DEFAULT_MODEL_PATH}")
    try:
        urllib.request.urlretrieve(MODEL_URL, partial)
        partial.replace(DEFAULT_MODEL_PATH)
    except Exception:
        partial.unlink(missing_ok=True)
        raise
    return DEFAULT_MODEL_PATH


def normalize_audio(source: Path, destination: Path) -> None:
    if not source.is_file():
        raise FileNotFoundError(source)
    subprocess.run(
        [
            require_command("ffmpeg"),
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(source),
            "-vn",
            "-ac",
            "1",
            "-ar",
            "16000",
            "-c:a",
            "pcm_s16le",
            str(destination),
        ],
        check=True,
    )


def read_wave(path: Path, np: Any) -> tuple[Any, int]:
    with wave.open(str(path), "rb") as audio:
        if audio.getnchannels() != 1 or audio.getsampwidth() != 2:
            raise ValueError(f"Expected mono PCM16 WAV: {path}")
        sample_rate = audio.getframerate()
        samples = np.frombuffer(audio.readframes(audio.getnframes()), dtype="<i2")
    return np.ascontiguousarray(samples.astype("float32") / 32768.0), sample_rate


def make_extractor(model: Path, threads: int, provider: str, sherpa_onnx: Any) -> Any:
    config = sherpa_onnx.SpeakerEmbeddingExtractorConfig(
        model=str(model), num_threads=threads, debug=False, provider=provider
    )
    if not config.validate():
        raise ValueError(f"Invalid speaker embedding config: {config}")
    return sherpa_onnx.SpeakerEmbeddingExtractor(config)


def embedding(samples: Any, sample_rate: int, extractor: Any) -> list[float] | None:
    stream = extractor.create_stream()
    stream.accept_waveform(sample_rate=sample_rate, waveform=samples)
    stream.input_finished()
    if not extractor.is_ready(stream):
        return None
    return normalized(extractor.compute(stream))


def file_embedding(source: Path, extractor: Any, np: Any, temp_dir: Path) -> list[float]:
    normalized_path = temp_dir / f"{len(list(temp_dir.iterdir())):04d}.wav"
    normalize_audio(source, normalized_path)
    samples, sample_rate = read_wave(normalized_path, np)
    result = embedding(samples, sample_rate, extractor)
    if result is None:
        raise ValueError(f"Not enough usable speech in {source}")
    return result


def score_file(
    source: Path,
    reference: Sequence[float],
    extractor: Any,
    np: Any,
    temp_dir: Path,
    window_seconds: float,
    minimum_rms: float,
) -> list[dict[str, Any]]:
    normalized_path = temp_dir / f"{len(list(temp_dir.iterdir())):04d}.wav"
    normalize_audio(source, normalized_path)
    samples, sample_rate = read_wave(normalized_path, np)
    window_frames = int(window_seconds * sample_rate)
    minimum_frames = int(min(2.0, window_seconds) * sample_rate)
    scores: list[dict[str, Any]] = []

    for start in range(0, len(samples), window_frames):
        chunk = samples[start : start + window_frames]
        if len(chunk) < minimum_frames:
            continue
        rms = float(np.sqrt(np.mean(np.square(chunk))))
        if rms < minimum_rms:
            continue
        vector = embedding(chunk, sample_rate, extractor)
        if vector is None:
            continue
        scores.append(
            {
                "file": str(source),
                "start": start / sample_rate,
                "end": (start + len(chunk)) / sample_rate,
                "rms": rms,
                "similarity": cosine_similarity(reference, vector),
            }
        )
    return scores


def describe_scores(name: str, scores: Sequence[float]) -> None:
    if not scores:
        print(f"{name}: no usable segments")
        return
    print(
        f"{name}: n={len(scores)} min={min(scores):.3f} "
        f"median={statistics.median(scores):.3f} max={max(scores):.3f}"
    )


def evaluate(args: argparse.Namespace) -> None:
    np, sherpa_onnx = runtime_modules()
    model = ensure_model(args.model)
    extractor = make_extractor(model, args.threads, args.provider, sherpa_onnx)

    with tempfile.TemporaryDirectory(prefix="stet-speaker-probe-") as raw_temp:
        temp_dir = Path(raw_temp)
        enrollments = [file_embedding(path, extractor, np, temp_dir) for path in args.enroll]
        reference = centroid(enrollments)
        leave_one_out = [
            cosine_similarity(vector, centroid(enrollments[:index] + enrollments[index + 1 :]))
            for index, vector in enumerate(enrollments)
        ]
        self_rows = [
            row
            for path in args.self_test
            for row in score_file(
                path, reference, extractor, np, temp_dir, args.window, args.minimum_rms
            )
        ]
        other_rows = [
            row
            for path in args.other
            for row in score_file(
                path, reference, extractor, np, temp_dir, args.window, args.minimum_rms
            )
        ]

    self_scores = [row["similarity"] for row in self_rows] or leave_one_out
    other_scores = [row["similarity"] for row in other_rows]
    describe_scores("self", self_scores)
    describe_scores("other", other_scores)

    print(f"\nsegments (threshold={args.threshold:.3f})")
    for expected, rows in (("self", self_rows), ("other", other_rows)):
        for row in rows:
            predicted = "self" if row["similarity"] >= args.threshold else "other"
            print(
                f"{row['similarity']:.3f}  expected={expected:<5} predicted={predicted:<5} "
                f"{row['file']} [{row['start']:.1f}-{row['end']:.1f}s]"
            )

    separating_threshold = None
    if self_scores and other_scores and max(other_scores) < min(self_scores):
        separating_threshold = (max(other_scores) + min(self_scores)) / 2
        print(f"\nclean separating threshold: {separating_threshold:.3f}")
    elif self_scores and other_scores:
        print("\nno clean threshold: self and other score ranges overlap")

    if args.json_out:
        payload = {
            "model": str(model),
            "threshold": args.threshold,
            "separating_threshold": separating_threshold,
            "enrollment_leave_one_out": leave_one_out,
            "self": self_rows,
            "other": other_rows,
        }
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
        print(args.json_out)


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description=__doc__)
    root.add_argument("--self-check", action="store_true", help=argparse.SUPPRESS)
    commands = root.add_subparsers(dest="command")

    commands.add_parser("devices", help="List macOS AVFoundation audio input devices")

    record = commands.add_parser("record", help="Record several enrollment WAV files")
    record.add_argument("--device", required=True, help="Audio-device index from the devices command")
    record.add_argument("--output", type=Path, required=True)
    record.add_argument("--count", type=int, default=4)
    record.add_argument("--seconds", type=float, default=8.0)

    probe = commands.add_parser("evaluate", help="Compare self and other-speaker similarities")
    probe.add_argument("--enroll", type=Path, nargs="+", required=True)
    probe.add_argument("--self-test", type=Path, nargs="*", default=[])
    probe.add_argument("--other", type=Path, nargs="*", default=[])
    probe.add_argument("--model", type=Path)
    probe.add_argument("--provider", default="cpu")
    probe.add_argument("--threads", type=int, default=2)
    probe.add_argument("--window", type=float, default=5.0)
    probe.add_argument("--minimum-rms", type=float, default=0.005)
    probe.add_argument("--threshold", type=float, default=0.6)
    probe.add_argument("--json-out", type=Path)
    return root


def main() -> None:
    args = parser().parse_args()
    if args.self_check:
        self_check()
    elif args.command == "devices":
        list_devices()
    elif args.command == "record":
        if args.count < 1 or args.seconds <= 0:
            raise ValueError("--count and --seconds must be positive")
        record_clips(args.device, args.output, args.count, args.seconds)
    elif args.command == "evaluate":
        if len(args.enroll) < 2:
            raise ValueError("Use at least two independent enrollment recordings")
        if args.window < 2 or args.minimum_rms < 0:
            raise ValueError("--window must be at least 2 seconds and --minimum-rms cannot be negative")
        evaluate(args)
    else:
        parser().print_help()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        raise SystemExit(130)
    except Exception as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
