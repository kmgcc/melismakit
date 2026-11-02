# 架构

MelismaKit 是一个 AppKit 组件。它把一份 TTML 歌词变成一组随时间变化的 Core Animation 图层，并把播放时钟的所有权留给宿主。本文说明数据如何流动、状态归谁所有，以及哪些设计是刻意保留的。

## 1. 模块

| Target / Product | 职责 |
|---|---|
| `MelismaKit` | 解码、值模型、计时、排版、图层、动效、交互、API |
| `MelismaKitSwiftUI` | `MelismaKitViewRepresentable`，负责挂载 |
| `MelismaKitDemo` | AppKit 示例应用，覆盖逐字、逐行、辉光、对唱/Ruby、伴唱 |
| `MelismaKitProbe` | 确定性渲染探针，输出帧耗时与缓存统计 |
| `MelismaKitBench` | 装载与稳态帧耗时基准，支持 JSON 与语料库校验 |
| `MelismaKitBenchCore` | Bench/Probe 共用的测量与合成 TTML 生成 |
| `MelismaKitParity` | 与上游渲染行为对照的诊断工具 |
| `MelismaKitTests` | XCTest 单元与回归测试 |

`MelismaKit` 的依赖限于系统框架；`MelismaKitSwiftUI` 依赖 `MelismaKit` 与系统 SwiftUI。

## 2. 数据流

```text
TTML Data
  │
  ├─ TTMLDecoder
  │    ├─ XML 树
  │    ├─ 时间解析（媒体绝对 / W3C 相对）
  │    ├─ 角色、Ruby、翻译、罗马音、元数据
  │    └─ LyricsDocument（纯值模型）
  │
  ├─ TimingPolicy
  │    └─ PreparedGroup / PreparedLine（预处理后的时间边界）
  │
  ├─ LyricsTimeline + LyricsClock
  │    └─ 当前播放集合、高亮集合、焦点、间奏
  │
  ├─ TextLayoutEngine（Core Text）
  │    └─ 行、词、字形、Ruby、翻译的几何
  │
  └─ LayerRenderer（Core Animation + Core Image）
       └─ Group → Line → Word → Glyph 图层树
            └─ CADisplayLink 驱动
```

### 解码

`TTMLDecoder` 是 `Sendable` 值类型。它先把 XML 解析成树，再构建 `LyricsDocument`。默认 profile 是 `.amllAbsolute`，即每个 `begin` / `end` 都按媒体绝对时间解释；`.w3cRelative` 用于显式的父子相对时间。

`LyricsDocument` 由 `LyricGroup`、`LyricLine`、`LyricWord`、`RubySyllable`、`LyricTextLayer` 组成，全部是 `Equatable, Codable, Sendable` 值类型。它可以跨线程传递、缓存和共享。

### 计时预处理

`TimingPolicy` 把原始文档转换成渲染用的 `PreparedGroup`。它处理：

- 行首/词首提前量；
- 相邻行切换；
- 并行前景与伴唱的时间范围；
- 异常重叠与倒流边界；
- 行尾高亮补齐所需的实际遮罩结束时间。

预处理改变的是渲染时间，源文档时间保持原值。`onSeek` 回传的是源时间加 `seekOffset`。

### 时间线

`LyricsTimeline` 根据当前媒体时间计算：

- `playing`：当前正在播放的行；
- `highlighted`：应保持高亮的行；
- `focus`：滚动焦点；
- `interlude`：间奏区间；
- `endOfSong`：是否到达结尾。

`LyricsClock` 负责在宿主采样之间做预测。DisplayLink 用帧间隔驱动刷新，媒体时间以宿主采样为准；暂停与 Seek 时同样如此。

### 排版

`TextLayoutEngine` 使用 Core Text：

- 字体解析与字体度量按 key 缓存；
- 行内按词/字拆分，CJK 与拉丁采用各自的分块策略；
- Ruby、翻译、罗马音各自参与行高与基线计算；
- 窗口尺寸变化时做增量重排，按帧预算分批提交；
- 长词与 RTL 文本走同一套 shaping 管线。

排版结果控制在视口与 `overscan` 范围内，图层也只在这个范围内物化。

### 图层

渲染器维护四层结构：

```text
GroupLayers
  ├─ main LineLayers
  │    └─ WordLayers
  │         └─ GlyphLayers
  └─ background LineLayers（可选）
```

- 每组对应一个主行，可能带一个伴唱行。
- 字形图层使用 mask 与预乘墨水渐变实现逐字扫亮。
- 静止行的模糊可以烘焙进位图，把每帧重复的高斯合成降为一次。
- 字形缓存按字节预算裁剪；视口外的行会在 `pruneTransientCaches()` 时释放内容。

### 动效

- 滚动与焦点移动使用弹簧轨道；默认由 `springDuration` 与 `springBounce` 解析，`positionSpring` 可覆盖。
- 长音节使用重音包络：缩放、位移、辉光。
- 间奏点使用独立的呼吸采样。
- 入场、退场、唤醒与点击级联各有独立状态机。
- 所有时间都来自媒体时间或宿主时间，计时由显式采样驱动。

## 3. 状态所有权

| 状态 | 所有者 |
|---|---|
| 文档、布局、图层、动画、交互 | `LyricsView` |
| 播放时间、播放/暂停、Seek | 宿主 |
| 配置 | 宿主构造，`LyricsView` 持有当前值 |
| 点击回传 | `LyricsView.onSeek` → 宿主 |
| 解码结果 | 宿主可缓存；`LyricsDocument` 为值类型 |
| SwiftUI 视图生命周期 | 宿主 |

`LyricsView` 是唯一有状态边界。`MelismaKitViewRepresentable` 直接引用宿主持有的 `LyricsView`，自身负责挂载。

## 4. 线程模型

- `LyricsView` 及其全部 UI 操作在 `@MainActor`。
- `TTMLDecoder.decode` 是同步纯函数；`decodeAsync` 在 detached task 中解析，返回 `Sendable` 文档。
- `install(document:)` 必须在主线程调用。
- 图层与 Core Text 操作只在主线程执行。
- 宿主可以从任意线程准备 `Data`；视图方法的调用统一在主线程。

## 5. 渲染契约

这些是当前实现承诺的可观察行为，修改渲染器时需要保持或显式更新测试。

- **并行前景**：同一组内并行演唱的前景行在整组结束前保持清晰与高亮；常规顺序行按焦点移动淡出。
- **模糊**：状态变化时发布独立的滤镜参数；半径在 `motion.blurTransition` 内过渡；指针进入与手动浏览清除模糊；移出后按 `pointerExitDelay` 恢复。
- **点击级联**：从首个可见行向下，以 `clickStagger` 逐行启动，包括点击行上方的行。
- **Seek**：`seek: true` 立刻定位整个图层栈并取消排队的弹簧；点击歌词使用 `.cascade`，进度条拖动使用 `.immediate`。
- **遮罩顺序**：空格归入相邻词的间隙；遮罩控制点严格保持文本空间顺序；时间倒流被钳制，文本顺序保持稳定。
- **预测**：每个媒体采样立即应用；只在标注间隙内做有界前向预测，暂停与 Seek 时绝对精准。
- **伴唱**：展开高度与缩放由一个抑制过冲的补间统一控制；伴唱边缘贴合主行变换后的边缘。
- **重音清理**：重音位移、缩放与辉光乘以有限的退场生命周期；归零时恢复恒等状态。
- **退场补齐**：使用实际单词遮罩结束时间（包括伴唱词），在 `catchUpMinimum...catchUpMaximum` 内完成。
- **离散模式**：跳过退场补齐；各词保留退场时刻的点亮量，再按常规退场淡出。

这些契约由 `BehaviorRegressionTests`、`TimelineTests`、`MotionTests`、`LayoutTests` 与 `IncrementalInstallationTests` 覆盖。

## 6. 性能设计

- **视口有界**：物化范围限于视口与 overscan 内的行。
- **缓存**：字体解析、文本度量与字形位图分级缓存。
- **模糊烘焙**：静止行的模糊写入位图，render server 每帧直接复用。
- **增量重排**：窗口尺寸变化按帧预算分批处理，把同步布局的主线程占用控制在单帧预算内。
- **按需刷新**：视图移出屏幕、最小化或隐藏时停止 DisplayLink；暂停且动画结束时同样收敛。
- **可调质量**：`renderScale` 控制 glyph mask 分辨率，`fpsCap` 控制刷新率，`cacheBudgetBytes` 控制缓存上限。

性能数字与测量方法见 [PERFORMANCE.md](PERFORMANCE.md)。

## 7. 扩展点

- **新歌词格式**：实现一个解码器，输出 `LyricsDocument`，再调用 `install(document:)`；`LyricsView` 的内部状态机保持原样。
- **新视觉参数**：优先扩展 `LyricsConfiguration` 的值类型字段，并在 `LayerRenderer` 中消费；宿主通过配置字段表达需求，图层由 `LayerRenderer` 维护。
- **新动效**：把时间采样写成纯函数，加入 `Motion.swift`，并用确定性测试覆盖。
- **新表面**：通过 `surface` 与合成配置表达，应用特定的窗口逻辑留在宿主。

## 8. 宿主职责

以下能力由宿主提供：

- 音频播放、解码、同步或设备管理；
- 曲库、文件扫描、歌词搜索与下载；
- 封面提取、主题存储、设置持久化；
- 应用窗口、全屏、菜单与快捷键；
- LRC / YRC / ASS 等格式的解析与转换：转为 TTML 后交给组件。

MelismaKit 负责歌词渲染，接收歌词数据、配置与媒体时间。
