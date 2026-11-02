# MelismaKit

> macOS 上的原生逐字歌词渲染组件。

MelismaKit 最初是我们为 macOS 播放器写的歌词界面，后来从我们的应用中剥离，成为独立的歌词项目。它把 AMLL 兼容的 TTML 渲染成随播放时间推进的原生图层，负责解析、排版、动画、滚动、命中测试与歌词点击回调。音频时钟、曲库、封面、主题与窗口生命周期由接入方负责。

歌词的计时、布局、动效与交互基于 AMLL（Apple Music-like Lyrics）的源码开发。AMLL 是 Web 端实现，使用 TypeScript、DOM 与浏览器渲染；MelismaKit 把相关行为转写为 Swift，运行在 AppKit、Core Text 与 Core Animation 上。

![MelismaKit 渲染对唱歌词：注音、罗马音、翻译与逐字高亮](Documentation/images/hero.png)

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
| 演唱间隙中的间奏点 | 由逐字时间驱动的重音与辉光 |

## 系统要求

- macOS 15 或更高版本
- Swift 6.1 或更高版本的兼容工具链（包使用 Swift 5 语言模式）
- 渲染核心使用 AppKit；SwiftUI 支持由 `MelismaKitSwiftUI` 产物提供

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

在 Xcode 中：**File → Add Package Dependencies…**，输入仓库地址，选择版本规则，然后勾选 `MelismaKit` 与 `MelismaKitSwiftUI`。只使用 AppKit 时，链接 `MelismaKit` 即可。

## 快速接入

### SwiftUI

`LyricsView` 是渲染与交互的唯一状态源。控制器或模型持有它，SwiftUI 的 `body` 只负责挂载。

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

`load`、`install` 与 `synchronize` 接收的都是**媒体时间**，单位为秒。宿主直接传入当前播放位置；两次采样之间的插值由 `LyricsView` 完成：

- 在播放、暂停、Seek、切歌与恢复时调用 `synchronize(time:playing:)`。
- 周期性采样可以很稀疏；`LyricsView` 会依据 `hostTime` 在采样之间做有界预测。
- 用户拖动进度条时传入 `seek: true` 与 `motion: .immediate`，让图层栈直接定位。
- 点击歌词时，视图通过 `onSeek` 回传源媒体时间；宿主执行播放器 Seek。若点击需要级联动画，传入 `motion: .cascade`。

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

解码失败时，`TTMLDecoder` 抛出 `LyricsError.invalidTTML`。`load` 解析成功后才替换当前画面；解析失败时，上一份歌词继续显示。

## 配置

`LyricsConfiguration` 是完整的值类型配置。修改后赋给 `view.configuration` 即可，内部图层由视图维护。

```swift
var configuration = LyricsConfiguration()
configuration.fontName = "Helvetica Neue"
configuration.fontNameCJK = "PingFang SC"
configuration.fontSize = 34
configuration.alignPosition = 0.32
configuration.springDuration = 0.55
configuration.springBounce = 0.75
configuration.showTranslation = true
configuration.showRuby = true
configuration.palette.mainActive = .white
configuration.palette.mainInactive = LyricsColor(0.52, 0.55, 0.60)
configuration.motion.pointerExitDelay = 0
configuration.fpsCap = 60
configuration.renderScale = 0.75
view.configuration = configuration
```

位置弹簧优先使用 `springDuration` 与 `springBounce`；需要完全控制底层参数时再设置 `positionSpring`。

可用选项、默认值与常用组合见 [配置参考](Documentation/CONFIGURATION.md)。

## 生命周期与性能

- 每个可见歌词区域持有一个 `LyricsView`；同一区域只保留一套渲染状态。
- 视图移出屏幕或窗口被遮挡时，把 `automaticDisplayUpdates` 设为 `false`；重新出现时设为 `true`，必要时调用 `prepareWakeEntryAnimation()`。
- 彻底移除视图前调用 `releaseRenderingResources()`。
- 长时间运行或进入后台时，可调用 `pruneTransientCaches()` 释放视口外的字形缓存。
- 全屏封面模糊、多层合成场景可以用 `setPointerInteractionSuppressed(_:)`，让浮层接管指针事件。
- 高分辨率屏幕可以降低 `renderScale`，或用 `fpsCap` 限制刷新率；先用 Probe/Bench 测量，再决定取舍。

更完整的生命周期说明见 [接入指南](Documentation/INTEGRATION.md)，性能数据与测量方法见 [性能](Documentation/PERFORMANCE.md)。

## TTML 支持范围

内置解码器面向 AMLL 歌词 TTML：

- 默认按媒体绝对时间解释 `begin` / `end`；需要通用 W3C 父子相对时间时，显式使用 `TTMLDecoder(profile: .w3cRelative)`。
- 支持逐字 `span`、行级计时、对唱、伴唱、Ruby、翻译、罗马音、间奏标记与 `amll:meta` 元数据。
- 支持 iTunes / AMLL 扩展命名空间中的常用元数据字段。
- LRC、YRC、ASS 等格式可以先转换为 TTML，或自行构造 `LyricsDocument` 后调用 `install(document:)`。

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

Demo 支持用 `--library-root` 扫描包含 `Tracks/<track>/lyrics.ttml` 的目录。

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

MelismaKit 的职责是歌词渲染。曲库、音频播放、歌词抓取、封面提取、主题持久化与应用设置由接入方负责。组件通过值类型、配置与媒体时间同宿主协作。

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
| [许可证](Documentation/LICENSING.md) | AGPL 3.0 与第三方归属 |
| [源码溯源](Documentation/PROVENANCE.md) | 派生、原创与待考条目 |

## 实现来源

MelismaKit 解析 AMLL 兼容的 TTML 子集；计时、布局、动效与交互的部分函数从 [AMLL (Apple Music-like Lyrics)](https://github.com/steve-xmh/applemusic-like-lyrics) 源码转写为 Swift，属于派生作品。派生涉及 AMLL 的 `packages/core` 与 `packages/ttml`，范围见 [NOTICE](NOTICE)，逐符号记录见 [源码溯源](Documentation/PROVENANCE.md)。

MelismaKit 是独立项目，AMLL 由其作者维护。

## 许可证

本项目以 GNU Affero 通用公共许可证第 3 版（AGPL 3.0）分发。完整条款见 [LICENSE](LICENSE)，第三方归属见 [NOTICE](NOTICE)。
