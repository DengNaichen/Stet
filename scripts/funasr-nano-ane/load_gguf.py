"""Load Fun-ASR-Nano encoder GGUF tensors into FunASRNanoAudioEncoder."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import torch
from gguf import GGUFReader

from sanm_nano import FunASRNanoAudioEncoder


def _numpy(tensor) -> np.ndarray:
    data = np.array(tensor.data, copy=True)
    if data.dtype == np.float16:
        data = data.astype(np.float32)
    return np.ascontiguousarray(data)


def _linear_weight(arr: np.ndarray, expected: tuple[int, ...]) -> torch.Tensor:
    # GGUF readers may expose ggml [in, out] or already-reversed PyTorch [out, in].
    if arr.ndim != 2:
        raise ValueError(f"expected 2D linear weight, got {arr.shape}")
    if tuple(arr.shape) == expected:
        return torch.from_numpy(np.ascontiguousarray(arr))
    if tuple(arr.T.shape) == expected:
        return torch.from_numpy(np.ascontiguousarray(arr.T))
    raise ValueError(f"linear weight {arr.shape} does not match {expected}")


def load_encoder_from_gguf(path: Path) -> FunASRNanoAudioEncoder:
    reader = GGUFReader(str(path))
    fields = {name: field.contents() for name, field in reader.fields.items()}
    # GGUF metadata funasr.adp.ffn_dim is 2048, but adaptor block tensors are 1024→256.
    model = FunASRNanoAudioEncoder(
        input_size=int(fields.get("funasr.enc.input_size", 560)),
        d_model=int(fields.get("funasr.enc.output_size", 512)),
        n_head=int(fields.get("funasr.enc.attention_heads", 4)),
        num_blocks=int(fields.get("funasr.enc.num_blocks", 50)),
        tp_blocks=int(fields.get("funasr.enc.tp_blocks", 20)),
        ffn_dim=int(fields.get("funasr.enc.linear_units", 2048)),
        kernel=int(fields.get("funasr.enc.kernel_size", 11)),
        llm_dim=int(fields.get("funasr.adp.llm_dim", 1024)),
        adp_layers=int(fields.get("funasr.adp.n_layer", 2)),
        adp_head=int(fields.get("funasr.adp.attention_heads", 8)),
        adp_ffn=256,
    )
    tensors = {t.name: _numpy(t) for t in reader.tensors}
    missing: list[str] = []

    def assign(module_key: str, gguf_key: str, *, fsmn: bool = False, linear: bool = False) -> None:
        if gguf_key not in tensors:
            missing.append(gguf_key)
            return
        arr = tensors[gguf_key]
        param = model.get_parameter(module_key)
        if fsmn:
            expected = tuple(param.shape)
            if arr.ndim == 2 and arr.shape == (expected[0], expected[2]):
                value = torch.from_numpy(np.ascontiguousarray(arr)).view(expected)
            elif arr.ndim == 2 and arr.shape == (expected[2], expected[0]):
                value = torch.from_numpy(np.ascontiguousarray(arr.T)).view(expected)
            elif arr.ndim == 3 and tuple(arr.shape) == expected:
                value = torch.from_numpy(np.ascontiguousarray(arr))
            else:
                raise ValueError(f"{module_key}: fsmn {arr.shape} vs {expected} from {gguf_key}")
        elif linear:
            value = _linear_weight(arr, tuple(param.shape))
        else:
            value = torch.from_numpy(arr)
        if tuple(param.shape) != tuple(value.shape):
            raise ValueError(f"{module_key}: {tuple(param.shape)} != {tuple(value.shape)} from {gguf_key}")
        param.data.copy_(value)

    def load_sanm(prefix: str, gguf_prefix: str) -> None:
        assign(f"{prefix}.self_attn.linear_q_k_v.weight", f"{gguf_prefix}.self_attn.linear_q_k_v.weight", linear=True)
        assign(f"{prefix}.self_attn.linear_q_k_v.bias", f"{gguf_prefix}.self_attn.linear_q_k_v.bias")
        assign(f"{prefix}.self_attn.linear_out.weight", f"{gguf_prefix}.self_attn.linear_out.weight", linear=True)
        assign(f"{prefix}.self_attn.linear_out.bias", f"{gguf_prefix}.self_attn.linear_out.bias")
        assign(f"{prefix}.self_attn.fsmn_block.weight", f"{gguf_prefix}.self_attn.fsmn_block.weight", fsmn=True)
        assign(f"{prefix}.w_1.weight", f"{gguf_prefix}.feed_forward.w_1.weight", linear=True)
        assign(f"{prefix}.w_1.bias", f"{gguf_prefix}.feed_forward.w_1.bias")
        assign(f"{prefix}.w_2.weight", f"{gguf_prefix}.feed_forward.w_2.weight", linear=True)
        assign(f"{prefix}.w_2.bias", f"{gguf_prefix}.feed_forward.w_2.bias")
        assign(f"{prefix}.norm1.weight", f"{gguf_prefix}.norm1.weight")
        assign(f"{prefix}.norm1.bias", f"{gguf_prefix}.norm1.bias")
        assign(f"{prefix}.norm2.weight", f"{gguf_prefix}.norm2.weight")
        assign(f"{prefix}.norm2.bias", f"{gguf_prefix}.norm2.bias")

    load_sanm("encoders0", "audio_encoder.encoders0.0")
    for index in range(len(model.encoders)):
        load_sanm(f"encoders.{index}", f"audio_encoder.encoders.{index}")
    for index in range(len(model.tp_encoders)):
        load_sanm(f"tp_encoders.{index}", f"audio_encoder.tp_encoders.{index}")
    assign("after_norm.weight", "audio_encoder.after_norm.weight")
    assign("after_norm.bias", "audio_encoder.after_norm.bias")
    assign("tp_norm.weight", "audio_encoder.tp_norm.weight")
    assign("tp_norm.bias", "audio_encoder.tp_norm.bias")
    assign("linear1.weight", "audio_adaptor.linear1.weight", linear=True)
    assign("linear1.bias", "audio_adaptor.linear1.bias")
    assign("linear2.weight", "audio_adaptor.linear2.weight", linear=True)
    assign("linear2.bias", "audio_adaptor.linear2.bias")
    for index in range(len(model.blocks)):
        prefix = f"blocks.{index}"
        gguf_prefix = f"audio_adaptor.blocks.{index}"
        assign(f"{prefix}.self_attn.linear_q.weight", f"{gguf_prefix}.self_attn.linear_q.weight", linear=True)
        assign(f"{prefix}.self_attn.linear_q.bias", f"{gguf_prefix}.self_attn.linear_q.bias")
        assign(f"{prefix}.self_attn.linear_k.weight", f"{gguf_prefix}.self_attn.linear_k.weight", linear=True)
        assign(f"{prefix}.self_attn.linear_k.bias", f"{gguf_prefix}.self_attn.linear_k.bias")
        assign(f"{prefix}.self_attn.linear_v.weight", f"{gguf_prefix}.self_attn.linear_v.weight", linear=True)
        assign(f"{prefix}.self_attn.linear_v.bias", f"{gguf_prefix}.self_attn.linear_v.bias")
        assign(f"{prefix}.self_attn.linear_out.weight", f"{gguf_prefix}.self_attn.linear_out.weight", linear=True)
        assign(f"{prefix}.self_attn.linear_out.bias", f"{gguf_prefix}.self_attn.linear_out.bias")
        assign(f"{prefix}.w_1.weight", f"{gguf_prefix}.feed_forward.w_1.weight", linear=True)
        assign(f"{prefix}.w_1.bias", f"{gguf_prefix}.feed_forward.w_1.bias")
        assign(f"{prefix}.w_2.weight", f"{gguf_prefix}.feed_forward.w_2.weight", linear=True)
        assign(f"{prefix}.w_2.bias", f"{gguf_prefix}.feed_forward.w_2.bias")
        assign(f"{prefix}.norm1.weight", f"{gguf_prefix}.norm1.weight")
        assign(f"{prefix}.norm1.bias", f"{gguf_prefix}.norm1.bias")
        assign(f"{prefix}.norm2.weight", f"{gguf_prefix}.norm2.weight")
        assign(f"{prefix}.norm2.bias", f"{gguf_prefix}.norm2.bias")

    if missing:
        raise RuntimeError(f"missing GGUF tensors ({len(missing)}): {missing[:8]}")
    model.eval()
    return model
