# 语音交互增强方案：极简环绕版 (iOS 26)

本方案采用最基础的触感与一个极简的环绕动效来表示识别状态。

---

## 1. 触感反馈 (Haptic Feedback)
1.  **开始录音 (Mic Down)**: 
    *   触发 `UIImpactFeedbackGenerator(style: .medium)`。
2.  **停止录音 (Mic Up)**: 
    *   触发 `UISelectionFeedbackGenerator().selectionChanged()`。

---

## 2. 视觉组件

### 2.1 基础拾音波形 (Simple Waveform)
*   **组件**: `WaveformView`
*   **样式**: 4-5 根垂直灰白色线条，宽度 `2.5pt`。无多余修饰。
*   **位置**: 麦克风键左侧。

### 2.2 环绕识别点 (Rotating Orbit Dot)
*   **组件**: `ProcessingOrbitView`
*   **设计**: 一个直径 `4pt` 的纯色小圆点。
*   **动画**: 
    *   **轨道**: 圆点偏离麦克风按钮中心（例如 `x: 22`）。
    *   **旋转**: 应用 `.rotationEffect(.degrees(animate ? 360 : 0))`。
    *   **循环**: `.linear(duration: 1.5).repeatForever(autoreverses: false)`。
*   **效果**: 录音结束后，小圆点会沿着麦克风按键的边缘不停地画圆圈，直到文字上屏。

---

## 3. 技术实施步骤

1.  **状态控制**: 在 `KeyboardViewController` 中管理 `isRecording` 和 `isProcessing`。
2.  **布局封装**: 使用 `ZStack` 将 `ProcessingOrbitView` 覆盖在麦克风按钮之上。

---

**方案已更新为环绕圆点设计。**
