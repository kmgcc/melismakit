# 变更记录

本项目的版本记录从 `0.2.0` 开始。格式参考 Keep a Changelog，版本号遵循语义化版本。

## [Unreleased]

### 新增

- 位置弹簧优先使用 `springDuration` 与 `springBounce`，默认 `0.55` 与 `0.65`；`positionSpring` 保留为底层覆盖。

## [0.3.0] - 2026-11-02

这个版本把 MelismaKit 正式整理为独立的 macOS 歌词组件，并集中修复了增量安装与对唱间奏的行为。

### 新增

- 完整的接入、配置、架构、测试与贡献文档。
- `CHANGELOG.md`、Issue 模板与 PR 模板。
- 文档中明确区分展示时间偏移（`trackOffset`）与点击 Seek 偏移（`seekOffset`）。

### 变更

- 阶段性路线图、验证日志与行为踩坑记录已移出仓库；可复用的渲染契约并入架构文档，测试方法并入测试指南。
- 文档与示例使用 MelismaKit 的 API 与示例数据。
- README 的安装版本更新为 `0.3.0`。

### 修复

- 增量安装时保留已有歌词图层，切歌与重装过程保持连续画面。
- 对唱间奏标记与主行时间对齐。
- 行退场的高亮补齐在模糊返回前完成，最后一句保持亮度。
- 复用每个布局引擎的词分词器，减少进入重排时 NaturalLanguage 资源的重复初始化。

### 验证

- `swift build`（Debug/Release，warnings-as-errors）
- `swift test`
- `MelismaKitProbe` 真实规模冒烟
- `MelismaKitBench --verify-fixtures`
- `script/bench_gate.py`

## [0.2.2] - 2026-09-23

### 修复

- 将 parity 诊断从歌词渲染循环中移出，每帧路径只保留渲染工作。
- 减少播放期间模糊烘焙造成的卡顿。

## [0.2.1] - 2026-09-22

### 新增

- 静止行模糊烘焙：把静止行的模糊写入位图，render server 每帧直接复用。
- 离屏 bake/live 对照工具 `MelismaKitParity`。

### 性能

- 降低长时间播放时的合成开销，尤其是全屏与多行模糊场景。

## [0.2.0] - 2026-09-12

### 变更

- 包、产品与 target 正式更名为 `MelismaKit` / `MelismaKitSwiftUI`。
- 仓库从宿主项目中的实现抽取为独立 Swift Package，保留解码器、渲染器、测试、Demo 与 Probe。
- 增加独立构建、测试与基准入口。

### 新增

- `MelismaKitDemo` 的逐字、逐行、辉光、对唱/Ruby 与伴唱样本。
- `MelismaKitProbe` 确定性渲染与截图输出。
- 性能基准与合成 TTML 语料库。

### 文档

- 增加接入、许可证与源码溯源说明。
- 明确 AMLL 归属与 AGPL-3.0-only 分发方式。

[0.3.0]: https://github.com/kmgcc/melismakit/releases/tag/v0.3.0
[0.2.2]: https://github.com/kmgcc/melismakit/compare/v0.2.1...v0.2.2
[0.2.1]: https://github.com/kmgcc/melismakit/compare/v0.2.0...v0.2.1
[0.2.0]: https://github.com/kmgcc/melismakit/tree/v0.2.0
