# Hot-word 排除学习

状态：active。平台：macOS 日常听写。跟踪 issue：[GitHub #73](https://github.com/DengNaichen/Stet/issues/73)。

## 目标

Fun-ASR Nano 的 hot-word prompt 最多注入约 50 个词。该功能通过同一段音频的两次转写，找出即使不注入也能稳定识别、因而不值得继续占用注入位置的词。

它只产生“建议从 Nano active hot words 中排除”的候选，不删除个人词典，不发现新词，不使用用户最后发送或编辑后的文本，也不参与会议或被动监听。

## 每条样本

每次 Nano 日常听写保存一次完整实验输入与输出：

- 当次真正传给 Nano 的有序 hot-word 列表，最多 50 个，并保留来源；
- 带 hot words 的原始转写；
- 同一音频、`hotwords: nil` 的后台转写。

hot-word 列表会随着用户编辑词典、自动学习和未来 ranking 改变。每条历史直接内联保存自己的真实列表。第一版不建立 set hash、共享 revision 或独立集合表，也不要求一个 batch 的 20 条拥有相同列表。保存快照是保证 A/B 数据正确所必需的事实记录，也是未来 ranking 和集合版本分析的基础。

## 批处理

- 一条样本在 hot-word 快照和两份转写齐备后进入 `pending`，不等待 `finalText`、粘贴、发送或 AX correction observation。
- 每累计 20 条 pending 历史，按 FIFO 发起一个后台请求；一次最多 20 条且只允许一个 batch in flight。
- App 启动时恢复中断的 in-flight 状态并处理积压。超过 20 条时连续按批 drain。
- 不设置固定每日时刻。少于 20 条时保留到以后继续积累，不因退出、关机、休眠或多日未启动而丢失。
- 网络、限流和服务端错误进入有限重试；缺少 provider 配置时保留 pending。请求可能因崩溃或超时重复发送，因此按 HistoryEntry UUID 幂等应用结果。
- 删除历史同时删除对应样本；关闭个人词典后不新增或发送，重新开启后恢复。

## 模型和请求

使用用户在 Refine 中已经选择的 provider、model 和凭据，不增加单独的学习模型设置。请求采用非思考模式和结构化 JSON；固定 system prompt 放在稳定前缀以利用 provider cache。音频永远不上传。

请求最多包含 20 条历史。因为每条的 hot words 可能不同，每条历史内联自己的 snapshot：

```json
{
  "version": 1,
  "histories": [
    {
      "id": "history-entry-uuid",
      "hotwords": ["Cursor", "Stet"],
      "withHotwords": "我用 Cursor 打开 Stet",
      "withoutHotwords": "我用 Cursor 打开 step"
    }
  ]
}
```

模型只从请求中实际出现的词里保守选择明显不需要注入的词；证据不足时跳过。某条历史只有在该词存在于其 snapshot 时才能作为该词证据。返回不要求自然语言原因，避免额外成本和不可验证解释：

```json
{
  "version": 1,
  "unnecessaryHotwords": ["Cursor"]
}
```

客户端拒绝未知词、重复词、错误版本、额外自由文本和 malformed payload。空数组是正常成功结果。

## 用户确认

模型结果不自动改变词典或 active injection set：

- 空结果静默完成，不通知；
- 非空结果合并为待 review 建议；只有出现尚未通知的新建议时发送一次系统通知；
- 用户在 Dictionary 设置页选择“从 Nano hot words 中排除”或“继续保留”；
- 排除只影响 Nano active injection，词仍保留在个人词典并继续供 rewrite 使用；
- 同一 pending 建议不重复通知，用户选择保留后也不应被下一批立即再次打扰。

第一版不要求模型给原因。需要向用户解释时，展示“无 hot words 也能识别”的产品说明；未来如需证据详情，应展示真实 A/B 历史，而不是模型生成的理由。

## 明确不做

- 不读取或比较 `finalText`；
- 不使用用户 AX 编辑作为 ground truth；
- 不新增 hot words（#75）；
- 不做整个大词典的 slot ranking（#74）；
- 不删除手动或自动词典项；
- 不冻结 hot-word 集合以等待 20 条相同 snapshot；
- 不为 snapshot 引入 hash/revision 数据模型，除非未来 ranking 确实需要。

## 验证重点

覆盖 19/20/21 条边界、多批积压、混合 snapshot、App 重启、stale in-flight 恢复、重复响应幂等、provider/model 变化、缺少凭据、malformed/未知词响应、空结果不通知、重复建议不通知，以及 History 删除联动。
