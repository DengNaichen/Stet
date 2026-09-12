"""Traceable Fun-ASR-Nano SAN-M encoder + Transformer adaptor.

Matches Packages/StetEngine/Vendor/FunASRPackage/RuntimeSource/stet_funasr.cpp
and FunASR SenseVoiceEncoderSmall + Transformer adaptor. Padding uses a
length mask with a finite fill (-1e4) so EnumeratedShapes stay fp16-safe.

Position encoding uses speech.size(1) so each enumerated bucket specializes.
A data-dependent pad mask is required for correctness; that mask currently
prevents ANE compilation, so the runtime pins CoreML to CPU.
"""

from __future__ import annotations

import math

import torch
import torch.nn as nn
import torch.nn.functional as F

MASK_FILL = -1.0e4


def _sinusoidal_pe(x: torch.Tensor) -> torch.Tensor:
    # FunASR SinusoidalPositionEncoder: positions 1..T, sin|cos split.
    # Use x.size(1) so EnumeratedShapes can specialize each bucket; avoid cumsum (ANE-hostile).
    half = x.shape[-1] // 2
    timesteps = x.size(1)
    positions = torch.arange(1, timesteps + 1, device=x.device, dtype=x.dtype)
    log_inc = torch.log(x.new_tensor(10000.0)) / (half - 1)
    inv = torch.exp(torch.arange(half, device=x.device, dtype=x.dtype) * (-log_inc))
    scaled = positions[:, None] * inv[None, :]
    return x + torch.cat([torch.sin(scaled), torch.cos(scaled)], dim=1).unsqueeze(0)


def _pad_mask(speech: torch.Tensor, lengths: torch.Tensor) -> torch.Tensor:
    timesteps = speech.size(1)
    positions = torch.arange(1, timesteps + 1, device=speech.device, dtype=speech.dtype)
    return (positions.unsqueeze(0) <= lengths.reshape(-1, 1).to(dtype=speech.dtype)).to(dtype=speech.dtype)


class SANMAttention(nn.Module):
    def __init__(self, in_dim: int, d_model: int, n_head: int, kernel: int) -> None:
        super().__init__()
        assert d_model % n_head == 0
        self.n_head = n_head
        self.d_k = d_model // n_head
        self.d_model = d_model
        self.linear_q_k_v = nn.Linear(in_dim, d_model * 3)
        self.linear_out = nn.Linear(d_model, d_model)
        self.fsmn_block = nn.Conv1d(
            d_model, d_model, kernel, stride=1, padding=0, groups=d_model, bias=False
        )
        pad = (kernel - 1) // 2
        self.pad_fn = nn.ConstantPad1d((pad, pad), 0.0)

    def forward(self, x: torch.Tensor, mask_bt: torch.Tensor) -> torch.Tensor:
        qkv = self.linear_q_k_v(x)
        q, k, v = torch.split(qkv, self.d_model, dim=-1)
        hidden_mask = mask_bt.unsqueeze(-1)
        v = v * hidden_mask
        fsmn = self.fsmn_block(self.pad_fn(v.transpose(1, 2))).transpose(1, 2) + v
        fsmn = fsmn * hidden_mask

        # -1 keeps T dynamic for EnumeratedShapes; do not capture Python T from x.shape.
        q = q.view(q.size(0), -1, self.n_head, self.d_k).transpose(1, 2)
        k = k.view(k.size(0), -1, self.n_head, self.d_k).transpose(1, 2)
        vh = v.view(v.size(0), -1, self.n_head, self.d_k).transpose(1, 2)
        scores = torch.matmul(q * (self.d_k ** -0.5), k.transpose(-2, -1))
        scores = scores + (1.0 - mask_bt)[:, None, None, :] * MASK_FILL
        attn = torch.softmax(scores, dim=-1) * mask_bt[:, None, None, :]
        out = torch.matmul(attn, vh).transpose(1, 2).contiguous().view(v.size(0), -1, self.d_model)
        return self.linear_out(out) + fsmn


class SANMLayer(nn.Module):
    def __init__(self, in_dim: int, d_model: int, n_head: int, ffn_dim: int, kernel: int) -> None:
        super().__init__()
        self.residual = in_dim == d_model
        self.norm1 = nn.LayerNorm(in_dim, eps=1e-5)
        self.self_attn = SANMAttention(in_dim, d_model, n_head, kernel)
        self.norm2 = nn.LayerNorm(d_model, eps=1e-5)
        self.w_1 = nn.Linear(d_model, ffn_dim)
        self.w_2 = nn.Linear(ffn_dim, d_model)

    def forward(self, x: torch.Tensor, mask_bt: torch.Tensor) -> torch.Tensor:
        attn = self.self_attn(self.norm1(x), mask_bt)
        x = x + attn if self.residual else attn
        h = self.w_2(F.relu(self.w_1(self.norm2(x))))
        return x + h


class AdaptorAttention(nn.Module):
    def __init__(self, dim: int, n_head: int) -> None:
        super().__init__()
        assert dim % n_head == 0
        self.n_head = n_head
        self.d_k = dim // n_head
        self.linear_q = nn.Linear(dim, dim)
        self.linear_k = nn.Linear(dim, dim)
        self.linear_v = nn.Linear(dim, dim)
        self.linear_out = nn.Linear(dim, dim)

    def forward(self, x: torch.Tensor, mask_bt: torch.Tensor) -> torch.Tensor:
        q = self.linear_q(x).view(x.size(0), -1, self.n_head, self.d_k).transpose(1, 2)
        k = self.linear_k(x).view(x.size(0), -1, self.n_head, self.d_k).transpose(1, 2)
        v = self.linear_v(x).view(x.size(0), -1, self.n_head, self.d_k).transpose(1, 2)
        scores = torch.matmul(q * (self.d_k ** -0.5), k.transpose(-2, -1))
        scores = scores + (1.0 - mask_bt)[:, None, None, :] * MASK_FILL
        attn = torch.softmax(scores, dim=-1) * mask_bt[:, None, None, :]
        out = torch.matmul(attn, v).transpose(1, 2).contiguous().view(x.size(0), -1, x.size(-1))
        return self.linear_out(out)


class AdaptorLayer(nn.Module):
    def __init__(self, dim: int, n_head: int, ffn_dim: int) -> None:
        super().__init__()
        self.norm1 = nn.LayerNorm(dim, eps=1e-5)
        self.self_attn = AdaptorAttention(dim, n_head)
        self.norm2 = nn.LayerNorm(dim, eps=1e-5)
        self.w_1 = nn.Linear(dim, ffn_dim)
        self.w_2 = nn.Linear(ffn_dim, dim)

    def forward(self, x: torch.Tensor, mask_bt: torch.Tensor) -> torch.Tensor:
        x = x + self.self_attn(self.norm1(x), mask_bt)
        return x + self.w_2(F.relu(self.w_1(self.norm2(x))))


class FunASRNanoAudioEncoder(nn.Module):
    def __init__(
        self,
        input_size: int = 560,
        d_model: int = 512,
        n_head: int = 4,
        num_blocks: int = 50,
        tp_blocks: int = 20,
        ffn_dim: int = 2048,
        kernel: int = 11,
        llm_dim: int = 1024,
        adp_layers: int = 2,
        adp_head: int = 8,
        adp_ffn: int = 256,
    ) -> None:
        super().__init__()
        self.d_model = d_model
        self.encoders0 = SANMLayer(input_size, d_model, n_head, ffn_dim, kernel)
        self.encoders = nn.ModuleList(
            [SANMLayer(d_model, d_model, n_head, ffn_dim, kernel) for _ in range(num_blocks - 1)]
        )
        self.after_norm = nn.LayerNorm(d_model, eps=1e-5)
        self.tp_encoders = nn.ModuleList(
            [SANMLayer(d_model, d_model, n_head, ffn_dim, kernel) for _ in range(tp_blocks)]
        )
        self.tp_norm = nn.LayerNorm(d_model, eps=1e-5)
        self.linear1 = nn.Linear(d_model, 2048)
        self.linear2 = nn.Linear(2048, llm_dim)
        self.blocks = nn.ModuleList(
            [AdaptorLayer(llm_dim, adp_head, adp_ffn) for _ in range(adp_layers)]
        )

    def forward(self, speech: torch.Tensor, speech_lengths: torch.Tensor) -> torch.Tensor:
        # speech: [B, T, 560], speech_lengths: [B] int32 valid frames
        mask = _pad_mask(speech, speech_lengths)
        x = _sinusoidal_pe(speech * math.sqrt(self.d_model))
        x = self.encoders0(x, mask)
        for layer in self.encoders:
            x = layer(x, mask)
        x = self.after_norm(x)
        for layer in self.tp_encoders:
            x = layer(x, mask)
        x = self.tp_norm(x)
        x = self.linear2(F.relu(self.linear1(x)))
        for layer in self.blocks:
            x = layer(x, mask)
        return x * mask.unsqueeze(-1)
