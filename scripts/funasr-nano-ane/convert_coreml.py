"""Export the production GGUF weights; preprocessing/masks stay on the host.

Outputs are encoder + adaptor embeddings, not SenseVoice CTC logits.
All artifacts must be written outside tracked source directories.
"""
import argparse
import json
import time
from pathlib import Path
import numpy as np
import torch
import coremltools as ct
from load_gguf import load_encoder_from_gguf

class EncoderWithHostMask(torch.nn.Module):
    def __init__(self, model):
        super().__init__()
        self.model = model

    def forward(self, positioned_features, valid_mask):
        m = self.model
        x = m.encoders0(positioned_features, valid_mask)
        for layer in m.encoders:
            x = layer(x, valid_mask)
        x = m.after_norm(x)
        for layer in m.tp_encoders:
            x = layer(x, valid_mask)
        x = m.tp_norm(x)
        x = m.linear2(torch.relu(m.linear1(x)))
        for layer in m.blocks:
            x = layer(x, valid_mask)
        return x

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--gguf', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--enumerated', action='store_true')
    p.add_argument('--ane-layout', action='store_true')
    p.add_argument('--frames', type=int, default=128)
    args = p.parse_args()
    if args.output.exists():
        raise FileExistsError(args.output)
    torch.set_num_threads(4)
    m = EncoderWithHostMask(load_encoder_from_gguf(args.gguf)).eval()
    inputs = (torch.zeros(1,args.frames,560),torch.ones(1,args.frames))
    names=['positioned_features','valid_mask']
    if args.ane_layout:
        from ane_model import ANEEncoder
        m=ANEEncoder(m.model).eval()
        inputs=(torch.zeros(1,560,1,args.frames),torch.ones(1,1,1,args.frames),torch.zeros(1,args.frames,1,1))
        names.append('attention_bias')
    with torch.inference_mode():
        traced = torch.jit.trace(m, inputs)
    start = time.perf_counter()
    shapes=[value.shape for value in inputs]
    if args.enumerated:
        if not args.ane_layout: raise ValueError('enumerated requires ANE layout')
        shapes=[ct.EnumeratedShapes(shapes=[[1,560,1,t] for t in [64,128,256,512]],default=[1,560,1,128]),
                ct.EnumeratedShapes(shapes=[[1,1,1,t] for t in [64,128,256,512]],default=[1,1,1,128]),
                ct.EnumeratedShapes(shapes=[[1,t,1,1] for t in [64,128,256,512]],default=[1,128,1,1])]
    model = ct.convert(traced, inputs=[
        ct.TensorType(name=name,shape=shape,dtype=np.float32) for name,shape in zip(names,shapes)
    ], outputs=[ct.TensorType(name='audio_embeds',dtype=np.float32)],
       minimum_deployment_target=ct.target.macOS15 if args.enumerated else ct.target.macOS14,
       compute_precision=ct.precision.FLOAT16,
       compute_units=ct.ComputeUnit.CPU_AND_NE, skip_model_load=True)
    if args.enumerated:
        model.user_defined_metadata['stet.encoder.contract']='nano-gguf-ane-v1-buckets'
    model.save(str(args.output))
    print(json.dumps({'package':str(args.output),'conversion_seconds':time.perf_counter()-start}),flush=True)

if __name__ == '__main__':
    main()
