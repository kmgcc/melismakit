# 配置参考

`LyricsConfiguration` 是一个 `Equatable, Sendable` 值类型。每次把它赋给 `LyricsView.configuration`，视图会按需重新排版；改颜色、动画或混合参数时沿用现有文本布局。

本文列出配置项、默认值与语义；宿主的配置入口即这些字段，其余状态由视图内部维护。

## 1. 顶层配置

### 文本与字体

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `fontName` | `String` | `"Helvetica Neue"` | 拉丁主字体家族名 |
| `fontNameCJK` | `String?` | `nil` | 中日韩字体家族；为 `nil` 时回退到系统字体 |
| `fontSize` | `Double` | `38` | 主歌词字号，单位 point |
| `fontWeight` | `Double` | `0.4` | 主歌词字重，`0...1`，映射到 Core Text 权重 |
| `translationFontName` | `String` | `"Helvetica Neue"` | 翻译字体 |
| `translationFontWeight` | `Double` | `0` | 翻译字重 |
| `translationFontSize` | `Double?` | `nil` | 翻译字号；`nil` 由主字号推导 |

### 内容呈现

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `showTranslation` | `Bool` | `true` | 显示翻译图层 |
| `showRomanization` | `Bool` | `true` | 显示罗马音图层 |
| `showRuby` | `Bool` | `true` | 显示 Ruby 注音 |
| `translationLanguage` | `String` | `"zh-Hans"` | 优先选择的翻译语言 |
| `romanizationLanguage` | `String` | `""` | 优先选择的罗马音语言；空字符串表示保留全部语言 |
| `obscenity` | `ObscenityMode` | `.disabled` | 脏话过滤模式 |
| `maskCharacter` | `String` | `"*"` | 过滤时使用的遮蔽字符 |
| `lineTimingOnly` | `Bool` | `false` | 强制按行级计时呈现；高亮按行级粒度呈现 |
| `preserveCompletedHighlight` | `Bool` | `true` | 并行前景行结束后保留高亮，直到整组结束 |
| `alwaysPostpositionBackground` | `Bool` | `false` | 伴唱行始终排在主行之后 |
| `hoverBackground` | `Bool` | `false` | 悬停行显示背景高亮 |
| `bottomText` | `String` | `""` | 视图底部的单行文本；为空时隐藏 |

### 布局

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `alignPosition` | `Double` | `0.35` | 焦点行在视图高度中的相对位置 |
| `alignOffset` | `Double` | `0` | 在焦点几何之后追加的 point 偏移；弹簧作用于焦点，偏移直接叠加 |
| `alignAnchor` | `LyricAlignment` | `.center` | 焦点行的锚点 |
| `wordFadeWidth` | `Double` | `0.5` | 逐字遮罩的淡入宽度 |
| `overscan` | `Double` | `300` | 视口外保留的排版范围，单位 point |
| `hidePassedLines` | `Bool` | `false` | 播放时隐藏已经过去的行 |
| `interludeDotScale` | `Double` | `1.15` | 间奏点相对直径 |

### 外观

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `surface` | `LyricsSurfaceStyle` | `.window` | 表面合成模式 |
| `palette` | `LyricsPalette` | 见下文 | 语义色调色板 |
| `backdropColor` | `LyricsColor?` | `nil` | 宿主背景色，合成在歌词通道之后 |
| `blendOpacity` | `Double` | `1` | 歌词通道的整体 alpha 倍率；逐字遮罩的 alpha 保持原值 |
| `blendMode` | `LyricsBlendMode` | `.automatic` | 整体墨水混合模式 |
| `channelBlend` | `LyricsChannelBlendConfiguration` | 全 `nil` | 按 inactive/current/highlight 通道覆盖混合 |
| `highlightMode` | `HighlightMode` | `.smooth` | 平滑扫亮或离散逐字 |
| `emphasis` | `Bool` | `true` | 长音节重音缩放 |
| `glow` | `Bool` | `true` | 重音辉光 |
| `glowRadiusScale` | `Double` | `1` | 辉光半径倍率 |
| `blur` | `Bool` | `true` | 焦点之外的行模糊 |
| `bakeSettledBlur` | `Bool` | `true` | 把静止行的模糊烘焙进位图，把每帧高斯合成降为一次 |
| `scale` | `Bool` | `true` | 焦点行的缩放差异 |
| `spring` | `Bool` | `true` | 使用弹簧滚动；关闭时使用直接定位 |
| `positionSpring` | `SpringParameters?` | `nil` | 覆盖焦点滚动弹簧；`nil` 使用 profile 默认值 |

### 性能

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `cacheBudgetBytes` | `Int` | `6 * 1024 * 1024` | 字形缓存预算 |
| `renderScale` | `Double` | `1` | 相对 backing scale 的渲染比例，范围约 `0.35...1` |
| `fpsCap` | `Int` | `0` | DisplayLink 帧率上限；`0` 跟随显示器原生刷新率 |

### 封面模糊与全屏

这些字段服务于封面模糊或多层合成场景。普通窗口保持默认值即可。

| 属性 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `coverBlurProfile` | `LyricsCoverBlurProfile` | `.lighter` | 封面模糊的明暗通道 |
| `coverBlurRenderLayer` | `LyricsRenderLayer` | `.full` | 单 surface 或拆分为 base/highlight 两层 |
| `coverBlurHideActiveMainLine` | `Bool` | `false` | base 层隐藏当前主行，交由 highlight 层绘制 |
| `coverBlurSuppressEmphasisGlow` | `Bool` | `false` | 在封面模糊渲染中关闭重音辉光 |
| `coverBlurGenericMode` | `Bool` | `false` | 使用通用封面模糊合成路径 |
| `fullscreenLyricDodgeMode` | `Bool` | `false` | 全屏避让模式：歌词为实色合成让出空间 |
| `fullscreenAppleStyleMode` | `Bool` | `false` | 早期全屏集成的兼容字段；全屏行为当前由 `surface` 决定 |
| `coverBlurThemeColor` | `LyricsColor?` | `nil` | 早期封面模糊集成的兼容字段；封面模糊行为当前由 `surface` 与 `coverBlurProfile` 决定 |

## 2. 调色板

`LyricsPalette` 的默认值是一套中性深色主题。颜色分量范围是 `0...1`，`LyricsColor` 支持 Display P3：

```swift
LyricsColor(0.95, 0.98, 1.0, alpha: 1, displayP3: true)
```

| 属性 | 默认值 | 用途 |
|---|---|---|
| `mainActive` | 白色 | 当前行/已点亮文字 |
| `mainInactive` | `0.42, 0.44, 0.49` | 当前行以外的主歌词 |
| `lineTimingInactive` | 同 `mainInactive` | 行级计时文档中当前行以外的文字 |
| `translation` | `0.48, 0.50, 0.55` | 翻译 |
| `lineTimingSubInactive` | `0.48, 0.50, 0.55` | 行级计时的次级文字 |
| `backgroundActive` | `0.84, 0.84, 0.84` | 伴唱当前行 |
| `backgroundInactive` | `0.38, 0.40, 0.44` | 伴唱中当前行以外的行 |
| `backgroundKaraoke` | `0.90, 0.91, 0.93` | 伴唱逐字扫亮 |
| `emphasisGlow` | 白色 | 辉光颜色 |
| `backgroundBaseOpacity` | `0.38` | 伴唱基础 alpha |
| `backgroundKaraokeOpacity` | `0.84` | 伴唱扫亮 alpha |

## 3. 动画配置

`configuration.motion` 是 `LyricsMotionConfiguration`：

| 属性 | 默认值 | 说明 |
|---|---|---|
| `blurRadius` | `2.25` | 焦点之外的行的基础模糊半径 |
| `maximumBlurRadius` | `4.5` | 距离焦点最远处的模糊上限 |
| `blurTransition` | `0.45` | 模糊进入/退出时长，秒 |
| `pointerExitDelay` | `0` | 指针移出后延迟多久恢复模糊；`0` 表示立即 |
| `clickStagger` | `0.055` | 点击后逐行级联启动间隔，秒 |
| `backgroundTransition` | `0.35` | 伴唱展开时长，秒 |
| `resizeSpring` | `SpringParameters(mass: 1, damping: 22, stiffness: 120, soft: true)` | 窗口尺寸变化后的重排弹簧 |
| `exitFade` | `0.28` | 行退场淡出时长，秒 |
| `catchUpMinimum` | `0.12` | 行尾高亮补齐的最短时长，秒 |
| `catchUpMaximum` | `0.28` | 行尾高亮补齐的最长时长，秒 |
| `highlightAnticipation` | `0.12` | 标注间隙内的有界前向预测，秒 |

弹簧使用 `SpringParameters`：

```swift
SpringParameters(mass: 1, damping: 20, stiffness: 100, soft: false)
```

- `mass`、`damping`、`stiffness` 是标准弹簧参数。
- `soft: true` 会钳制参数以抑制过冲。
- 预置：`.position`、`.scale`、`.background`；`SpringParameters.nonBouncyPosition(from:)` 返回抑制回弹的版本。
- `SpringParameters.positionOverride(interval:slow:end:profile:)` 根据行间距离生成位置弹簧。

## 4. 计时配置

`configuration.timing` 是 `LyricsTimingConfiguration`：

| 属性 | 默认值 | 说明 |
|---|---|---|
| `enabled` | `true` | 是否执行计时预处理；关闭后按原始时间轴呈现 |
| `trackOffset` | `0` | 展示时间校正，秒；正值把歌词时间轴整体后移（歌词相对声音更晚出现），负值提前 |
| `seekOffset` | `0` | 仅应用于 `onSeek` 回传时间的校正，秒 |
| `globalAdvance` | `0` | 从 `trackOffset` 中减去的全局提前量；新接入建议只使用 `trackOffset` |
| `leadIn` | `0.6` | 相邻行切换的提前量，秒 |
| `nearSwitchGap` | `0.16` | 判定“近切换”的间隙阈值，秒 |

注意：

- `trackOffset` 只作用于展示时间；`onSeek` 回传值由源时间与 `seekOffset` 决定。
- `seekOffset` 只作用于 `onSeek` 回传值；展示时间保持 `trackOffset` 的结果。
- 如果宿主已经把所有偏移合并进 `trackOffset`，把 `globalAdvance` 保持为零，让扣减只发生一次。

## 5. 通道混合

`LyricsChannelBlendConfiguration` 允许分别控制三个墨水通道：

```swift
configuration.channelBlend = .init(
    inactive: .normal,
    current: .normal,
    highlight: .plusLighter
)
```

- 全部为 `nil` 时，使用 `surface` 预设。
- 只要设置了任意一个通道，其余 `nil` 通道使用 `.normal`。
- `highlight` 模式在单字形 alpha 遮罩之前合成，合成范围限于歌词通道。
- `inactive` / `current` 模式仍由宿主合成器绘制完整歌词表面。

`LyricsBlendMode`：`.automatic`、`.normal`、`.plusLighter`、`.plusDarker`。

## 6. 枚举

### `LyricsSurfaceStyle`

| 值 | 说明 |
|---|---|
| `.window` | 默认透明窗口表面，适合面板与普通窗口 |
| `.artisticFullscreen` | 实色全屏表面（alpha 为 1） |
| `.appleStyle` | Apple 风格全屏表面 |
| `.coverBlurLight` | 封面模糊亮色合成表面 |
| `.coverBlurDark` | 封面模糊暗色合成表面 |
| `.coreReference` | 与上游行为对照的参考表面；常规 UI 使用 `.window` 等预设 |

### `LyricsRenderLayer`

| 值 | 说明 |
|---|---|
| `.full` | 单个完整表面，默认 |
| `.base` | 双 surface 合成中的基础层 |
| `.highlight` | 双 surface 合成中的高亮层 |

宿主需要把歌词拆成两层、分别叠在封面模糊图上时使用 `.base` / `.highlight`；其他场景保持 `.full`。

### `LyricsProfile`

| 值 | 说明 |
|---|---|
| `.currentPlayer` | 默认播放器预设：保留并行前景高亮、间奏前后微调、5 秒浏览恢复 |
| `.upstream` | 更贴近上游 AMLL 可观察行为的时间线清理与间奏节奏 |

普通接入使用默认值即可。切换 profile 会改变间奏边界、高亮保留与部分弹簧参数，属于行为级选择。

### 其他枚举

| 枚举 | 值 | 说明 |
|---|---|---|
| `HighlightMode` | `.smooth` / `.discrete` | 平滑扫亮 / 离散逐字 |
| `LyricAlignment` | `.top` / `.center` / `.bottom` | 焦点行锚点 |
| `ObscenityMode` | `.disabled` / `.full` / `.partial` | 原样显示 / 全遮蔽 / 部分遮蔽 |
| `LyricsCoverBlurProfile` | `.lighter` / `.darker` | 封面模糊明暗通道 |
| `TTMLTimingProfile` | `.amllAbsolute` / `.w3cRelative` | 媒体绝对时间 / W3C 相对时间 |
| `LyricsSeekMotion` | `.immediate` / `.cascade` / `.preview` | 跳转后的图层运动 |

## 7. 常用组合

### 紧凑窗口面板

```swift
var configuration = LyricsConfiguration()
configuration.fontSize = 26
configuration.alignPosition = 0.30
configuration.showRuby = false
configuration.motion.blurRadius = 1.5
configuration.motion.maximumBlurRadius = 3
configuration.renderScale = 0.85
configuration.fpsCap = 60
```

### 全屏封面模糊

```swift
var configuration = LyricsConfiguration()
configuration.surface = .coverBlurDark
configuration.coverBlurProfile = .darker
configuration.coverBlurRenderLayer = .full
configuration.blendMode = .automatic
configuration.palette.mainActive = .white
configuration.palette.mainInactive = LyricsColor(1, 1, 1, alpha: 0.38)
configuration.fontSize = 54
configuration.alignPosition = 0.42
```

### 省电模式

```swift
var configuration = LyricsConfiguration()
configuration.blur = false
configuration.glow = false
configuration.emphasis = false
configuration.spring = false
configuration.bakeSettledBlur = true
configuration.renderScale = 0.7
configuration.fpsCap = 60
configuration.cacheBudgetBytes = 3 * 1024 * 1024
```

### 只显示行级计时

```swift
var configuration = LyricsConfiguration()
configuration.lineTimingOnly = true
configuration.highlightMode = .smooth
configuration.showRuby = false
configuration.showRomanization = false
```

### 自定义 P3 调色板

```swift
var configuration = LyricsConfiguration()
configuration.palette.mainActive = LyricsColor(0.96, 0.98, 1.0, displayP3: true)
configuration.palette.mainInactive = LyricsColor(0.46, 0.50, 0.58, displayP3: true)
configuration.palette.emphasisGlow = LyricsColor(0.72, 0.86, 1.0, displayP3: true)
configuration.palette.translation = LyricsColor(0.62, 0.66, 0.72, displayP3: true)
```

## 8. 配置与重排

- 修改字体、字号、字重、行内容显示开关、对齐或 `wordFadeWidth` 会触发文本重排。
- 修改颜色、透明度、混合模式、模糊、辉光或帧率时，通常沿用现有文本布局。
- 连续修改多个字段时，先构造好完整配置再一次赋值，让重排只发生一次。
- 配置是值类型；`configuration.motion.pointerExitDelay = 0` 这样的嵌套修改在 Swift 中会写回 `configuration`，再整体赋给视图。
