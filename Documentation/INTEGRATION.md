# 接入指南

本文面向第一次把 MelismaKit 放进 macOS 应用的开发者。它说明组件与宿主的职责边界、推荐生命周期、时钟契约，以及几个容易接错的细节。

## 1. 边界

| 职责 | MelismaKit | 宿主应用 |
|---|---|---|
| TTML 解析、计时预处理、行/词时间轴 | 负责 | 提供原始 `Data` 或已解析文档 |
| 排版、图层、动画、滚动、命中测试 | 负责 | 不操作内部图层 |
| 歌词点击目标与回传时间 | 通过 `onSeek` 回传 | 执行播放器 Seek |
| 媒体时钟的采样与预测 | 在采样之间插值 | 提供媒体时间与播放状态 |
| 曲库、音频播放、封面、主题、持久化 | 不包含 | 负责 |
| SwiftUI 生命周期 | 提供薄挂载层 | 持有 `LyricsView` 的生命周期 |

MelismaKit 不读取应用 Bundle、设置存储、主题存储或曲库注册表。它只通过值类型、配置对象、`onSeek` 与 `synchronize` 和宿主通信。

## 2. 最小生命周期

```text
创建 LyricsView
  └─ 设置 configuration / onSeek / onFrame
       └─ load(ttml:) 或 install(document:)
            └─ synchronize(time:playing:)  ← 播放、暂停、Seek、切歌
                 └─ clear() 或 releaseRenderingResources()  ← 移除
```

`LyricsView` 是 `@MainActor` 的 `NSView`。在主线程创建、配置、加载与同步。解析可以在后台完成，安装必须回到主线程。

## 3. 创建与挂载

### AppKit

```swift
@MainActor
final class LyricsPanelController: NSViewController {
    let lyrics = LyricsView(frame: .zero)

    override func loadView() {
        view = lyrics
    }
}
```

`LyricsView` 没有内在内容尺寸；它填满 Auto Layout 或父视图给它的 bounds。请显式设置宽高约束，或在 `viewDidLayout` 中设置 frame。

### SwiftUI

```swift
struct LyricsPanel: View {
    let lyrics: LyricsView

    var body: some View {
        MelismaKitViewRepresentable(view: lyrics)
            .frame(minHeight: 220)
    }
}
```

`MelismaKitViewRepresentable` 只负责把已有的 `LyricsView` 放进 SwiftUI 视图树。它不复制配置、播放状态或回调。`LyricsView` 应当由 `@StateObject` 控制器、`@State` 中的引用类型模型，或更高层的服务持有。

不要这样写：

```swift
// 错误：SwiftUI 重建视图时会创建新的渲染器
var body: some View {
    MelismaKitViewRepresentable(view: LyricsView(frame: .zero))
}
```

## 4. 加载文档

### 同步加载

```swift
try lyrics.load(ttml: data, time: mediaTime, playing: isPlaying)
```

`load` 会先解码，再替换当前文档。解码失败会抛出 `LyricsError.invalidTTML`，上一份有效歌词保持不变。

### 异步解析

```swift
let document = try await TTMLDecoder().decodeAsync(data)
lyrics.install(document: document, time: mediaTime, playing: isPlaying)
```

`TTMLDecoder` 是 `Sendable` 值类型；`LyricsDocument` 也是不可变值数据。可以在后台任务中解码，再回到主线程安装。

### 清空

```swift
lyrics.clear(time: mediaTime, playing: isPlaying)
```

没有歌词时不要 `load` 一份空字符串并期待它被当作“无歌词”；使用 `clear`。它保留播放状态，之后可以原子地安装下一份文档。

### 文档缓存

`LyricsDocument` 可以安全地缓存和共享。一个常见的做法是按“曲目 ID + 歌词文本”缓存最近两份文档，切歌时先命中缓存，避免重复解析。不要在每次 `synchronize` 时重新 `load`；那会重建图层并打断动画。

## 5. 时钟契约

### 单位

所有公开时间都是**秒**，属于媒体时间域。不要传毫秒、`CACurrentMediaTime()` 的绝对秒数或播放器内部帧号。

### 采样频率

宿主不需要每帧调用。播放、暂停、Seek、切歌、窗口重新出现时各调用一次即可；`LyricsView` 会在两次采样之间根据 `hostTime` 预测。也可以以 10–30 Hz 周期采样，行为相同。

```swift
lyrics.synchronize(time: player.currentTime, playing: player.isPlaying)
```

### hostTime

`hostTime` 默认取 `CACurrentMediaTime()`。只有当宿主能提供同一时钟域的单调时间时才显式传入；否则省略。

```swift
lyrics.synchronize(
    time: mediaTime,
    playing: isPlaying,
    hostTime: CACurrentMediaTime()
)
```

### Seek

```swift
lyrics.synchronize(
    time: targetTime,
    playing: isPlaying,
    seek: true,
    motion: .immediate
)
```

- `seek: true` 会立刻重置图层栈，取消排队的弹簧动画。
- `motion: .immediate` 用于进度条拖动、快进/快退与显式跳转。
- `motion: .cascade` 用于点击歌词后的级联滚动。
- `motion: .preview` 用于拖动时的预览状态。

`synchronize` 返回视图当前预测的媒体时间，通常可以忽略；需要和播放器对齐时可以使用返回值。

### 暂停

暂停时传 `playing: false`，时间保持精确。不要停止采样却继续把 `playing` 留在 `true`，否则视图会按旧速度继续预测。

## 6. 点击与交互

```swift
lyrics.onSeek = { mediaTime in
    player.seek(to: mediaTime)
}
```

`onSeek` 的参数是源媒体时间，已经包含 `configuration.timing.seekOffset`。若宿主还有全局延迟，应当在前置处理中合并，不要再次叠加。

视图自身处理：

- 鼠标悬停：清除行模糊，移出后按 `motion.pointerExitDelay` 恢复；
- 滚轮：手动浏览，暂停自动跟随；5 秒无操作后恢复，或调用 `followCurrentLyrics()`；
- 右键：复制当前行歌词；
- 点击：回传 Seek 时间。

如果歌词上方有浮层或全屏遮罩，调用：

```swift
lyrics.setPointerInteractionSuppressed(true)
```

恢复时传 `false`，视图会根据当前屏幕指针位置重新协调 hover 状态，而不是等待下一次鼠标移动。

需要在宿主重新挂载视图时恢复指针状态，可以调用：

```swift
lyrics.setPointerInside(false)
```

### 自定义命中测试

```swift
if let index = lyrics.groupIndex(at: point),
   let time = lyrics.seekTime(forGroup: index) {
    // 自定义菜单或跳转
}
```

`groupIndex(at:)` 使用视图坐标；`seekTime(forGroup:)` 返回该行的源媒体时间。

### 快照

```swift
let image = lyrics.snapshotImage(scale: 2)
```

用于导出、测试或调试。它会应用与屏幕一致的模糊滤镜，并用 `configuration.backdropColor` 填充背景。

## 7. 可见性与资源

### 隐藏

```swift
lyrics.automaticDisplayUpdates = false
```

窗口被遮挡、切到后台、进入迷你播放器时停止 DisplayLink。`LyricsView` 也会在 `viewDidHide`、窗口最小化或不可见时自行停止，但显式关闭更可靠。

### 重新出现

```swift
lyrics.automaticDisplayUpdates = true
lyrics.prepareWakeEntryAnimation()
```

`prepareWakeEntryAnimation()` 只在文档已安装、已有首帧且不在入场动画中时生效，避免把一次加载入场打断成第二次动画。

### 彻底移除

```swift
lyrics.releaseRenderingResources()
```

释放图层、字形缓存与 DisplayLink。文档仍然保留；如果要复用同一个视图，重新安装文档或让它重新布局。

### 后台维护

```swift
lyrics.pruneTransientCaches()
```

把字形缓存压到预算的一半，并释放不可见行的内容。适合在进入后台、长时间暂停或内存压力通知中调用。

## 8. 配置

配置是值类型：

```swift
var configuration = LyricsConfiguration()
configuration.fontSize = 30
configuration.showTranslation = false
configuration.motion.blurRadius = 1.5
lyrics.configuration = configuration
```

完整字段、默认值与常用组合见 [配置参考](CONFIGURATION.md)。

几个接入时最容易忽略的项：

- `fontNameCJK`：主字体只覆盖拉丁字形时，CJK 会回退到系统字体；显式指定 CJK 字体可以让中日韩文与拉丁文的字重一致。
- `alignPosition`：焦点行在视图高度中的相对位置，`0.35` 表示偏上；窗口面板通常可以在 `0.28–0.38` 之间调整。
- `renderScale`：相对于 backing scale 的渲染比例，不是绝对像素；全屏常驻 surface 可以用 `0.75`。
- `fpsCap`：`0` 跟随显示器原生刷新率；需要省电时设 `60`。
- `timing.trackOffset`：只影响展示时间；`timing.seekOffset`：只影响 `onSeek` 回传的时间。不要混用。
- `surface` 与 `coverBlur*`：只有在做封面模糊或多层合成时才需要；普通窗口保持 `.window` 与 `.full`。

## 9. 多 surface

一个应用可以同时有窗口歌词、全屏歌词、迷你播放器歌词与预览面板。推荐：

- 每个可见 surface 一个 `LyricsView`；
- 同一首歌的 `LyricsDocument` 可以在多个视图之间共享；
- 每个 surface 自己持有配置与可见性状态；
- 不要把一个 `LyricsView` 同时挂到两个父视图；
- 切换宿主（窗口 ↔ 全屏）时，先关闭旧宿主，再挂到新宿主，并调用 `prepareWakeEntryAnimation()`。

```swift
let document = try TTMLDecoder().decode(data)
windowLyrics.install(document: document, time: t, playing: p)
fullscreenLyrics.install(document: document, time: t, playing: p)
```

## 10. 错误处理

`TTMLDecoder.decode` 与 `LyricsView.load` 只抛出 `LyricsError.invalidTTML(String)`。常见原因：

- 根元素不是 TTML 命名空间中的 `tt`；
- 文档包含外部实体或 DOCTYPE；
- 时间属性无法解析；
- 歌词结构缺少必要的 `p` / `span`。

接入时建议保留“上一份有效歌词”，在解码失败时记录错误但不要清空画面。MelismaKit 的 `load` 已经遵循这个顺序：解析成功后才替换文档。

## 11. 更新依赖

```sh
swift package update MelismaKit
```

Xcode：**File → Packages → Update to Latest Package Versions**。

更新后重新运行宿主测试，重点检查：

- 公开 API 是否有弃用或签名变化；
- 自定义配置字段是否仍存在；
- 歌词点击回传时间是否仍符合宿主 Seek 策略；
- 全屏与多 surface 的重新挂载是否正常。

版本策略与变更记录见 [CHANGELOG.md](../CHANGELOG.md)。

## 12. 接入检查清单

- [ ] `LyricsView` 由控制器/模型持有，不在 SwiftUI `body` 中创建。
- [ ] 传入的是秒，不是毫秒。
- [ ] 播放/暂停/Seek/切歌都会调用 `synchronize`。
- [ ] Seek 使用 `seek: true` 与合适的 `motion`。
- [ ] `onSeek` 的偏移只应用一次。
- [ ] 隐藏时关闭 `automaticDisplayUpdates`。
- [ ] 移除前调用 `releaseRenderingResources`。
- [ ] 窗口、全屏、迷你播放器使用独立 surface。
- [ ] 大文档在后台解码，再回主线程 `install`。
- [ ] 高分辨率屏幕上确认 `renderScale` 与 `fpsCap` 的实际观感与开销。

## 13. 常见问题

**歌词不显示。** 检查视图 bounds 是否为零、是否已加入窗口、`document` 是否非空、`automaticDisplayUpdates` 是否为 `true`、调色板 alpha 是否为零。

**文字发虚。** `renderScale` 小于 1 会降低 glyph mask 分辨率；全屏或 5K 屏幕上先尝试 `1`，再按性能预算下调。

**时间越走越偏。** 检查单位与 `hostTime` 时钟域。不要传播放器内部的绝对主机时间作为媒体时间。

**点击 Seek 偏了几百毫秒。** 通常是 `trackOffset` 与 `seekOffset` 重复叠加，或宿主又在 `onSeek` 外加了一次全局延迟。

**暂停后仍在动。** 确认暂停时传了 `playing: false`；如果宿主停止了采样但没有通知视图，视图会继续按最后一次状态预测。

**全屏切换后 hover 或模糊不恢复。** 挂载后调用 `setPointerInside(false)`，重新出现时调用 `prepareWakeEntryAnimation()`。

## 14. `LyricsView` 方法速查

| API | 用途 |
|---|---|
| `configuration` | 读写当前 `LyricsConfiguration` |
| `onSeek` | 歌词点击回传源媒体时间 |
| `onFrame` | 每次渲染后的帧快照；只做轻量诊断 |
| `document` | 当前已安装文档，只读 |
| `lastFrame` | 最近一帧的 `LyricsFrame` |
| `automaticDisplayUpdates` | 开启/关闭 DisplayLink 驱动 |
| `isDisplayUpdateRunning` | DisplayLink 是否在运行 |
| `isFollowing` | 是否处于自动跟随 |
| `load(ttml:time:playing:hostTime:)` | 同步解码并安装 |
| `install(document:time:playing:hostTime:)` | 安装已解码文档 |
| `clear(time:playing:hostTime:)` | 清空当前歌词 |
| `synchronize(time:playing:seek:motion:hostTime:)` | 提交播放采样 |
| `followCurrentLyrics()` | 立即恢复自动跟随 |
| `prepareWakeEntryAnimation()` | 重新显示时的入场 |
| `releaseRenderingResources()` | 释放图层、缓存与 DisplayLink |
| `pruneTransientCaches()` | 压缩缓存、释放不可见行 |
| `scroll(by:hostTime:)` | 宿主驱动的滚动 |
| `setPointerInside(_:hostTime:)` | 同步指针进入/移出 |
| `setPointerInteractionSuppressed(_:hostTime:)` | 浮层期间抑制指针交互 |
| `groupIndex(at:)` | 命中测试 |
| `seekTime(forGroup:)` | 行的源媒体时间 |
| `snapshotImage(scale:)` | 导出当前画面 |
| `render(at:)` | 在指定宿主时间显式渲染，供测试/离屏使用 |

`onFrame` 在渲染路径中调用；不要在回调里做同步 I/O、重新布局或再次调用 `render`。`render(at:)` 会推进一次渲染状态，正常接入时不需要手动调用。
