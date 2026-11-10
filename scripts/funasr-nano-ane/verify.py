"""Real-feature parity, device placement and warm latency gate for an encoder."""
import argparse
import collections
import json
import resource
import time
from pathlib import Path
import numpy as np
import coremltools as ct

def positioned(features, frames):
    result = np.zeros((1, frames, 560), np.float32)
    t = features.shape[0]
    half = 280
    positions = np.arange(1,t+1,dtype=np.float64)[:,None]
    inv = np.exp(np.arange(half)*(-np.log(10000.0)/(half-1)))
    pe = np.concatenate([np.sin(positions*inv),np.cos(positions*inv)],axis=1)
    result[0,:t] = features*np.float32(np.sqrt(512)) + pe.astype(np.float32)
    mask = np.zeros((1,frames),np.float32)
    mask[0,:t] = 1
    return result,mask

def placement(path, units):
    plan = ct.models.compute_plan.MLComputePlan.load_from_path(str(path),compute_units=units)
    counts = collections.Counter()
    costs = collections.Counter()
    def visit(block):
        for op in block.operations:
            usage = plan.get_compute_device_usage_for_mlprogram_operation(op)
            device = type(usage.preferred_compute_device).__name__ if usage else 'unknown'
            counts[device] += 1
            cost = plan.get_estimated_cost_for_mlprogram_operation(op)
            if cost is not None:
                costs[device] += cost.weight
            for child in op.blocks:
                visit(child)
    for fn in plan.model_structure.program.functions.values():
        visit(fn.block)
    return dict(counts), dict(costs)

def main():
    p=argparse.ArgumentParser()
    p.add_argument('--model',type=Path,required=True)
    p.add_argument('--reference',type=Path,required=True)
    p.add_argument('--report',type=Path,required=True)
    p.add_argument('--frames',type=int,default=128)
    p.add_argument('--repeats',type=int,default=10)
    p.add_argument('--ane-layout',action='store_true')
    p.add_argument('--cpu',action='store_true')
    p.add_argument('--old',action='store_true')
    args=p.parse_args()
    prefix=str(args.reference)
    meta=json.loads(Path(prefix+'.json').read_text())
    t=meta['frames']
    features=np.fromfile(prefix+'.features.f32',np.float32).reshape(t,560)
    expected=np.fromfile(prefix+'.embeds.f32',np.float32).reshape(t,1024)
    if t>args.frames: raise ValueError('reference exceeds bucket')
    units=ct.ComputeUnit.CPU_ONLY if args.cpu else ct.ComputeUnit.CPU_AND_NE
    before=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    start=time.perf_counter()
    if args.model.suffix=='.mlmodelc':
        path=args.model
    else:
        path=Path(ct.models.utils.compile_model(str(args.model)))
    compile_s=time.perf_counter()-start
    start=time.perf_counter()
    model=ct.models.CompiledMLModel(str(path),compute_units=units)
    load_s=time.perf_counter()-start
    x,mask=positioned(features,args.frames)
    if args.old:
        x=np.zeros_like(x); x[0,:t]=features
        inputs={'speech':x,'speech_lengths':np.array([t],np.int32)}
    else:
        inputs={'positioned_features':x,'valid_mask':mask}
    if args.ane_layout:
        inputs={'positioned_features':x.transpose(0,2,1)[:,:,None,:].copy(),
                'valid_mask':mask[:,None,None,:],
                'attention_bias':((1-mask)*-1e4)[:,:,None,None]}
    timings=[]
    for _ in range(args.repeats):
        start=time.perf_counter()
        output=model.predict(inputs)['audio_embeds']
        if args.ane_layout: output=output[0,:,0,:].T[:t]
        else: output=output.reshape(args.frames,1024)[:t]
        timings.append(time.perf_counter()-start)
    output.astype(np.float32).tofile(str(args.report)+'.embeds.f32')
    finite=bool(np.isfinite(output).all())
    cosine=np.sum(expected*output,axis=1)/(np.linalg.norm(expected,axis=1)*np.linalg.norm(output,axis=1))
    peak=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    devices,costs=placement(path,units)
    report=dict(reference=meta,compute_units=units.name,compile_seconds=compile_s,load_seconds=load_s,
        prediction_seconds=timings,finite=finite,row_cosine_min=float(cosine.min()),
        max_abs_diff=float(np.abs(expected-output).max()),peak_rss_bytes=peak,
        baseline_peak_rss_bytes=before,devices=devices,estimated_costs=costs)
    args.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2),flush=True)
    assert finite and cosine.min()>0.995, 'embedding parity failed'
    if not args.cpu:
        assert devices.get('MLNeuralEngineComputeDevice',0)>0, 'no ANE operations in execution plan'

if __name__=='__main__': main()
