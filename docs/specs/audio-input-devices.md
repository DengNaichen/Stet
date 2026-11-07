# 功能规格：音频输入设备

**创建**：2026-11-07
**状态**：Draft
**输入**：定义 macOS 听写和会议录制共用的麦克风选择：设备列表、默认路线、外置设备偏好的保存、设备缺失时的回退且不覆盖偏好，以及设置中的麦克风测试。替代旧 spec「001 音频设备管理」。

**范围**：macOS。iOS 的输入路由（内置麦克风优先、路由恢复）见「iOS 常驻麦克风与 Live Activity」spec。
**边界**：本 spec 拥有“用哪个麦克风”的决定：列表内容、偏好的保存与清除、回退顺序、刷新时机和麦克风测试。听写会话的启动、重试与状态见「macOS 听写会话」spec；会议录制中设备中断后的处理见「会议录制与保存」spec；麦克风权限见 [权限与恢复](permissions-and-recovery.md)。
**替代**：旧 spec「001 音频设备管理」。

## 术语

- **默认路线**：用户没有指定外置麦克风时使用的输入，界面显示为“Default (Built-in Microphone)”。
- **外置偏好**：用户明确选择的非内置麦克风，按设备唯一标识（UID）保存，不按名称保存。
- **回退**：外置偏好对应的设备当前不可用时，本次改用默认路线；偏好本身保持不变。
- **当前设备**：按偏好和当前可用设备解析出、下一次录音将使用的麦克风。

## 用户场景与测试 *(必填)*

### 用户故事 1 - 选择录音用的麦克风（优先级：P1）

作为用户，我希望看到 Stet 可以使用的麦克风并选择其中一个，让听写和会议都从正确的设备录音。

**为什么是这个优先级**：设备可见和可选是本功能的核心价值。

**独立测试**：连接一个外置麦克风，在设置的麦克风页和菜单栏“选择麦克风”中分别切换，确认选中标记变化，下一次听写和会议使用该设备。

**验收场景**：

1. **Given** 有一个或多个外置麦克风，**When** 我打开设置的麦克风页或菜单栏“选择麦克风”，**Then** 看到“Default (Built-in Microphone)”和每个外置麦克风的名称。
2. **Given** 我选择某个外置麦克风，**When** 我开始下一次听写或会议录制，**Then** 使用该麦克风录音。
3. **Given** 我选择了外置麦克风，**When** 我改选“Default (Built-in Microphone)”，**Then** 外置偏好被清除，之后使用默认路线。
4. **Given** 某个选项是当前设备，**When** 我查看菜单栏列表，**Then** 该项带勾选标记。

---

### 用户故事 2 - 设备变化不阻止录音，也不丢失偏好（优先级：P1）

作为用户，我希望拔掉常用的外置麦克风时 Stet 仍能录音，再插回时自动用回它，不需要重新选择。

**为什么是这个优先级**：硬件经常插拔，回退保护主流程，保留偏好避免反复设置。

**独立测试**：选择外置麦克风后重启 Stet，确认仍选中；拔掉该设备后开始录音，确认使用默认路线；插回后再次录音，确认用回外置麦克风。

**验收场景**：

1. **Given** 我选择过外置麦克风且它仍连接，**When** 我重启 Stet，**Then** 它仍是当前设备。
2. **Given** 外置偏好对应的设备已断开，**When** 我开始录音，**Then** 自动使用默认路线，不需要确认。
3. **Given** 已发生回退，**When** 该设备重新连接，**Then** 当前设备自动恢复为它，偏好从未被改写。
4. **Given** 没有外置偏好，**When** Stet 自动选择，**Then** 优先使用内置麦克风。

---

### 用户故事 3 - 在设置中测试麦克风（优先级：P2）

作为用户，我希望在设置里录一小段并回放，确认当前麦克风工作正常。

**为什么是这个优先级**：降低设置成本，但依赖设备选择已经可用。

**独立测试**：打开设置的麦克风页，开始测试录音，说话时观察电平，停止后回放。

**验收场景**：

1. **Given** 我在麦克风页，**When** 我点击“开始录音”，**Then** 使用当前设备录音并显示实时电平。
2. **Given** 测试录音已结束，**When** 我点击“播放录音”，**Then** 听到刚才的录音；播放中可以停止。
3. **Given** 我切换到另一个麦克风，**When** 再次测试，**Then** 测试使用新的当前设备。

### 边界情况

- 没有任何外置麦克风：列表只有“Default (Built-in Microphone)”。
- 没有内置麦克风（例如外接显示器的台式 Mac）：默认路线依次改用系统默认输入；再不行则按设备类型优先级选一个（专业外置设备优先于虚拟设备和 AirPlay）。
- 两个设备名称相同：按 UID 区分，选择和保存都不会混淆；界面暂不区分显示（待产品确认）。
- 设置页或菜单打开期间插拔设备：列表随系统设备变化自动刷新。
- 回退期间界面显示：当前设备显示为“Default (Built-in Microphone)”被选中，不提示外置偏好仍被保留（待产品确认）。
- 录音进行中改选麦克风：当前录音不切换，下一次录音生效（待产品确认）。

## 需求 *(必填)*

### 功能需求

- **FR-001**：听写、会议录制的麦克风轨道和麦克风测试必须使用同一份设备选择，不存在各自独立的设备设置。
- **FR-002**：设备列表必须显示“Default (Built-in Microphone)”和当前可用的所有外置输入设备（按系统显示名称）；内置麦克风只通过“Default”一项表示。
- **FR-003**：选择外置设备时，必须按 UID 保存为外置偏好，并跨重启保留；选择“Default”或选择内置设备时，必须清除外置偏好。
- **FR-004**：解析当前设备的规则：有外置偏好且该设备可用时用它；否则使用默认路线。默认路线依次为：内置麦克风 → 系统默认输入 → 按设备类型优先级最高的可用设备。
- **FR-005**：因外置偏好不可用而回退时，不得改写或清除外置偏好；设备恢复可用后，下一次解析必须重新使用它。
- **FR-006**：设置的麦克风页和菜单栏“选择麦克风”显示期间，必须监听系统设备变化并立即刷新列表和当前设备；会议录制开始前也必须刷新一次。
- **FR-007**：设置页与菜单栏都必须标出当前设备；两处选择效果相同、立即保存。
- **FR-008**：选择变化只影响之后开始的录音；进行中的听写或会议录音不切换设备（待产品确认）。
- **FR-009**：听写开始时，使用当前设备启动采集；该设备无法打开时的重试与失败结果见「macOS 听写会话」spec。会议录制只使用解析出的设备，不在录制中途换设备；中途中断的处理见「会议录制与保存」spec。
- **FR-010**：麦克风测试位于设置的麦克风页，提供开始 / 停止录音、实时电平和回放 / 停止回放；录音中不能回放，回放中不能录音。
- **FR-011**：麦克风测试必须使用与听写相同的采集方式和当前设备，使测试结果能代表听写时的音质。
- **FR-012**：麦克风测试的录音只用于回放，不进入转写、历史或任何上传。

### 关键实体

- **音频输入设备**：系统中的一个输入设备，包含 UID、显示名称、是否内置、连接类型。
- **设备偏好**：“默认路线”或“外置设备（UID）”二者之一，持久保存。
- **当前设备**：由偏好和当前可用设备解析出的结果，供下一次录音使用。
- **麦克风测试录音**：一次测试产生的临时录音，只用于回放。

## 成功标准 *(必填)*

### 可衡量结果

- **SC-001**：不重启 Stet，即可在设置或菜单栏中看到并切换当前可用的麦克风。
- **SC-002**：选择的外置麦克风在重启后仍被选中的比例为 100%（设备仍连接时）。
- **SC-003**：外置偏好设备断开时，开始录音无需任何额外操作即可使用默认路线。
- **SC-004**：设备重新连接后，下一次录音自动使用外置偏好，无需重新选择。
- **SC-005**：用户可以在一个页面内完成“录音—看电平—回放”的麦克风测试。

## 假设

- 用户已允许麦克风权限；未允许时的行为见 [权限与恢复](permissions-and-recovery.md)。
- 设备排序和优先级的具体实现不作为产品规则，只要满足 FR-004 的顺序。
- 引导中不单独提供麦克风测试；首次听写步骤承担验证作用（见「首次使用引导」spec）。
- 被动监听已移除，不再存在需要长期占用麦克风的后台采集。

## 待产品确认

| 问题 | 当前行为 | 可选方向 |
| --- | --- | --- |
| 录音中途切换麦克风是否立即生效 | 不生效，下一次录音才使用新设备 | A. 保持；B. 听写中热切换；C. 会议中也热切换 |
| “Default” 是否应跟随系统默认输入 | 有内置麦克风时总是用内置，即使系统默认是耳机麦克风 | A. 保持“内置优先”并沿用当前文案；B. 改为跟随系统默认 |
| 回退时是否提示用户 | 不提示，界面显示 Default 被选中 | A. 保持；B. 显示“外置麦克风不可用，暂用内置” |
| 同名设备如何显示 | 只显示名称 | A. 保持；B. 追加连接类型或序号 |
| 麦克风测试失败时是否提示 | 启动或停止失败只写日志，界面回到就绪 | A. 显示失败原因；B. 保持 |

## 与当前实现的已知差异（非规范，供评审）

以下内容只记录核对基线 `b327f54` 时的代码状态，不代表产品决定。

- 偏好保存与回退规则见 [AudioDeviceSelectionResolver](../../StetMac/Core/Audio/Devices/AudioDeviceSelectionResolver.swift) 与 [AudioDeviceSelectionManager](../../StetMac/Core/Audio/Devices/AudioDeviceSelectionManager.swift)，与 FR-003 至 FR-005 一致；测试见 [AudioDeviceSelectionResolverTests](../../StetMacTests/Core/Audio/Devices/AudioDeviceSelectionResolverTests.swift)。
- 听写开始时不刷新设备，直接读取上次解析的缓存（`currentRecordingDevice`，[MacAudioCaptureService](../../StetMac/Core/Speech/MacAudioCaptureService.swift) 的 `startMacRecording`）。若外置偏好设备在设置页和菜单都未打开时断开，缓存仍指向它；此时采集候选只包含该设备（[MacCaptureAudioDevicePlanner](../../StetMac/Core/Audio/Capture/MacCaptureAudioDevicePlanner.swift) 的 `inputDeviceCandidates`），听写可能直接失败而不是回退，与 FR-005、SC-003 冲突（从代码推断，未真机核实）。会议录制在开始前调用 `refreshDevices`（[MacMeetingAudioRecorder](../../StetMac/Core/Audio/Capture/MacMeetingAudioRecorder.swift)），不受此影响。
- 设备变化监听只在设置麦克风页或菜单栏视图存在期间运行（[AudioInputDeviceListViewModel](../../StetMac/Features/MacShell/AudioDeviceManagement/AudioInputDeviceListViewModel.swift)），与 FR-006 一致，但不足以覆盖上一条。
- 回退状态 `isUsingFallbackBuiltIn` 已计算但没有界面使用方（[AudioDeviceSelectionManager](../../StetMac/Core/Audio/Devices/AudioDeviceSelectionManager.swift)）；回退时设置页和菜单显示 Default 被选中（[AudioInputDeviceSettingsSection](../../StetMac/Features/MacShell/AudioDeviceManagement/AudioInputDeviceSettingsSection.swift)、[AudioInputDeviceMenuSection](../../StetMac/Features/MacShell/AudioDeviceManagement/AudioInputDeviceMenuSection.swift)）。
- 麦克风测试的录音文件在下一次测试或离开页面时都不删除（[DefaultMicrophoneTestService](../../StetMac/Features/Dictation/MicrophoneTest/DefaultMicrophoneTestService.swift)、[MicrophoneTestViewModel](../../StetMac/Features/Dictation/MicrophoneTest/MicrophoneTestViewModel.swift)），会残留在系统临时目录。
- 麦克风测试使用独立的采集实例，未与正在进行的听写或会议互斥；离开麦克风页时也不停止进行中的测试录音（[MacAudioSettingsViewModel](../../StetMac/Features/MacShell/AudioSetting/MacAudioSettingsViewModel.swift) 的 `onDisappear`）。
- 麦克风测试录音不足 0.1 秒时，停止会按“无语音”抛错，界面只回到就绪且没有可回放的录音，也没有提示。
