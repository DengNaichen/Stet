"""Serial native CPU/ANE comparison; writes raw evidence and a JSON summary.

Run only after compilation and other inference work finishes. Sample WAVs must
be 16 kHz mono and shorter than 30 seconds for the direct-encoder comparison.
"""
import argparse
import json
import statistics
import subprocess
from pathlib import Path
import numpy as np


def run(command, log):
    with log.open('w') as stream:
        subprocess.run([str(x) for x in command],check=True,stdout=stream,stderr=subprocess.STDOUT)


def read_tsv(path):
    values={}
    for line in path.read_text().splitlines():
        key,value=line.split('\t',1)
        values.setdefault(key,[]).append(value)
    return values


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--build',type=Path,required=True)
    parser.add_argument('--models',type=Path,required=True)
    parser.add_argument('--coreml',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--repeats',type=int,default=10)
    parser.add_argument('audio',type=Path,nargs='+')
    args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=True)
    summaries=[]
    for audio in args.audio:
        entry={'sample':audio.name}
        outputs={}
        for backend in ['cpu','ane']:
            prefix=args.output/(audio.stem+'-'+backend)
            cmd=[args.build/'funasr-encoder-probe',args.models,audio,prefix,args.repeats]
            if backend=='ane': cmd.append(args.coreml)
            run(cmd,Path(str(prefix)+'.encoder.log'))
            data=json.loads(Path(str(prefix)+'.json').read_text())
            data['warm_median_seconds']=statistics.median(data['encoder_seconds'][1:])
            entry[backend]=data
            embeddings=Path(str(prefix)+'.embeds.f32')
            outputs[backend]=np.fromfile(embeddings,np.float32).reshape(data['frames'],1024)
            with Path(str(prefix)+'.direct.txt').open('w') as out, Path(str(prefix)+'.decode.log').open('w') as err:
                subprocess.run([str(args.build/'funasr-decode-probe'),str(args.models),str(embeddings)],
                    check=True,stdout=out,stderr=err)
            data['direct_transcript']=Path(str(prefix)+'.direct.txt').read_text().strip()
            encoder=args.coreml if backend=='ane' else args.models/'funasr-encoder-f16.gguf'
            report=Path(str(prefix)+'.pipeline.tsv')
            run([args.build/'funasr-transcribe-probe',encoder,args.models,audio,args.repeats,report],
                Path(str(prefix)+'.pipeline.log'))
            pipeline=read_tsv(report)
            pipeline['warm_median_seconds']=statistics.median(float(x) for x in pipeline['prediction_seconds'][1:])
            data['pipeline']=pipeline
        expected,actual=outputs['cpu'],outputs['ane']
        cosine=np.sum(expected*actual,axis=1)/(np.linalg.norm(expected,axis=1)*np.linalg.norm(actual,axis=1))
        entry['finite']=bool(np.isfinite(actual).all())
        entry['row_cosine_min']=float(cosine.min())
        entry['consumed_row_cosine_min']=float(cosine[:(len(cosine)+7)//8].min())
        entry['max_abs_diff']=float(np.abs(expected-actual).max())
        entry['direct_text_equal']=entry['cpu']['direct_transcript']==entry['ane']['direct_transcript']
        entry['pipeline_text_equal']=entry['cpu']['pipeline']['transcript']==entry['ane']['pipeline']['transcript']
        entry['encoder_speedup']=entry['cpu']['warm_median_seconds']/entry['ane']['warm_median_seconds']
        entry['pipeline_speedup']=entry['cpu']['pipeline']['warm_median_seconds']/entry['ane']['pipeline']['warm_median_seconds']
        summaries.append(entry)
        (args.output/'summary.json').write_text(json.dumps(summaries,ensure_ascii=False,indent=2)+'\n')
        print(audio.name,'encoder speedup',round(entry['encoder_speedup'],2),'direct text',entry['direct_text_equal'],
              'pipeline text',entry['pipeline_text_equal'],'cosine',entry['row_cosine_min'],flush=True)
    assert all(x['finite'] and x['row_cosine_min']>0.995 for x in summaries),'embedding parity failed'
    assert all(x['direct_text_equal'] and x['pipeline_text_equal'] for x in summaries),'transcription regression'
    assert all(x['ane']['pipeline']['backend']==['coreml-cpu-and-ne'] for x in summaries),'unexpected CPU fallback'

if __name__=='__main__': main()
