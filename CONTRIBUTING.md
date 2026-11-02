# 贡献指南

MelismaKit 的目标是成为一个可以独立接入、独立维护的 macOS 歌词组件。欢迎修 bug、补测试、改文档、提性能、扩展渲染能力。

## 1. 先确认边界

这个仓库只做歌词渲染。以下内容不属于这里：

- 音频播放、解码、设备管理；
- 曲库、文件扫描、歌词搜索与下载；
- 封面提取、主题存储、应用设置；
- 某个具体播放器的窗口、全屏、皮肤或状态模型；
- LRC / YRC / ASS 格式的内置解析（可以新增解码器，但不要把它和视图耦合）。

如果你的改动需要引入上述依赖，先开 issue 讨论边界，而不是直接提交。

## 2. 开发环境

- macOS 15 或更高版本
- Xcode 26 或兼容的 Swift 6.1+ 工具链
- 无第三方依赖；不需要额外的包管理器或环境变量

```sh
git clone https://github.com/kmgcc/melismakit.git
cd melismakit
swift build
swift test
swift run MelismaKitDemo
```

Demo 是 AppKit 应用，必须在有窗口会话的 macOS 上运行。Probe 与 Bench 支持无交互运行。

## 3. 仓库结构

```text
Sources/MelismaKit/           核心渲染、解码、布局、动效、公开 API
Sources/MelismaKitSwiftUI/    SwiftUI 挂载层
Sources/MelismaKitDemo/       AppKit 示例
Sources/MelismaKitProbe/      确定性渲染探针
Sources/MelismaKitBench/      性能基准 CLI
Sources/MelismaKitBenchCore/  测量与合成语料
Sources/MelismaKitParity/     上游行为对照工具
Tests/MelismaKitTests/        XCTest
Fixtures/                     可复现的合成 TTML 语料库
Documentation/                公开文档
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
- 优先使用值类型和纯函数。不要把宿主的状态、通知或单例带进组件。
- 不新增第三方依赖。系统框架足够时，不引入包。
- 不操作内部图层的公共 API 不属于宿主接口；需要新能力时先扩展 `LyricsConfiguration` 或明确的视图方法。
- 日志使用 `OSLog`，不要在库里留 `print`。
- 公开 API 需要文档注释；参数单位、默认值和线程约束要写清楚。
- 文档使用中文；代码注释沿用所在文件的现有语言，不要为了统一而大面积重写注释。

### 性能约定

- 改有性能含义的路径前，先记录当前数字。
- 纯性能改动与视觉改动分开提交。
- 不在主线程做可以移到后台的解析；安装与图层操作仍然留在主线程。
- 新增缓存必须有明确预算与清理路径。

### 许可证约定

从 AMLL 或其他 AGPL 代码转译的代码，必须在同一次提交中：

1. 在 [Documentation/PROVENANCE.md](Documentation/PROVENANCE.md) 增加符号条目；
2. 在 [NOTICE](NOTICE) 增加归属说明；
3. 在相关源文件头部加派生声明。

只抄结构、不记录来源，属于许可证合规缺陷，不是风格问题。

## 6. 提交与 PR

- 一个提交只做一件事。标题描述可观察行为，例如 `Keep the last line visible at the end of a song`。
- 不把格式化、重命名和行为改动混在一起。
- PR 说明：改了什么、为什么、关键取舍、未覆盖的边界、实际运行的验证命令。
- 行为或视觉改动附截图/视频；性能改动附前后数字。
- 新增公开 API 或修改配置语义时，同步更新 `README.md`、`Documentation/` 与 `CHANGELOG.md`。
- 不提交 `.build/`、DerivedData、临时截图或本机路径。

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

文档里不要写内部阶段编号、临时计划、个人机器路径或某个宿主应用的私有实现。这个仓库的读者是第一次见到 MelismaKit 的开发者。
