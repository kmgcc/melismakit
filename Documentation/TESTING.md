# 测试指南

MelismaKit 的测试分三层：解码与纯逻辑的 XCTest、渲染状态的行为回归，以及 Demo/Probe 的确定性输出。性能测量与 CI 阈值见 [PERFORMANCE.md](PERFORMANCE.md)。

## 1. 环境

- macOS 15 或更高版本
- Swift 6.1 或更高版本的工具链
- Xcode（Demo 与 Probe 需要 AppKit 运行环境）

```sh
git clone https://github.com/kmgcc/melismakit.git
cd melismakit
swift package dump-package
```

## 2. 常用命令

```sh
# 构建
swift build --configuration debug
swift build --configuration release -Xswiftc -warnings-as-errors

# 测试
swift test --configuration debug

# Demo
swift run MelismaKitDemo
swift run MelismaKitDemo --ttml /path/to/lyrics.ttml

# 探针（确定性渲染 + 可选截图）
swift run MelismaKitProbe Sources/MelismaKitDemo/Resources/complex.ttml /tmp/probe 10 760 720 --paused

# 性能基准
swift run -c release MelismaKitBench --scale 120

# 语料库校验
swift run --quiet MelismaKitBench --verify-fixtures
```

CI 会同时跑 Debug 与 Release 的 warnings-as-errors、测试、Probe 冒烟、语料库校验与性能门禁。

## 3. 测试分层

| 文件 | 覆盖 |
|---|---|
| `DecoderTests` | TTML 基础结构、媒体绝对时间、W3C 相对时间、元数据、Ruby、翻译、罗马音、对唱与伴唱 |
| `DecoderRobustnessTests` | 畸形 XML、命名空间、外部实体、异常时间属性、空白与边界输入 |
| `TimelineTests` | 播放集合、高亮集合、焦点、间奏、结尾、Seek 行为 |
| `TimingPolicyTests` | 提前量、相邻行切换、重叠、倒流、行尾补齐 |
| `LayoutTests` | 字体、度量、CJK/拉丁分块、Ruby/翻译布局、换行与重排 |
| `MotionTests` | 弹簧、重音包络、间奏采样、退场 |
| `BehaviorRegressionTests` | 模糊、点击级联、遮罩顺序、预测、伴唱展开、重音清理、退出补齐 |
| `IncrementalInstallationTests` | 切歌/重装时保留图层、增量布局与状态转换 |
| `SyntheticCorpusTests` | `Fixtures/` 语料库的字节级完整性与生成器一致性 |

新增可观察行为时，至少补一个确定性单元测试；改渲染状态机时，优先在 `BehaviorRegressionTests` 或 `IncrementalInstallationTests` 中补回归。

## 4. 语料库

`Fixtures/` 是可复现的合成 TTML 语料库，覆盖：

- 行级计时与逐字计时；
- Ruby、翻译、罗马音；
- 对唱与间奏；
- CJK、Emoji、RTL 与组合字符；
- 长词压力。

`Fixtures/SHA256SUMS.txt` 记录字节哈希。`MelismaKitBench --verify-fixtures` 会重新生成并比对；结果相符时通过，出现差异时脚本以失败退出。语料库需要更新时，把重新生成的结果与生成器变更一起提交。

Demo 另有 `Sources/MelismaKitDemo/Resources/` 下的展示样本；它们与测试语料库分开维护。

## 5. Probe 与截图

`MelismaKitProbe` 用内置合成文档或指定 TTML 渲染固定帧数，输出帧耗时与缓存统计。它适合：

- 快速确认渲染器稳定、帧耗时保持在预算内；
- 生成 README 中的确定性截图；
- 脱离完整应用复现布局问题。

```sh
swift run MelismaKitProbe Sources/MelismaKitDemo/Resources/duet-ruby.ttml /tmp/probe 10 760 720 --paused
```

Probe 默认把截图写到输出目录。提交视觉改动时，附上同一输入的前后截图或短视频。

## 6. 视觉检查

人工视觉确认仍是必要环节。改动排版、动效或合成后，至少检查：

- 窗口与实色全屏两种 surface；
- 播放、暂停、Seek、切歌；
- 窗口缩放与多显示器 backing scale；
- 指针进入/移出、滚轮浏览、点击 Seek；
- 长歌词、空歌词、仅含翻译/Ruby 的文档；
- 深色与浅色调色板；
- 低 `renderScale` 与 60 fps 上限下的清晰度/流畅度取舍。

Demo 顶部的控制项可以切换 surface、计时模式、通道混合、字号、辉光、间奏点大小，并用“Colored blend test”检查内部高亮通道。

## 7. CI 与提交前检查

仓库的 GitHub Actions 在 push 与 PR 上运行：

1. `swift package dump-package`
2. Debug 与 Release 的 `-warnings-as-errors` 构建
3. `swift test`
4. `MelismaKitProbe` 真实规模冒烟
5. `MelismaKitBench --verify-fixtures`
6. `script/bench_gate.py` 性能门禁

本地提交前至少运行：

```sh
swift build --configuration debug -Xswiftc -warnings-as-errors
swift test --configuration debug
git diff --check
```

视觉或性能改动再附加：

```sh
swift run -c release MelismaKitBench --scale 120 --json > /tmp/bench.json
python3 script/bench_gate.py /tmp/bench.json
```

## 8. 包测试的覆盖范围

组件测试覆盖解码、计时、布局与渲染；宿主特有的窗口、全屏、皮肤、主题映射、播放器时钟与资源生命周期由接入方在自己的工程中验证：

- 窗口、全屏、迷你播放器与预览 surface；
- 播放器 Seek、切歌、暂停与恢复；
- 主题与封面颜色映射；
- 视图重设父容器与重新挂载；
- 应用重启后的恢复；
- 真实音频设备的时钟行为。

## 9. 添加测试

- 纯逻辑优先：解码、计时、布局与运动采样都应当可以脱离窗口测试。
- 时间相关的测试使用显式采样，时钟由测试用例提供。
- 渲染状态测试使用 `LyricsView.render(at:)` 或 `snapshotImage`，让测试脱离实际显示刷新。
- 测试夹具使用原创合成文本。
- 新测试文件加入 `Tests/MelismaKitTests/`，`Package.swift` 保持原样（测试 target 自动包含目录）。
