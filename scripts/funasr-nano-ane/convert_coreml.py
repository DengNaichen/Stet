#!/usr/bin/env python3
"""Convert Fun-ASR-Nano encoder+adaptor GGUF → CoreML mlprogram."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

import coremltools as ct
import numpy as np
import torch

sys.path.insert(0, str(Path(__file__).resolve().parent))

from load_gguf import load_encoder_from_gguf

BUCKETS = [128, 256, 512, 1024, 1800]
FEATURE_DIM = 560
DEFAULT_GGUF = (
    Path.home() / "Library/Application Support/Stet/Models/Fun-ASR-Nano/funasr-encoder-f16.gguf"
)
DEFAULT_OUT = Path.home() / "Library/Application Support/Stet/Models/Fun-ASR-Nano"


def _pick_bucket(frames: int) -> int:
    for bucket in BUCKETS:
        if frames <= bucket:
            return bucket
    raise ValueError(f"sequence length {frames} exceeds max bucket {BUCKETS[-1]}")


def _pad_speech(speech: torch.Tensor, bucket: int) -> torch.Tensor:
    frames = speech.shape[1]
    if frames == bucket:
        return speech
    pad = speech.new_zeros(speech.shape[0], bucket - frames, speech.shape[2])
    return torch.cat([speech, pad], dim=1)


@torch.no_grad()
def _torch_check(model: torch.nn.Module) -> None:
    torch.manual_seed(0)
    frames = 40
    speech = torch.randn(1, frames, FEATURE_DIM)
    lengths = torch.tensor([frames], dtype=torch.int32)
    exact = model(speech, lengths)
    padded = model(_pad_speech(speech, 128), lengths)
    delta = (exact - padded[:, :frames]).abs().max().item()
    print(f"torch padded vs exact max|Δ|={delta:.6g}")
    if delta > 1e-4:
        raise RuntimeError("padding mask leaked into valid frames")
    if not torch.isfinite(exact).all():
        raise RuntimeError("torch encoder produced non-finite values")


def convert(gguf_path: Path, output_dir: Path, skip_compile: bool) -> Path:
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"loading {gguf_path}")
    started = time.time()
    model = load_encoder_from_gguf(gguf_path)
    model.eval()
    print(f"loaded encoder in {time.time() - started:.1f}s")
    _torch_check(model)

    example_speech = torch.zeros(1, BUCKETS[0], FEATURE_DIM)
    example_lengths = torch.tensor([BUCKETS[0]], dtype=torch.int32)
    with torch.no_grad():
        traced = torch.jit.trace(model, (example_speech, example_lengths), strict=False)
        traced.eval()

    enumerated = ct.EnumeratedShapes(
        shapes=[[1, bucket, FEATURE_DIM] for bucket in BUCKETS],
        default=[1, BUCKETS[0], FEATURE_DIM],
    )
    print("converting to mlprogram (fp16, CPU_ONLY)...")
    started = time.time()
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="speech", shape=enumerated, dtype=np.float32),
            ct.TensorType(name="speech_lengths", shape=(1,), dtype=np.int32),
        ],
        outputs=[ct.TensorType(name="audio_embeds", dtype=np.float32)],
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.macOS14,
        compute_precision=ct.precision.FLOAT16,
        compute_units=ct.ComputeUnit.CPU_ONLY,
    )
    print(f"converted in {time.time() - started:.1f}s")

    torch.manual_seed(0)
    frames = 40
    speech_np = torch.randn(1, frames, FEATURE_DIM).numpy().astype(np.float32)
    padded_np = np.zeros((1, 128, FEATURE_DIM), dtype=np.float32)
    padded_np[:, :frames] = speech_np
    with torch.no_grad():
        torch_out = model(
            torch.from_numpy(padded_np), torch.tensor([frames], dtype=torch.int32)
        ).numpy()
    coreml_out = mlmodel.predict(
        {"speech": padded_np, "speech_lengths": np.array([frames], dtype=np.int32)}
    )
    embeds = np.array(next(iter(coreml_out.values())))
    if not np.isfinite(embeds).all():
        raise RuntimeError("CoreML encoder produced non-finite values; check compute units")
    delta = np.max(np.abs(torch_out[:, :frames] - embeds[:, :frames]))
    print(f"coreml vs torch valid frames max|Δ|={delta:.6g} shape={embeds.shape}")

    package = output_dir / "FunASRNanoEncoder.mlpackage"
    if package.exists():
        subprocess.run(["rm", "-rf", str(package)], check=True)
    mlmodel.save(str(package))
    print(f"saved {package}")
    compiled = output_dir / "FunASRNanoEncoder.mlmodelc"
    if skip_compile:
        return package
    if compiled.exists():
        subprocess.run(["rm", "-rf", str(compiled)], check=True)
    subprocess.run(
        ["xcrun", "coremlcompiler", "compile", str(package), str(output_dir)],
        check=True,
    )
    print(f"compiled {compiled}")
    return compiled


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gguf", type=Path, default=DEFAULT_GGUF)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--skip-compile", action="store_true")
    args = parser.parse_args()
    convert(args.gguf, args.output_dir, args.skip_compile)


if __name__ == "__main__":
    os.environ.setdefault("PYTORCH_ENABLE_MPS_FALLBACK", "1")
    main()
