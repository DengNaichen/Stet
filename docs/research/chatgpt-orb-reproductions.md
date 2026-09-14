# ChatGPT 蓝白水彩 Orb 复刻调查

调查日期：2026-09-10。目标是蓝白色团在稳定圆形内部流动、交叠和翻涌的视觉，不是泛指发光球、Siri 彩色球或变形网格。下列实现都是第三方近似或独立产品；本次没有验证到 OpenAI 原版 shader 的公开源码。GitHub 链接指向调查时的 `main` 分支。

## 1. Rare UI：最直接相关的蓝白 WebGL 示例

- [在线效果与作者文档](https://www.rareui.com/components/fluidorb)；同页右上角 **Get code** 提供完整 `FluidOrb` TSX，安装项为 `swamimalode07/rare-ui/fluid-orb`。
- **已核验**：作者明确以 ChatGPT voice mode 为灵感；主任务在浏览器中检查了实时效果和完整源码。圆内有白、浅蓝、饱和蓝的层次，能作为继续比较的视觉基准；尚不足以证明与参考视频的横向卷动一致。
- **代码结构**：WebGL 全屏四边形、圆形遮罩；三层 fBm；不同频率的正弦/余弦组成二维漂移；两路 fBm 扭曲坐标后再采样一次。最后把一个标量场通过两段 `smoothstep` 映射成白、浅色、主色。因此蓝色层次来自色阶映射，而非多个独立小斑点，也不是真实流体模拟。[同页源码](https://www.rareui.com/components/fluidorb)
- **声音接口**：只有 `size`、`color`、`className`；shader 输入是时间、分辨率和颜色，未实现声音驱动。页面展示的是自动流动。[作者文档与源码](https://www.rareui.com/components/fluidorb)
- **许可**：页面允许个人和商业使用及修改，欣赏署名，要求不要把组件作为自己的套件转售；不应擅自称为 MIT。[License & Usage](https://www.rareui.com/components/fluidorb)

结论置信度：实现结构高；视觉接近方向中等；等同原版低。

## 2. LerSent001/orb：横向剪切可借鉴，默认效果偏液态玻璃

- [在线编辑器](https://lersent001.github.io/orb/)，选择 `blueDrop` 预设；[仓库](https://github.com/LerSent001/orb)。支持独立 HTML 和 SwiftUI/Metal 导出，但它是液态玻璃编辑器，不是已认证的 ChatGPT 复刻。
- **已核验的运动模型**：`effect.wgsl` 的 `glsBlueDropFluid` 使用两路方向不同的缓慢 fBm 漂移扭曲二维坐标，再依次对 x、y 加剪切波；因此不仅改变一条分界线高度，内部坐标本身也发生变形。`lqFbm` 对高频细节施加解析衰减；主体与 ridge 场混合后经过四色映射。[shader 源码](https://github.com/LerSent001/orb/blob/main/effect.wgsl#L746)
- **不匹配之处**：默认 `blueDrop` 启用玻璃，色板从近黑深蓝到青白，还施加球面明暗。它没有白色上半部这一明确构图约束，不能因名字含 blue 就视为忠实参考。[预设源码](https://github.com/LerSent001/orb/blob/main/src/presets.ts#L299)
- **声音接口**：已读的 uniform 类型与写入器没有音频输入。Siri 分支中的 `low/mid/high` 是时间的三角函数，不是真实频段分析。[uniform 写入器](https://github.com/LerSent001/orb/blob/main/src/orb-uniforms.ts)、[shader](https://github.com/LerSent001/orb/blob/main/effect.wgsl#L421)
- **许可**：MIT，复制实质代码需保留版权及许可声明。[LICENSE](https://github.com/LerSent001/orb/blob/main/LICENSE)

结论置信度：源码判断高；本次未独立观察其动态，不作相似度排名。

## 3. ElevenLabs 官方 Orb：声音与动画解耦的现成参考

- [组件源码](https://github.com/elevenlabs/ui/blob/main/apps/www/registry/elevenlabs-ui/ui/orb.tsx)；[官方组件文档源码](https://github.com/elevenlabs/ui/blob/main/apps/www/content/docs/components/orb.mdx)。它是 ElevenLabs 自己的组件，不是 OpenAI 官方代码。
- **渲染模型**：虽然文档称 3D orb，当前代码实际使用平面 `CircleGeometry`。fragment shader 在极坐标里混合七个柔边椭圆，借助 Perlin 纹理扭曲角度，再做四色映射；不是真实流体模拟。[orb.tsx](https://github.com/elevenlabs/ui/blob/main/apps/www/registry/elevenlabs-ui/ui/orb.tsx)
- **可借鉴的声音建模**：分别暴露输入、输出音量 0–1；音量与速度先平滑，再积分推进 `uAnimation`。输出控制流动速度及角度扰动，输入控制椭圆高度和边缘效果，使不同运动维度各有职责。[orb.tsx](https://github.com/elevenlabs/ui/blob/main/apps/www/registry/elevenlabs-ui/ui/orb.tsx)
- **接线细节**：当前代码仅在 `volumeMode="manual"` 时逐帧读取外部音量；默认 `auto` 根据 listening/talking/thinking 状态生成三角函数。传入回调而保持默认模式，不能据此声称接上真实声音。平滑系数按帧固定；我们移植时宜改成与 `deltaTime` 对应的时间常数。[orb.tsx](https://github.com/elevenlabs/ui/blob/main/apps/www/registry/elevenlabs-ui/ui/orb.tsx)
- **许可**：MIT。[LICENSE.md](https://github.com/elevenlabs/ui/blob/main/LICENSE.md)

结论置信度：源码和接口判断高；不是蓝白水彩外观的直接替代。

## 排除与保留意见

- [viewmodifier 的 SwiftUI/Metal WIP](https://www.reddit.com/r/generative/comments/1iz3omd/chatgpt_voice_mode_shader_swiftui_metal/)确实由作者声称复刻 ChatGPT voice mode，但本次所见正文没有源码链接，评论仍在索要代码。只算展示线索，不把算法猜测当成已公开实现。
- 没有查到可核验的 William Candillon 或 Reactiive 蓝白 Orb 复刻源码；二者的 Skia 教学不能自动成为这项效果的制作依据。
- [aguscruiz/voiceorb](https://github.com/aguscruiz/voiceorb)采用音量驱动网格位移和 Fresnel 发光；[OpenAI Realtime Blocks Orb](https://openai-realtime-blocks.vercel.app/components/3d-orb)同样侧重球面变形。它们解决了语音可视化，但不是本次要的内部水彩运动。

## 对下一版的具体启示（设计判断）

1. 先以 Rare UI 的**低频二维坐标扭曲 + 有间隔的色阶**建立形态基准。色团太碎时应减少空间频率和高频权重；不能靠增加噪声层数代替水彩层次。
2. 用户要的左右翻涌，需要内部坐标随位置发生不同程度的剪切、弯曲、回卷。只对边界高度或整张纹理做平移，即使音量映射更复杂，也仍然是原来的晃动。
3. 保留简单的 `orb.level` 兼容入口，同时让内部控制量拆成 `energy`、`attack`、`activity` 等。声音改变流速、剪切强度和已有色层的运动；连续的基础流动负责静音时的生命感。复杂音频特征是后续可选项，没有证据表明必须先上 Python 或真实流体求解器。
4. 下一步验收应把同一段音频同时送入比较版本，观看连续运动，而非仅比较几个静态截图。分别检查静音、大声、快速音节、拖长元音、停顿后的余势，避免把“音量有响应”误当成“运动像原版”。
