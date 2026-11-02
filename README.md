# MelismaKit

> macOS 上的原生逐字歌词渲染组件。

![MelismaKit 渲染对唱歌词：注音、罗马音、翻译与逐字高亮](Documentation/images/hero.png)

MelismaKit 把 AMLL 兼容的 TTML 歌词渲染成与播放时间同步的原生图层。它负责解析、排版、动画、滚动、命中测试与歌词点击回调；宿主应用继续持有音频时钟、曲库、封面、主题与窗口生命周期。

它不依赖 WebView，也不依赖任何第三方 Swift Package。AppKit 与 SwiftUI 应用都可以接入。

## 特性

- **逐字与逐行**：支持逐字扫亮、逐行高亮、对唱（duet）与伴唱（background vocal）图层。
- **多语言排版**：Core Text 负责 CJK、拉丁、RTL、Emoji 与组合字符的排版；支持 Ruby 注音、翻译与罗马音。
- **原生动效**：弹簧滚动、模糊、重音缩放、辉光、卡拉 OK 遮罩、间奏呼吸点与入场/退场。
- **强类型配置**：字体、调色板、对齐、图层混合、渲染质量、帧率与动效参数都通过值类型配置。
- **两种挂载方式**：AppKit 直接使用 `LyricsView`；SwiftUI 使用轻量的 `MelismaKitViewRepresentable`。
- **可验证**：内置 Demo、确定性 Probe、性能基准与可复现的合成 TTML 语料库。

| | |
|---|---|
| ![逐字高亮](Documentation/images/word-highlight.png) | ![主文本上方的 Ruby 注音](Documentation/images/ruby.png) |
| 当前活跃行的逐字扫亮 | Ruby 注音、翻译与罗马音 |
| ![两行歌词之间的间奏点](Documentation/images/interlude-dots.png) | ![长音节处的重音发光](Documentation/images/glow.png) |
| 无演唱段落中的间奏点 | 由逐字时间驱动的重音与辉光 |

## 系统要求

- macOS 15 或更高版本
- Swift 6.1 或更高版本的兼容工具链（包使用 Swift 5 语言模式）
- 渲染核心依赖 AppKit；SwiftUI 支持是可选的 `MelismaKitSwiftUI` 产物

## 安装

在 `Package.swift` 中添加依赖：

```swift
dependencies: [
    .package(url: "https://github.com/kmgcc/melismakit.git", from: "0.3.0")
]
```

在目标中链接所需产物：

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "MelismaKit", package: "melismakit"),
        .product(name: "MelismaKitSwiftUI", package: "melismakit")
    ]
)
```

在 Xcode 中：**File → Add Package Dependencies…**，输入仓库地址，选择版本规则，然后勾选 `MelismaKit` 与 `MelismaKitSwiftUI`。只使用 AppKit 时可以不添加后者。

## 五分钟接入

### SwiftUI

`LyricsView` 是渲染与交互的唯一状态源。请在控制器或模型中持有它，不要在 SwiftUI 的 `body` 里重复创建。

```swift
import MelismaKit
import MelismaKitSwiftUI
import SwiftUI

@MainActor
final class LyricsController: ObservableObject {
    let view = LyricsView(frame: .zero)
    var onSeek: ((Double) -> Void)?

    init() {
        var configuration = LyricsConfiguration()
        configuration.fontSize = 32
        configuration.showTranslation = true
        view.configuration = configuration
        view.onSeek = { [weak self] mediaTime in
            self?.onSeek?(mediaTime)
        }
    }

    func load(_ ttml: Data, at mediaTime: Double, playing: Bool) throws {
        try view.load(ttml: ttml, time: mediaTime, playing: playing)
    }

    func update(mediaTime: Double, playing: Bool) {
        view.synchronize(time: mediaTime, playing: playing)
    }
}

struct LyricsPanel: View {
    @StateObject private var controller = LyricsController()
    let ttml: Data

    var body: some View {
        MelismaKitViewRepresentable(view: controller.view)
            .task { try? controller.load(ttml, at: 0, playing: false) }
    }
}
```

### AppKit

```swift
import AppKit
import MelismaKit

@MainActor
final class LyricsPanelController: NSViewController {
    let lyrics = LyricsView(frame: .zero)

    override func loadView() {
        view = lyrics
    }

    func load(_ ttml: Data, at mediaTime: Double, playing: Bool) throws {
        try lyrics.load(ttml: ttml, time: mediaTime, playing: playing)
    }

    func update(mediaTime: Double, playing: Bool) {
        lyrics.synchronize(time: mediaTime, playing: playing)
    }
}
```

### 时钟契约

`load`、`install` 与 `synchronize` 接收的都是**媒体时间**，单位为秒，不是播放器内部帧时间。宿主不需要自己累加帧间隔，也不需要为每次刷新计算插值：

- 在播放、暂停、Seek、切歌与恢复时调用 `synchronize(time:playing:)`。
- 周期性采样可以很稀疏；`LyricsView` 会依据 `hostTime` 在采样之间做有界预测。
- 用户拖动进度条时传入 `seek: true` 与 `motion: .immediate`，让图层栈直接定位。
- 点击歌词时，视图通过 `onSeek` 回传源媒体时间；宿主执行真正的播放器 Seek。若点击需要级联动画，传入 `motion: .cascade`。

```swift
func seek(to mediaTime: Double) {
    player.seek(to: mediaTime)
    lyrics.synchronize(
        time: mediaTime,
        playing: player.isPlaying,
        seek: true,
        motion: .immediate
    )
}
```

### 加载与异步解析

`load(ttml:)` 会同步解码并安装文档，适合已经拿到数据的普通场景。较大的歌词或导入流程可以在主线程之外解析：

```swift
@MainActor
func loadInBackground(_ data: Data, into view: LyricsView) async throws {
    let document = try await TTMLDecoder().decodeAsync(data)
    view.install(document: document, time: 0, playing: false)
}
```

解码失败时，`TTMLDecoder` 抛出 `LyricsError.invalidTTML`。`load` 会先把文档解析完，再替换当前画面，因此失败不会清空上一份有效歌词。

## 配置

`LyricsConfiguration` 是完整的值类型配置。修改后赋给 `view.configuration` 即可，无需操作内部图层。

```swift
var configuration = LyricsConfiguration()
configuration.fontName = "Helvetica Neue"
configuration.fontNameCJK = "PingFang SC"
configuration.fontSize = 34
configuration.alignPosition = 0.32
configuration.showTranslation = true
configuration.showRuby = true
configuration.palette.mainActive = .white
configuration.palette.mainInactive = LyricsColor(0.52, 0.55, 0.60)
configuration.motion.pointerExitDelay = 0
configuration.fpsCap = 60
configuration.renderScale = 0.75
view.configuration = configuration
```

可用选项、默认值与常用组合见 [配置参考](Documentation/CONFIGURATION.md)。

## 生命周期与性能

- 每个可见歌词区域持有一个 `LyricsView`。不要在一棵视图树里复用同一个实例，也不要为同一区域创建第二套渲染状态。
- 视图移出屏幕或窗口被遮挡时，把 `automaticDisplayUpdates` 设为 `false`；重新出现时设为 `true`，必要时调用 `prepareWakeEntryAnimation()`。
- 彻底移除视图前调用 `releaseRenderingResources()`。
- 长时间运行或进入后台时，可调用 `pruneTransientCaches()` 释放不可见的字形缓存。
- 全屏封面模糊、多层合成场景可以用 `setPointerInteractionSuppressed(_:)` 避免浮层拦截指针。
- 高分辨率屏幕可以降低 `renderScale`，或用 `fpsCap` 限制刷新率；先用 Probe/Bench 测量，再决定取舍。

更完整的生命周期说明见 [接入指南](Documentation/INTEGRATION.md)，性能数据与测量方法见 [性能](Documentation/PERFORMANCE.md)。

## TTML 支持范围

内置解码器面向 AMLL 歌词 TTML：

- 默认按媒体绝对时间解释 `begin` / `end`；需要通用 W3C 父子相对时间时，显式使用 `TTMLDecoder(profile: .w3cRelative)`。
- 支持逐字 `span`、行级计时、对唱、伴唱、Ruby、翻译、罗马音、间奏标记与 `amll:meta` 元数据。
- 支持 iTunes / AMLL 扩展命名空间中的常用元数据字段。
- 不内置 LRC、YRC、ASS 等格式的解析器。宿主可以转换为 TTML，或自行构造 `LyricsDocument` 后调用 `install(document:)`。

## Demo、探针与基准

```sh
# AppKit Demo（内置逐字、逐行、辉光、对唱/Ruby、伴唱样本）
swift run MelismaKitDemo

# 打开外部 TTML
swift run MelismaKitDemo --ttml /path/to/lyrics.ttml

# 确定性渲染，输出帧耗时与缓存统计
swift run MelismaKitProbe Sources/MelismaKitDemo/Resources/complex.ttml /tmp/probe 10 760 720 --paused

# 装载与帧耗时基准
swift run -c release MelismaKitBench --scale 120
```

Demo 也支持用 `--library-root` 显式扫描包含 `Tracks/<track>/lyrics.ttml` 的目录；它不会读取任何特定应用的曲库。

## 更新

Swift Package Manager：

```sh
swift package update MelismaKit
```

Xcode：**File → Packages → Update to Latest Package Versions**。

版本规则：

- 标签使用 `vX.Y.Z`，从 `v0.2.0` 起为 annotated tag。
- `0.x` 阶段，破坏性 API 变更提升次版本号；补丁版本保持源代码兼容。
- 需要完全可复现的构建时，用 `.exact("0.3.0")` 或在 `Package.resolved` 中固定 revision。
- 每个版本的变更记录见 [CHANGELOG.md](CHANGELOG.md) 与 [GitHub Releases](https://github.com/kmgcc/melismakit/releases)。

## 架构与贡献

MelismaKit 的边界是“歌词渲染”，不是播放器框架。它不包含曲库、音频播放、歌词抓取、封面提取、主题持久化或应用设置。这个边界是刻意保留的：任何应用都应该能以同样的方式接入它。

- 渲染管线与模块划分：[架构](Documentation/ARCHITECTURE.md)
- 构建、测试与基准：[测试指南](Documentation/TESTING.md)
- 参与开发：[CONTRIBUTING.md](CONTRIBUTING.md)

## 文档索引

| 文档 | 内容 |
|---|---|
| [接入指南](Documentation/INTEGRATION.md) | 生命周期、时钟、Seek、SwiftUI 边界与多 surface |
| [配置参考](Documentation/CONFIGURATION.md) | 全部配置项、默认值、枚举与常用组合 |
| [架构](Documentation/ARCHITECTURE.md) | 解码、计时、排版、图层与性能设计 |
| [性能](Documentation/PERFORMANCE.md) | 参考测量、复现命令与 CI 阈值 |
| [测试指南](Documentation/TESTING.md) | 单元测试、Demo、Probe、Bench 与视觉检查 |
| [贡献指南](CONTRIBUTING.md) | 开发环境、提交规范、PR 与发布流程 |
| [变更记录](CHANGELOG.md) | 版本历史 |
| [许可证](Documentation/LICENSING.md) | AGPL-3.0-only 与第三方归属 |
| [源码溯源](Documentation/PROVENANCE.md) | 派生与原创符号清单 |

## 与 AMLL 的关系

[AMLL (Apple Music-like Lyrics)](https://github.com/steve-xmh/applemusic-like-lyrics) 是 Web 端实现，基于 TypeScript、DOM 与浏览器渲染管线。MelismaKit 是面向 macOS 的原生实现，基于 AppKit、Core Text 与 Core Animation。

两者共享歌词格式规范，不共享代码库。MelismaKit 解析 AMLL 兼容的 TTML 子集；部分计时、布局与动效函数是阅读 AMLL 源码后转译为 Swift 的派生作品。**MelismaKit 不是 AMLL 的官方移植版本，也不隶属于 AMLL 项目或获得其背书。**

- [NOTICE](NOTICE) 记录第三方归属与派生范围。
- [源码溯源](Documentation/PROVENANCE.md) 逐个符号列出派生、原创与无法确定的条目。

## 许可证

本项目以 GNU Affero 通用公共许可证第 3 版（`AGPL-3.0-only`）分发。详见 [LICENSE](LICENSE)、[NOTICE](NOTICE) 与 [许可证说明](Documentation/LICENSING.md)。

AGPL 对通过网络提供修改版服务、以及分发修改版有源代码提供要求。将本项目用于闭源商业应用前，请先确认你的分发方式符合许可证。
