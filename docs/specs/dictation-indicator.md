# 功能规格：听写指示器与外观

**创建**：2026-09-11（2026-11-07 按模板扩展）
**状态**：Draft（其中“已批准外观”各节为 2026-09-11 用户已批准的设计事实，状态为 active）
**输入**：定义 macOS 听写面板与水彩圆球（Watercolor Blue 及其他主题）的视觉、动画、按钮布局、主题选择，以及各会话状态的呈现。在原 Watercolor Blue 规格的基础上扩展为完整模板，原有已批准参数全部保留。

**范围**：macOS。iOS 的指示器行为不受本 spec 影响，保持不变。
**边界**：本 spec 拥有面板的位置与窗口行为、圆球的视觉与动画、按钮的几何与可用性、主题列表与选择方式、各状态的视觉呈现。会话状态本身和取消 / 完成的效果见[macOS 听写会话](macos-dictation-session.md) spec；待复制面板和错误面板中的文字内容与按钮效果见[文本交付](text-delivery.md)和[听写结果与失败处理](dictation-outcomes.md) spec；音频电平的采集来源见[macOS 听写会话](macos-dictation-session.md) spec；引导中的外观步骤见[首次使用引导](onboarding.md) spec。
**替代**：无。

## 术语

- **圆球**：听写时显示的圆形水彩画面，由原生着色器绘制。
- **玻璃按钮**：圆球两侧的“取消”（×）和“完成”（✓）按钮。
- **Thinking**：会话处于“处理中”时圆球的收缩、缓慢运动状态。
- **安静波纹**：聆听中长时间安静时出现的缓慢波纹，不代表进入 Thinking。
- **主题**：圆球的配色方案，共 7 个：Watercolor Blue、Blossom、Egg、Harbor、Cat、Beacon、Autumn。

## 用户场景与测试 *(必填)*

### 用户故事 1 - 一眼看出 Stet 在听还是在想（优先级：P1）

作为用户，我希望不读文字就能分辨“正在听我说话”和“正在处理”，并看到声音被接收到。

**为什么是这个优先级**：指示器是听写过程中唯一的视觉反馈。

**独立测试**：开始听写，说话、停顿、结束，观察圆球在聆听、安静、Thinking 三种状态下的尺寸和运动。

**验收场景**：

1. **Given** 正在聆听，**When** 我说话，**Then** 圆球随音量放大并加快流动；停止说话后回落。
2. **Given** 正在聆听，**When** 我安静至少 650 毫秒，**Then** 仍保持聆听外观，并逐渐出现安静波纹。
3. **Given** 我结束录音，**When** 会话进入处理中，**Then** 圆球收缩到 44 pt 并以固定节奏缓慢运动，不受麦克风影响；“完成”按钮不可用，“取消”仍可用。
4. **Given** 处理完成，**When** 面板消失，**Then** 圆球停止渲染。

---

### 用户故事 2 - 选择自己喜欢的主题（优先级：P2）

作为用户，我希望在设置中浏览并选择圆球主题，选中后下一次听写就使用该主题。

**为什么是这个优先级**：个性化重要，但不影响听写功能。

**独立测试**：在外观设置中切换主题，确认预览立即变化；开始听写，确认面板使用所选主题；重启后选择保留。

**验收场景**：

1. **Given** 从未设置主题或保存的值无法识别，**When** 我开始听写，**Then** 使用 Watercolor Blue。
2. **Given** 我在设置中切换到某个主题，**When** 我开始听写，**Then** 圆球使用该主题，且动画、尺寸、按钮布局与其他主题完全相同。
3. **Given** 我已保存某个主题，**When** 应用更新或重启，**Then** 该选择保留。

---

### 用户故事 3 - 减少动态效果时仍可用（优先级：P2）

作为开启“减少动态效果”的用户，我希望指示器不再流动，但依然能看出状态并使用按钮。

**独立测试**：开启系统“减少动态效果”，开始听写并结束，确认圆球为静态，尺寸直接切换，按钮直接出现在最终位置。

**验收场景**：

1. **Given** 减少动态效果已开启，**When** 会话在聆听和处理中之间切换，**Then** 圆球立即变为对应尺寸，没有过渡动画。
2. **Given** 减少动态效果已开启，**When** 面板出现，**Then** 按钮直接位于最终位置并可点击，无障碍标签反映当前状态。

### 边界情况

- 面板出现在鼠标所在屏幕；鼠标不在任何屏幕内时用主屏幕；没有屏幕可用时居中显示。
- 设备不支持 Metal：用主题配色的纵向渐变圆代替水彩着色器，其余行为不变。
- 窗口被遮挡或挂起后恢复：单帧最多推进 0.05 秒，不会快进出大幅位移。
- Thinking 过渡中途又回到聆听，或反复进入 Thinking：保持当前画面相位，不跳变。
- 按钮展开动画未完成时：按钮不可点击，也不暴露给辅助功能。

## 需求 *(必填)*

### 功能需求

**面板**

- **FR-001**：听写面板固定为 370 × 106 pt 的无边框浮动面板，显示在鼠标所在屏幕可见区域的底部正中，距底边 12 pt；它浮在普通窗口之上，跟随当前桌面空间，可出现在全屏应用上方，且不抢占目标应用的焦点。
- **FR-002**：面板按会话状态显示三种内容之一：启动中 / 聆听 / 处理中显示圆球；待复制显示文本卡片（圆角 28 pt，含文字和“OK”按钮）；错误显示错误卡片（圆角 28 pt，含错误文字和“Dismiss”按钮）。卡片中的文字与按钮效果由[文本交付](text-delivery.md)和[听写结果与失败处理](dictation-outcomes.md) spec 定义，本 spec 只负责外观。
- **FR-003**：启动中时一旦收到大于 0 的音频电平，即按聆听呈现。

**已批准外观（2026-09-11 用户批准，保留原文含义）**

- **FR-004**：缺失或无法识别的主题偏好默认使用 Watercolor Blue。原有六个主题全部保留可选，已保存的选择保留。七个主题使用同一个原生圆形渲染器、同一套音频响应、Thinking 动画和玻璃按钮布局；每个主题保留自己的外观卡片。iOS 行为不变。
- **FR-005**：参数来源是用户 2026-09-11 在浏览器实时控件中截取的状态（`http://127.0.0.1:8765/?variant=detail&size=circle`），而不是该 HTML 文件的默认值：

  | 参数 | 批准值 |
  | --- | --- |
  | 圆球直径（Orb diameter） | 64 pt |
  | 流动速度（Flow speed） | 1.25× |
  | 颜料颗粒（Pigment granulation） | 0.14 |
  | 层间流动（Interlayer flow） | 0.77 |
  | 安静波纹（Silence waves） | 开启 |
  | 预览电平（Preview level） | 0.60；应用内由实时归一化人声电平代替 |
  | 模拟 / 麦克风 / 暂停控件 | 截取时浏览器中全部关闭 |

- **FR-006**：Watercolor Blue 在所有状态下都保持淡蓝、白、浅蓝和浓蓝四种颜色。颗粒感通过改变颜料浓度和湿边实现，而不是叠加噪点层。大范围反向旋转的色场和独立的白色水洗层让各颜色层彼此穿行。
- **FR-007**：其他六个主题复用各自现有的三个色样，按固定的 `idle` 顺序分别作为底色、层间色和颜料色；把它们向同一种纸白稀释得到更浅的水洗，把颜料与底色混合得到浓色区域。进入 Thinking 时颜色角色不变。Watercolor Blue 保留批准的浏览器精确颜色，不经过这套派生映射。
- **FR-008（启动中 / 聆听）**：64 pt。归一化音频电平驱动批准的响应：能量 attack 55 ms / release 320 ms；颜料色调 attack 120 ms / release 580 ms；流速在 240 ms 内跟随 `1.25 × (1 + 4 × energy)`。整个圆球（颜料及其玻璃底）按原胶囊曲线 `0.98 + 0.10 × level^0.4` 随麦克风音量缩放，约 62.72–69.12 pt；缩放以 55 ms attack / 320 ms release 跟随输入。聆听期间按钮及其点击区域保持不动。人声贡献随现有 Thinking 过渡淡出，Thinking 仍收缩到 44 pt。
- **FR-009（聆听中的停顿）**：保持聆听状态。输入安静且残余能量较低至少 650 ms 后，柔和波纹在 600 ms 内淡入；波纹振幅和速度每 2.8–4.6 秒变化一次，两道波同向移动；恢复说话时在 120 ms 内淡出。
- **FR-010（处理中 / Thinking）**：同一幅画面收缩到 44 pt。输入改为 `0.10 + 0.06 × sin(2πt / 2.6)`，形变幅度为说话时的 40%，过渡时间常数 115 ms。把当前画面相位记录为锚点，围绕它混合形变。不得加入新色相、旋转、假进度条或随机运动。麦克风不驱动此状态。“取消”保持可用；因为采集已结束，“完成”不可用。
- **FR-011（结果 / 隐藏）**：面板关闭后停止渲染。现有剪贴板和错误界面保持原行为。
- **FR-012（减少动态效果）**：显示静态画面样本，尺寸按状态立即切换，按钮直接位于最终位置。标签和控件仍反映会话状态。
- **FR-013（音频映射）**：音频分析器在原有电平之外提供未加窗的单声道 RMS。Watercolor 使用浏览器的麦克风映射 `sqrt(clamp((RMS - 0.004) / 0.12, 0, 1))`，使普通的低背景输入也能进入批准的安静波纹状态。显式传入的归一化预览输入保持不变。原有感知 dB 测量继续供其他使用方使用；七个原生主题都共用浏览器的响应。不引入新的 FFT 到视觉映射、采集增益或识别行为。
- **FR-014（原生按钮布局）**：每个玻璃按钮 28 pt，圆形点击区域 44 pt，图标 12 pt。主圆球从 64 收缩到 44 pt 时，整个布局以相同连续比例绕中心收缩：按钮到 19.25 pt，图标到 8.25 pt，水平和垂直偏移都缩到聆听姿态的 68.75%；玻璃融合间距按同一比例变化。周围留白随之增大，使整个过渡中点击区域始终保持 44 pt。macOS 26 使用共享的 Liquid Glass 容器；更早的受支持系统使用材质背景。批准的原生实验参数：

  | 参数 | 值 |
  | --- | --- |
  | 轨迹（Trajectory） | 向下的三次贝塞尔摆动 |
  | 水平伸展（Horizontal reach） | 60.15538985143712 pt |
  | 最终下落（Final drop） | 12.6339011004039 pt |
  | 弯曲（Bend） | 11.88852372917651 pt |
  | 时长（Duration） | 0.3 s，smoothstep 缓动 |
  | 玻璃融合间距（Glass fusion spacing） | 11.56007428520794 pt |
  | 选定的实验预览进度（Selected lab preview progress） | 0.8643167688116247 |

- **FR-015**：选定的实验姿态就是完全展开、可交互的产品终点。产品进度 0–1 采样原曲线从 0 到该保存姿态的一段；这样保留所选几何，又不会让控件停在不可交互的预览状态。按钮点击区域保持在现有 370 × 106 pt 窗口内。

**主题选择**

- **FR-016**：设置的外观页显示当前主题的实时预览和全部主题卡片；在卡片中聚焦某个主题即保存为当前主题，下一次听写生效。
- **FR-017**：设置与引导中的预览使用与听写面板相同的圆形材质和安静波纹行为，但不显示会话按钮，也不接收麦克风输入。
- **FR-018**：引导中的外观步骤只在“应用并完成”时保存主题（见[首次使用引导](onboarding.md) spec）。

**无障碍**

- **FR-019**：圆球的无障碍标签按状态为“Starting microphone”“Listening”“Thinking”；按钮标签为“Cancel dictation”“Finish dictation”。面板隐藏或按钮未完全展开时，对应元素不暴露给辅助功能。

### 主题配图

资源：`StetMac/Assets.xcassets/watercolorBlue.imageset/watercolorBlue.png`。用内置 imagegen 工具生成后复制进资源目录，没有替换任何已有配图。最终提示词：

> Use case: stylized-concept. Generate one finished portrait illustration for the Watercolor Blue appearance theme card in the Stet macOS app, aspect ratio 4:5. The card should express the same material as a fluid blue watercolor orb: a broad, elegant ocean swell, seen from overhead, formed by azure blue watercolor pigment on pale icy blue cotton paper. Deep blue pools merge into lighter cyan washes; a generous winding band of soft white separates the deep blue from the very pale blue ground. Visible fine pigment granulation belongs inside the paint, with soft wet-on-wet edges and restrained paper texture. Large connected shapes, calm open areas, one or two sweeping wave forms with a lively inward curl, rich but not dark. Beautiful, tactile, polished fine-art print with natural daylight, readable when cropped to a small portrait card. Fill the entire image, no frame. No text, no letters, no logos, no app UI, no orb sphere, no random speckles overlaid on top, no tiny fragmented swirls, no purple or green.

### 署名

基础流动效果改编自 Swami Malode 的 [Rare UI's Fluid Orb](https://www.rareui.com/components/fluidorb)。[上游 MIT 许可证](https://github.com/swamimalode07/rare-ui/blob/main/LICENSE) 以 [StetVisuals/RareUI-LICENSE.txt](../../StetVisuals/RareUI-LICENSE.txt) 的形式收录，并随框架一同打包。

### 关键实体

- **主题偏好**：持久保存的主题名；缺失或无法识别时视为 Watercolor Blue。
- **圆球帧状态**：画面相位、锚点、色调、Thinking 混合度、安静波纹、音量缩放；只在面板可见期间推进。
- **按钮展开进度**：0–1，按 0.3 s smoothstep 变化，决定按钮位置与可点击性。

## 成功标准 *(必填)*

### 可衡量结果

- **SC-001**：聆听时圆球直径始终在约 62.72–69.12 pt 之间，Thinking 时为 44 pt；按钮点击区域在任何时刻都是 44 pt。
- **SC-002**：七个主题在同一输入下的尺寸、运动和按钮位置完全一致，只有颜色不同。
- **SC-003**：处理中时麦克风输入的任何变化都不改变圆球运动。
- **SC-004**：开启减少动态效果时，圆球不出现逐帧动画，且所有控件仍可操作。
- **SC-005**：面板隐藏后不再产生渲染帧。

## 假设

- 最低支持 macOS 15.0；Liquid Glass 只在 macOS 26 及以上使用。
- 旧的胶囊视图和按状态变化的胶囊样式已移除，不再作为产品外观。
- 着色器调试窗口属于开发工具，不在本 spec 范围。

## 待产品确认

| 问题 | 当前行为 | 可选方向 |
| --- | --- | --- |
| 设置中“聚焦即保存”是否符合预期 | 在主题卡片中滑动经过某主题就会保存它 | A. 保持；B. 与引导一致，点击“应用”才保存 |
| 引导外观步骤的初始预览主题 | 左侧预览默认 Egg，右侧列表和最终应用的是已保存主题 | A. 预览与已保存主题一致；B. 保持 |

## 与当前实现的已知差异（非规范，供评审）

以下内容只记录核对基线 `b327f54` 时的代码状态，不代表产品决定。

- 已批准参数与代码一致：[MacWatercolorOrbMotion](../../StetVisuals/MacWatercolorOrbMotion.swift)（尺寸、速度、颗粒、层间流动、包络、安静波纹、Thinking 正弦）、[MacWatercolorOrbLayout](../../StetVisuals/MacWatercolorOrbLayout.swift)（按钮几何与贝塞尔参数）、[MacWatercolorOrbPalette](../../StetVisuals/MacWatercolorOrbPalette.swift)（批准颜色与派生映射）、[MacDictationPanelLayout](../../StetMac/Features/MacShell/DictationPanel/MacDictationPanelLayout.swift)（370 × 106 pt）；对应测试见 [MacWatercolorOrbMotionTests](../../StetMacTests/StetVisuals/MacWatercolorOrbMotionTests.swift)。
- 设置页聚焦主题即持久保存（[MacAppearanceSettingsView](../../StetMac/Features/MacShell/AppearanceSetting/MacAppearanceSettingsView.swift) 的 `onFocusedThemeChange` 以 `persist: true` 调用）。
- 引导外观步骤左侧预览默认 Egg（[OnboardingViewModel](../../StetMac/Features/Onboarding/OnboardingViewModel.swift) 的 `onboardingPreviewTheme`），与已保存主题可能不一致。
- 旧着色器路径仍保留在 StetVisuals 中，只用于着色器调试窗口和旧的 [DictationView](../../StetMac/Features/Dictation/DictationView.swift)；产品听写面板只使用圆球（[MacDictationCapsuleVisualView](../../StetVisuals/MacDictationCapsuleVisualView.swift)）。
- 处理中时面板把音频特征缩放为 0.35 后传入（[MacDictationPanelViewModel](../../StetMac/Features/MacShell/DictationPanel/MacDictationPanelViewModel.swift)），但圆球在 Thinking 中不读取麦克风，因此对外观没有影响。

## 历史验证记录（非规范，2026-09-11 初次实现）

| 命令 | 结果 |
| --- | --- |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make build` | 退出码 2（xcodebuild 65）：该主机没有 `NaichengDeng.Stet.Debug` 的开发描述文件。 |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make ci-build` | 退出码 0。Swift、Metal、主题资源和框架许可证资源均已编译并打包。 |
| `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer make test` | 退出码 0。82 个套件共 550 个测试通过，包括 RMS 校准、idle / Thinking 分离、过渡连续性、点击区域几何和全部七个主题偏好。 |
| `make lint` | 退出码 0。SwiftLint 和 swift-format 通过。 |

交互验证使用一个链接生产 StetVisuals 框架的临时原生宿主。检查了浅色 / 深色背景下 64 pt 聆听和 44 pt Thinking、完成 → Thinking 且“完成”不可用、Thinking 中取消 → 隐藏、旧 Egg 渲染及切回 Watercolor，以及配图在生产卡片竖版裁切下的效果。减少动态效果和被中断的过渡在状态 / 几何测试中验证。本次验证没有运行真实麦克风会话或签名发布版本；PCM 输入用合成音频测试。

随后的全主题更新移除了旧胶囊视图和状态样式。`make test` 再次通过全部 550 个测试，`make lint` 通过。一个原生总览渲染了全部七个主题预览，使用同一圆形材质，每个主题现有的三个色样仍可辨认。本地打包是另一个 Release 构建，使用现有 Developer ID 身份和描述文件签名，没有发布，也没有替换已安装的应用。
