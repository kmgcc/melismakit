# 贡献指南

MelismaKit 的目标是成为一个可以独立接入、独立维护的 macOS 歌词组件。欢迎修 bug、补测试、改文档、提性能、扩展渲染能力。

## 1. 先确认边界

MelismaKit 专注歌词渲染。以下能力由宿主或其他项目提供：

- 音频播放、解码、设备管理；
- 曲库、文件扫描、歌词搜索与下载；
- 封面提取、主题存储、应用设置；
- 某个具体播放器的窗口、全屏、皮肤或状态模型；
- LRC / YRC / ASS 等格式的转换：先转为 TTML，再交给 MelismaKit 解码；新增解码器时与视图保持解耦。

改动涉及上述能力时，先开 issue 讨论边界。

## 2. 开发环境

- macOS 15 或更高版本
- Xcode 26 或兼容的 Swift 6.1+ 工具链
- 依赖限于 macOS 自带框架；开发环境使用 Xcode 与 Swift 工具链

```sh
git clone https://github.com/kmgcc/melismakit.git
cd melismakit
swift build
swift test
swift run MelismaKitDemo
```

Demo 是 AppKit 应用，必须在有窗口会话的 macOS 上运行。Probe 与 Bench 支持命令行运行。

## 3. 仓库结构

```text
Sources/MelismaKit/           核心渲染、解码、布局、动效、API
Sources/MelismaKitSwiftUI/    SwiftUI 挂载层
Sources/MelismaKitDemo/       AppKit 示例
Sources/MelismaKitProbe/      确定性渲染探针
Sources/MelismaKitBench/      性能基准 CLI
Sources/MelismaKitBenchCore/  测量与合成语料
Sources/MelismaKitParity/     上游行为对照工具
Tests/MelismaKitTests/        XCTest
Fixtures/                     可复现的合成 TTML 语料库
Documentation/                文档
script/                       基准门禁、截图与辅助脚本
```

## 4. 测试

提交前至少运行：

```sh
swift build --configuration debug -Xswiftc -warnings-as-errors
swift test --configuration debug
```

改性能相关代码时：

```sh
swift run -c release MelismaKitBench --scale 120 --json > /tmp/bench.json
python3 script/bench_gate.py /tmp/bench.json
```

改视觉行为时，附上同一输入的前后截图/GIF，并运行：

```sh
swift run MelismaKitProbe Sources/MelismaKitDemo/Resources/complex.ttml /tmp/probe 10 760 720 --paused
```

测试的完整说明见 [测试指南](Documentation/TESTING.md)。

## 5. 代码约定

- 使用 Swift 6.1 tools version，包保持 `swiftLanguageModes: [.v5]`。
- 视图与 UI 状态在 `@MainActor`；纯值模型保持 `Sendable`。
- 优先使用值类型和纯函数。组件只接收宿主传入的值、配置与回调。
- 依赖保持在 macOS 自带框架内；系统框架够用时直接使用。
- 宿主接口保持为 `LyricsConfiguration` 与明确的视图方法；内部图层的 API 留在组件内部。需要新能力时先扩展配置或视图方法。
- 日志使用 `OSLog`。
- API 需要文档注释；参数单位、默认值和线程约束要写清楚。
- 文档使用中文；代码注释沿用所在文件的现有语言，统一语言时以局部修改为主。

### 性能约定

- 改有性能含义的路径前，先记录当前数字。
- 纯性能改动与视觉改动分开提交。
- 解析可以移到后台；安装与图层操作留在主线程。
- 新增缓存必须有明确预算与清理路径。

### 许可证约定

从 AMLL 或其他 AGPL 代码转译的代码，必须在同一次提交中：

1. 在 [Documentation/PROVENANCE.md](Documentation/PROVENANCE.md) 增加符号条目；
2. 在 [NOTICE](NOTICE) 增加归属说明；
3. 在相关源文件头部加派生声明。

转译上游结构时，在同一次提交中记录来源；这是许可证合规要求。

## 6. 提交与 PR

- 一个提交只做一件事。标题描述可观察行为，例如 `Keep the last line visible at the end of a song`。
- 格式化、重命名与行为改动分别提交。
- PR 说明：改了什么、为什么、关键取舍、待验证的边界、实际运行的验证命令。
- 行为或视觉改动附截图/视频；性能改动附前后数字。
- 新增 API 或修改配置语义时，同步更新 `README.md`、`Documentation/` 与 `CHANGELOG.md`。
- 提交内容保持为源码与文档；`.build/`、DerivedData、临时截图与本机路径留在工作区。

### Issue

Bug 报告请包含：

- macOS 与 Swift/Xcode 版本；
- 最小复现（TTML 片段、配置、视图尺寸）；
- 期望行为与实际行为；
- 如果是视觉问题，附截图或录屏；
- 如果是性能问题，附 `MelismaKitBench` 或 Instruments 的相关数字。

## 7. 发布

发布由维护者执行。流程：

1. 确认 `main` 通过 CI，工作树干净。
2. 更新 `CHANGELOG.md`，写清用户可见的变化、破坏性变更与迁移方式。
3. 确认 `README.md` 中的安装版本与最低系统要求仍然准确。
4. 打 annotated tag：

   ```sh
   git tag -a v0.3.0 -m "MelismaKit v0.3.0"
   git push origin main
   git push origin v0.3.0
   ```

5. 在 GitHub 创建 Release，正文使用 `CHANGELOG.md` 对应段落，附上迁移说明与已知问题。
6. 如果宿主使用远程依赖，提醒接入方更新 `Package.resolved` 并重新验证。

版本规则：`0.x` 阶段，破坏性 API 变更提升次版本号；补丁版本保持源代码兼容。标签格式为 `vX.Y.Z`，从 `v0.2.0` 起使用 annotated tag。

## 8. 文档

- 用户接入看 [README](README.md)、[接入指南](Documentation/INTEGRATION.md)、[配置参考](Documentation/CONFIGURATION.md)。
- 维护者看 [架构](Documentation/ARCHITECTURE.md)、[测试指南](Documentation/TESTING.md)、[性能](Documentation/PERFORMANCE.md)。
- 许可证与溯源看 [LICENSING](Documentation/LICENSING.md)、[PROVENANCE](Documentation/PROVENANCE.md)、[NOTICE](NOTICE)。

文档面向第一次见到 MelismaKit 的开发者，聚焦组件本身的用法与实现；内部阶段编号、临时计划、个人机器路径与宿主应用的实现细节留在维护者手中。
