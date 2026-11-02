# 源码溯源与原创性分析

本文档记录了 MelismaKit 中哪些部分属于原创实现，哪些部分派生自基于 `AGPL-3.0-only` 协议的开源项目 [AMLL (Apple Music-like Lyrics)](https://github.com/steve-xmh/applemusic-like-lyrics)。

编写本文档的原因在于：本软件包虽然在歌词*格式*上是对 AMLL 的独立原生实现，但在部分*算法*上并非完全独立的全新实现。部分行为是刻意对照 AMLL 的源代码而非其文档来编写的，这必须予以清晰声明，而非含糊暗示。

## 如何理解判定结果

| 判定 | 含义 |
|---|---|
| **派生** | 属于派生作品。存在确凿的结构性证据：保留了相同的数值常量、相同的变量命名、完全相同的分支阈值，或相同的计算公式结构。 |
| **独立** | 属于独立原创实现。未在上游找到该算法的对应实现；仅有高层概念或设计思路共通不计入派生。 |
| **无法确定** | 无法确切判定。存在对应关系的可能性，但未得到确证。在此如实记录，不主观臆测。 |

仅有共通的*设计思路*（例如两套实现都将活跃歌词行滚动至特定位置、都将 CJK 文本按字拆分）不足以判定为派生。判定为派生必须具备数值常量或算法结构上的高度匹配。

## 核对方法

本文档结合两种核对方式：

| 方式 | 覆盖范围 | 说明 |
|---|---|---|
| 维护者人工核对 | `Motion.swift` 中的 `interludeSample`、`SpringParameters`；`Document.swift` 中的布局常量（`alignPosition`、`overscan`、`wordFadeWidth`） | 已对照上游源码完成核对，文末附双边代码对照 |
| 机器辅助筛查 | 覆盖全部 8 个库源码文件，对照上游遗留 0.2.1 分支及当前 main 主分支 | 作为完整清单的基础参考；判定以表中的常量、结构与证据为准 |

“无法确定”条目保留在清单中，不用推测替代证据。新增派生代码时，必须同步更新本文档、`NOTICE` 与源文件头部声明。

## 派生与独立符号清单

覆盖全部 8 个库源码文件。

### `Motion.swift`

| 符号 | 判定 | 上游位置 | 说明 |
|---|---|---|---|
| `interludeSample(elapsed:duration:profile:)` | **派生** | `core/src/lyric-player/dom/interlude-dots.ts` | 经人工直接对比确认，文末附双边代码对照 |
| `EmphasisEnvelope.sample` | **派生** | `core/src/lyric-player/dom-slim/lyric-line.ts` `initEmphasizeAnimation` | 相同的公式结构：`shape(du/2)*0.6`、`shape(du/3)*0.5`、`*1.6`/`*1.5`/`*1.2`、`min(1.2)`/`min(0.8)`、`du/2.5/anchor*char` 延迟、`min(0.3, blur*0.3)` 发光、`sin(π)` 浮动 `*0.05` 伴随伴唱 `*2` 系数、`*1.4` 浮动持续时间 |
| `Curves`（`emphasisIn` / `emphasisOut` / 32采样点曲线） | **派生** | `dom-slim/lyric-line.ts` `makeEmpEasing` | 控制点 `(0.2, 0.4, 0.58, 1)` 与 `(0.3, 0, 0.58, 1)`；32 采样点与 `ANIMATION_FRAME_QUANTITY = 32` 完全对应 |
| `SpringParameters.position` / `.scale` / `.background` | **派生** | `core/src/lyric-player/base.ts` | 经人工直接对比确认，文末附双边代码对照 |
| `SpringParameters.position(interval:slow:end:profile:)` | **派生** | `core/src/lyric-player/base/layout.ts` `computeLinePosYSpringParams` | `clamp(interval, 100, 800)`、`ratio = (1-(x-100)/700)**0.2`、`k = 170 + ratio*50`、`damping = 2.2*sqrt(k)` |
| `SpringTrack` | **独立** | — | 延迟队列接口形式上类似于 AMLL 的 `Spring`，但底层求解器采用 Apple 原生 `SwiftUI.Spring`，而非上游求解器 |
| `lyricLineFall*`, `exitCatchUpTime`, `HighlightSmoother` | **独立** | — | 未在上游找到对应实现 |

### `TimingPolicy.swift`

| 符号 | 判定 | 上游位置 | 说明 |
|---|---|---|---|
| `advanceFirstWords` | **派生** | 播放器 fork 的 `core/src/lyric-player/base.ts` `applyEarlyWordLeadIn` | 相同的前置词选取逻辑（`.prefix(2)`），相同的分段锚点 1 毫秒下限，相同的 `start = max(line.start, word.start - lead*(1-a))` 结构，相同的近端/远端上限 `260` / `180` / `leadIn*0.6`（上游单位为毫秒，此处换算为秒） |
| `prepare`（提前/前奏扫掠 pass、末端截断、主歌词/伴唱同步） | **派生** | 播放器 fork 的 `base.ts`；上游 `base/layout.ts` | 相同的提前量模型（`amount` `0.4`/`0.6`，边界为 `prev.start + prev.duration*0.3`）以及相同的主歌词/伴唱共享时间范围 |
| `convertExcessiveBackgroundLines`、`cleanUnintentionalLineOverlaps`、`normalizeLineWordsAndBounds`、`restore` | **无法确定** | — | 未找到完全匹配的上游函数，包括 `overlap > 0.1 && overlap > nextDuration*0.1` 阈值。上游邻近的 `applyTrailingWordCatchUp` 末端截断 pass 可能是其潜在演进源头，但对应关系尚未得到确证 |

### `Timeline.swift`

| 符号 | 判定 | 上游位置 | 说明 |
|---|---|---|---|
| `LyricsTimeline.update` | **派生** | `base.ts` `setCurrentTime`；`base/timeline.ts` `commitPlayerTimeState` | 活跃热点端点间的缓冲前景跨度、Seek 焦点定位规则，以及歌曲结尾焦点判定 `hasBottom ? count : count-1` |
| 间奏检测（Interlude detection） | **派生** | `base.ts` `getCurrentInterlude`；`base/layout.ts` `computeCurrentInterlude` | `0.25` 秒间隙裁剪、`4` 秒最小间隙阈值、`+0.02` 秒前瞻时间 |
| `LyricsInteraction`、`LyricsClock` | **独立** | — | 原生指针与宿主媒体时钟状态机；`backwardsJitterTolerance` 在上游无对应物，因为上游基于帧时间差（delta-driven）驱动 |

### `TTMLDecoder.swift`

| 符号 | 判定 | 上游位置 | 说明 |
|---|---|---|---|
| `amll:empty-beat`、`x-bg` / `x-translation` / `x-roman` 角色定义、对唱默认 Agent `v1`、伴唱 `( )` 括号剥离 | **派生** | `packages/ttml/src/parser.ts` | 相同的属性名称、角色名称、默认 Agent 标识以及括号伴唱剥离规则 |
| XML 树解析、媒体绝对时钟与 W3C 相对时钟解析、Ruby 注音、元数据、附随文件（sidecars）、诊断信息 | **独立** | — | 与 `parser.ts` 处于相同的解析*业务领域*，但无结构或数值维度的直接代码复制 |

### `TextLayout.swift`

| 符号 | 判定 | 上游位置 | 说明 |
|---|---|---|---|
| `makeAtoms` | **派生** | `core/src/utils/lyric-split-words.ts` `chunkAndSplitLyricWords` | 插值单字符计时（`start + offset/total*(end-start)`）、`total = max(1, 非空格字符长度)`、CJK 字符拆分逻辑（除非该词带有罗马音标注） |
| `qualifies`（重音触发判定） | **派生** | `base.ts` `shouldEmphasize` | `duration >= 1s`、任意长度的 CJK 字符、非 CJK 字符长度 `> 1 && <= 7` |
| `MaskPath` 渐变常量 | **派生** | `dom-slim/lyric-line.ts` | 前导 `fadeWidth*1.5` 与后随 `fadeWidth*0.5` |
| `balancedBreaks` | **独立** | — | 上游核心代码中不存在任何平衡换行算法 |
| 字体解析、文字排版塑形（shaping）、宽度测量、CJK 检测、脏话过滤遮蔽 | **独立** | — | 原生 Core Text 实现；脏话过滤的设计想法共通，但实现完全独立 |

### `LayerRenderer.swift`

| 符号 | 判定 | 上游位置 | 说明 |
|---|---|---|---|
| 主歌词行缩放 `0.97` 与 `alphaTarget = (scale-0.97)/0.03` | **派生** | `base.ts` (`SCALE_ASPECT = 97`)、`dom-slim/lyric-line.ts` | 相同的数值常量与归一化计算窗口 |
| `GlyphCache`、字形/词/行/组图层栈、墨水通道合成、Core Image 滤镜、发光（glow）效果 | **独立** | — | 原生 CALayer 图层树；模糊半径使用了一个在上游无等价物的距离项（上游仅为一个整数 `blurLevel`） |

### `LyricsView.swift`

| 符号 | 判定 | 上游位置 | 说明 |
|---|---|---|---|
| 布局与图层栈参数 | **派生** | `base.ts` `calcLayout`；`base/layout.ts` `computeGroupPresentation` | `alignPosition 0.35`、缓冲不透明度 `0.85`、`hidePassedLines` 位于 `interlude.anchor + 1`、伴唱行优先放置、`baseDelay 0.05` 伴随 `/= 1.05` 交错延迟、间奏点外边距 `fontSize*0.4` |
| `install` / `load` / `clear` / `render` / DisplayLink / 尺寸重排版 / 增量布局、进场与唤醒动画、指针跟踪、`snapshotImage` | **独立** | — | 全程基于原生 `NSView` 生命周期；在上游无结构对应物 |
| 伴唱展开曲线、模糊半径公式 | **无法确定** | — | 上游使用不同参数（`bgScale`、整数 `blurLevel`）；设计思路共通已确证，但具体公式未确证 |

## 直接验证项目的双边代码对照证据

### `Motion.swift` `interludeSample`

上游 `packages/core/src/lyric-player/dom/interlude-dots.ts`：

```ts
const c1 = 1.70158;
const c2 = c1 * 1.525;
...
scale *= Math.sin(1.5 * Math.PI - (currentDuration / breatheDuration) * 2) / 20 + 1;
if (currentDuration < 2000) { scale *= easeOutExpo(currentDuration / 2000); }
...
if (interludeDuration - currentDuration < 750) {
    scale *= 1 - easeInOutBack((750 - (interludeDuration - currentDuration)) / 750 / 2);
}
if (interludeDuration - currentDuration < 375) { globalOpacity *= clamp(0, (...)/375, 1); }
const dotsDuration = Math.max(0, interludeDuration - 750);
scale = Math.max(0, scale) * 0.7;
const dot0Opacity = clamp(0.25, ((currentDuration * 3) / dotsDuration) * 0.75, 1);
```

本项目 `Sources/MelismaKit/Motion.swift`：

```swift
let breathe = duration/ceil(duration/(profile == .upstream ? 4.5 : 1.5))
var scale = sin(1.5 * .pi - elapsed/breathe*2*(profile == .upstream ? .pi : 1))/20 + 1
if elapsed < 2 { scale *= 1-pow(2,-10*elapsed/2) }
if remaining < 0.75 {
    let x = (0.75-remaining)/0.75/2, c2 = 1.70158*1.525
    let ease = pow(2*x,2)*((c2+1)*2*x-c2)/2
    scale *= 1-ease
}
if remaining < 0.375 { opacity *= Curves.clamp(remaining/0.375) }
let d = duration-0.75
... return max(0.25, min(1, candidate))
return .init(scale:max(0,scale)*0.7,opacity:opacity,walk:walk)
```

常量 `1.70158 * 1.525` 以及局部变量名 `c2` 均完全保留。

### `Motion.swift` `SpringParameters`

上游 `packages/core/src/lyric-player/base.ts`：

```ts
protected posYSpringParams: Partial<SpringParams> = { mass: 0.9, damping: 15, stiffness: 90 };
protected scaleSpringParams: Partial<SpringParams> = { mass: 2, damping: 25, stiffness: 100 };
protected scaleForBGSpringParams: Partial<SpringParams> = { mass: 1, damping: 20, stiffness: 50 };
```

本项目 `Sources/MelismaKit/Motion.swift`：

```swift
public static let position = SpringParameters(mass:0.9,damping:15,stiffness:90)
public static let scale = SpringParameters(mass:2,damping:25,stiffness:100)
public static let background = SpringParameters(mass:1,damping:20,stiffness:50)
```

### `Document.swift` 布局常量

上游 `packages/core/src/lyric-player/base.ts`：

```ts
protected alignPosition = 0.35;
protected overscanPx = 300;
protected wordFadeWidth = 0.5;
```

本项目 `Sources/MelismaKit/Document.swift`：

```swift
public var alignPosition: Double = 0.35
public var wordFadeWidth: Double = 0.5
public var overscan: Double = 300
```

## 对比的上游版本信息

| 代码树 | 版本 | 声明的许可证 |
|---|---|---|
| `applemusic-like-lyrics` 遗留分支 | 0.2.1 | `GPL-3.0` |
| `applemusic-like-lyrics` 当前 main 主分支 | 0.5.1 | `AGPL-3.0-only` |

本项目作为 `AGPL-3.0-only` 分发，与两者均完全兼容。`advanceFirstWords` 的关键对比源是一个面向播放器场景的 AMLL fork 分支；该分支未包含在上述两个上游代码树中，本身是针对上游 `base.ts` 的补丁修改。

## 维护此文件规范

凡是引入从上游代码转译的代码，必须在同一次提交中完成：在本文件表格中新增一行记录、在 [`NOTICE`](../NOTICE) 中添加致谢说明，并在相关源码文件头部添加派生声明注释。直接复制上游代码结构却未在此处记录的行为属于**许可证合规缺陷**，而非单纯的代码风格问题。
