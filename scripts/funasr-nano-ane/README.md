# Fun-ASR-Nano encoder → CoreML

Converts the local `funasr-encoder-f16.gguf` SAN-M + adaptor graph into
`FunASRNanoEncoder.mlmodelc`. The compiled bundle is written next to the GGUF
files and is **not** committed. The macOS app prefers this encoder when
`model.mil` is present.

```
cd scripts/funasr-nano-ane
python3 -m venv /tmp/stet-nano-ane
/tmp/stet-nano-ane/bin/pip install -i https://pypi.tuna.tsinghua.edu.cn/simple -r requirements.txt
/tmp/stet-nano-ane/bin/python convert_coreml.py
```

Or from the repo root: `make funasr-nano-coreml`.

Sequence buckets are `[128, 256, 512, 1024, 1800]`. The runtime pads LFR
features to the smallest bucket. Dynamic attention masks currently fail
ANE compilation, so inference pins CoreML to CPU.
