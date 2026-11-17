# ANE 输入形状切换与编译缓存失效

## 运行证据

2026-11-17 22:57 的听写：4.032 秒音频，本地转写 42,309.7 ms；
开始时 `warmContextHit=true`，转写时 `reusedLoadedContext=true`。
Core ML 在 22:57:21 报告 E5 执行流创建失败，提示编译 bundle 可能被 APFS 清理，
随后重新编译；ANE compiler 调用从 22:57:27.711 到 22:58:03.556，约 35.8 秒。
紧接着同一音频的后台转写为 120.9 ms。

这次阻塞发生在已加载的上下文内，不能归因于语言模型的空闲超时回收。
Apple 也说明，系统可因存储压力清理 specialization 缓存，且首次预测可能需要按输入形状进行 specialization：
[Core ML 性能时序说明](https://developer.apple.com/documentation/coreml/analyzing-a-core-ml-model-s-performance-in-xcode)。
日志中的 APFS 提示并不能证明是哪一个系统行为删除了缓存。

## 修复与复现

旧编码器让四种帧长共用一个 `MLModel`；预热虽然遍历所有形状，切换形状时仍卸载当前 ANE specialization。
改为每个帧长桶独立持有模型及缓冲，在后台预热全部实例，再提供给前台复用。
语言模型保活另从 300 秒延长至 1800 秒，仅严重系统内存压力触发提前回收。

[真机复现脚本](../../scripts/funasr-nano-ane/verify_residency.py) 编译旧版与新版编码器，
使用唯一进程名隔离 Core ML 缓存，预热后只删除该测试进程自己的 E5 缓存，
再依次切换四种输入长度，共执行 24 次预测，并逐元素比较输出。
它不删除 Stet 的缓存，也不改动用户模型。

```sh
python3 scripts/funasr-nano-ane/verify_residency.py \
  --baseline-ref 9c9d047 \
  --model "$HOME/Library/Application Support/Stet/Models/Fun-ASR-Nano/FunASRNanoANE-v1.mlmodelc" \
  --output /tmp/stet-ane-residency-check \
  --purge-probe-cache
```

同一台 24 GB Apple Silicon Mac 的本次结果：

| 指标 | 原实现 | 每桶独立模型 |
| --- | ---: | ---: |
| 后台首次预热 | 41.75 秒 | 43.93 秒 |
| 删除测试缓存后的首次预测 | 53,310.575 ms | 5.194 ms |
| 24 次预测的中位数 | 35.137 ms | 9.919 ms |
| 24 次预测的最大值 | 53,310.575 ms | 37.363 ms |
| 新旧输出最大绝对差 | — | 0 |

本机临时原始结果为 `/tmp/stet-ane-residency-purge/summary.json`，不作为长期归档。
旧版阶段另有应用构建运行，因此这组结果用于验证是否出现重编译阻塞，不作为严格速度比。
这是编码器真机回归，不是端到端听写耗时；多个模型常驻会增加资源保留，
进程 RSS 也不能完整代表 ANE 的设备内存。这次实验不保证所有系统资源回收都不会引发重新编译。
