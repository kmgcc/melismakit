# 许可证与代码来源

MelismaKit 以 GNU Affero 通用公共许可证第 3 版（AGPL 3.0）分发。完整条款见 [LICENSE](../LICENSE)，第三方归属见 [NOTICE](../NOTICE)。

## 项目起源

MelismaKit 最初是我们为 macOS 播放器写的歌词界面，后来从我们的应用中剥离，成为独立的歌词项目。原生渲染器、解码器、值模型、测试、合成测试固件（synthetic fixtures）、Demo 与 Probe 随包维护。

## AMLL

歌词的计时、布局、动效与交互基于 **AMLL (Apple Music-like Lyrics)** 的源码开发，部分函数从 TypeScript 转写为 Swift，并适配 AppKit、Core Text 与 Core Animation。XML 解码器、Core Text 布局引擎、CALayer 图层树、值模型与宿主时钟处理为独立实现。

| 项目 | 内容 |
|---|---|
| 项目名称 | Apple Music-like Lyrics (AMLL) |
| 仓库地址 | <https://github.com/steve-xmh/applemusic-like-lyrics> |
| 许可证 | `AGPL-3.0-only` |
| 派生涉及模块 | `packages/core`（歌词播放器、布局、动效、分词分块），`packages/ttml`（TTML 规范配置） |
| 参考查阅日期 | 2026-09-12 |
| 参考查阅的上游代码树 | 0.2.1 遗留分支（声明为 `GPL-3.0`），当前 main 主分支（声明为 `AGPL-3.0-only`） |

派生内容限于计时、布局、动效与交互行为。上游与本项目同为 AGPL 3.0，许可证兼容。逐符号清单见 [源码溯源](PROVENANCE.md)。

## 依赖

本包使用 macOS 自带的 AppKit、Core Text、Core Animation、Core Image、Foundation、NaturalLanguage 与 SwiftUI。`MotionTests` 含一个独立编写的闭式测试预言机（test oracle），依据 Pushkine 弹簧求解器的行为编写；测试注释记录了 MIT 来源。

## 资源文件

项目内的 TTML 文件均为原创合成测试固件。新增歌词、封面、音频等第三方资产时，在合并前记录以下字段：

```markdown
### <资产文件名>

| 字段 | 内容 |
|---|---|
| 资产类型 | 例如：TTML 歌词文件 / 封面图片 / 音频片段 |
| 来源 | URL，或生成该资产的精确命令与输入数据 |
| 作者 / 权利人 | 姓名，或标明 "generated"（自动生成） |
| 许可证 | SPDX 标识符，或注明 "由 <权利人> 于 <日期> 授权许可" |
| 引入者 / 日期 | 引入人及具体日期 |
| 引入原因 | 依赖该资产的具体测试或 Demo 场景 |

若资产为真实歌曲的歌词，请说明该资产对应的测试目的。
```

测试固件合并入库前，补齐上述记录。
