# Product Sense

本文件记录 README 与真实用户入口已建立的 Stet 产品判断，不吸收 roadmap、monetization plan 或 Draft specs 中尚未采用的提案。

## 产品身份

- Stet 是把 speech 变成 usable text 的 macOS menu bar dictation app；本仓库是其 macOS app repository。[PRODUCT-0001]

## 目标用户

`unknown`：当前权威产品说明没有单独定义用户画像。

## 产品原则

- 产品目标是 minimal rewriting，并让 transcript 尽量保持 speaker intent。Rewrite 当前默认开启但可关闭，是受该目标约束的增强手段，不是产品目的。[PRODUCT-0003]

## 核心体验路径

- 用户从 global hotkey 开始/停止 dictation；Stet 录音、转写，再把结果粘贴回当前 app 或替换 selected text，而不是把用户带入独立文档编辑器。[PRODUCT-0002]
- Menu bar 是常驻主入口，Dock 默认隐藏但可由 Settings 开启，Settings 打开时也会临时显示 Dock。首次流程覆盖语言/转写引擎、权限、快捷键、首次成功听写与外观；Settings 还承载 General、Hotkey、Refine/凭据、History、audio、appearance、updates 与 personal dictionary。[PRODUCT-0004]
