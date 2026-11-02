# 许可证与代码溯源

MelismaKit 仅在 GNU Affero 通用公共许可证第 3 版（`AGPL-3.0-only`）下分发。完整的许可证文本见 [LICENSE](../LICENSE)。第三方归属声明见 [NOTICE](../NOTICE)。

SPDX-License-Identifier: AGPL-3.0-only

## 项目起源

本仓库是独立维护的 macOS 歌词渲染组件。它最初在一个 macOS 播放器项目中使用，随后抽取为不依赖任何宿主源码树的 Swift Package；原生渲染器、解码器、值模型、测试、合成测试固件（synthetic fixtures）、Demo 与 Probe 都随包独立维护。

## 上游归属致谢

本实现的开发旨在匹配 **AMLL (Apple Music-like Lyrics)** 在计时、布局、动效和交互方面的可观察行为 —— 并且对于部分函数，是通过直接研读其源代码而非公开文档来实现的。这些函数属于派生作品（derived works），在此予以致谢与声明。

| 项目 | 内容 |
|---|---|
| 项目名称 | Apple Music-like Lyrics (AMLL) |
| 仓库地址 | <https://github.com/steve-xmh/applemusic-like-lyrics> |
| 许可证 | `AGPL-3.0-only` |
| 派生涉及模块 | `packages/core`（歌词播放器、布局、动效、分词分块），`packages/ttml`（TTML 规范配置） |
| 参考查阅日期 | 2026-09-12 |
| 参考查阅的上游代码树 | 0.2.1 遗留分支（声明为 `GPL-3.0`），当前 main 主分支（声明为 `AGPL-3.0-only`） |

所派生的内容仅限于计时、布局、动效和交互行为。这些内容均经过了修改：从 TypeScript 转译为 Swift，并适配至 AppKit、Core Text 与 Core Animation。XML 解码器、Core Text 布局引擎、CALayer 图层树、数据值模型以及宿主媒体时钟处理逻辑均为原创实现。

MelismaKit **不是** AMLL 的官方移植版本，亦未隶属于 AMLL 项目或获得其背书。两者共享的是歌词文件格式规范，而非同一套代码库。

### 派生清单位置

[`Documentation/PROVENANCE.md`](PROVENANCE.md) 逐个符号记录了 8 个库源码文件中哪些函数属于派生、哪些属于独立原创，以及哪些尚无法完全确定。包含派生代码的文件均在文件头注释中指明了该清单链接。

由于上游代码树与本项目均采用 `AGPL-3.0-only`，因此许可证完全兼容，不涉及重新授权（relicensing）问题。AGPL 许可证第 5 条要求的归属致谢与“代码经过修改”的声明，由 [NOTICE](../NOTICE) 与本文档共同承担。

## 第三方依赖

本 Swift Package **不包含任何第三方 Package 依赖**。如 AppKit、Core Text、Core Animation、Core Image、Foundation、NaturalLanguage 和 SwiftUI 等系统框架均为 macOS 平台自带库，而非打包进项目的第三方源码。

`MotionTests` 包含一个根据 Pushkine 弹簧求解器公开发布的行为独立编写的闭式测试预言机（test oracle）。它并未打包该求解器的源码；测试文件中的注释记录了其 MIT 许可证参考来源。这也是后续任何参考实现应遵循的规范：自行编写测试验证逻辑，在注释中记录来源与许可证，绝不直接复制源码。

## 资源文件策略

项目内附带的 TTML 文件均为专门针对渲染器测试与 Demo 场景原创编写的合成测试固件。严禁在未记录溯源信息的情况下直接添加下载的歌词、封面图、音频或其他第三方资产。

因为歌词的著作权独立于录音制品，任何复现真实歌曲歌词的测试固件都需要充分的合规理由。请尽量编写原创文本；若确需引入，必须完整记录以下字段：

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

若该资产为真实歌曲的歌词，还必须说明为何原创合成固件无法满足相同目的。
```

缺少此类记录的测试固件不得合并入库。

## 本文档的法律边界

本文档记录了本组件采取的保守性合规选择。它并不构成将源自 AMLL 的衍生行为或未来任何第三方资产变更为其他许可证的许可授权。
