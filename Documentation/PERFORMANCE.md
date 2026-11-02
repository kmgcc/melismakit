# 性能

本文记录 MelismaKit 的参考测量、复现命令与 CI 阈值。数字用于判断量级与回归，不是与机器无关的绝对承诺。

## 1. 测量口径

- 构建：Release，`swift build -c release`。
- 视口：760×720（`MelismaKitBench` / `MelismaKitProbe` 可通过参数调整）。
- 装载：TTML 解码（decode）+ 文档安装与首次布局（install）+ 总计。
- 稳态帧：120 fps 渲染 10 秒，丢弃首帧（首帧包含装载布局），nearest-rank 百分位，统计 `>8.33 ms` 与 `>16.67 ms` 的超预算帧数。
- 工具：`MelismaKitBench`，与 `MelismaKitProbe` 共用 `MelismaKitBenchCore` 的测量实现。

参考机器：Apple Silicon（arm64），macOS 26.6.2，Xcode 26.6 / Swift 6.3.3。以下数字是 2026 年 9 月的一次测量，用于量级参考。

## 2. 装载耗时（毫秒）

| 文档 | 行数 | decode | install | 总计 |
|---|---:|---:|---:|---:|
| 合成 word | 120 | 11.5–14.5 | 46–59 | 61–74 |
| 合成 word | 400 | 28–34 | 44–52 | 72–86 |
| Ruby | 120 | 10.9 | 94.7 | 105.6 |
| 行级计时 | 120 | 3.1 | 35.7 | 38.8 |
| 长词压力 | 120 | 5.6 | 132.0 | 137.6 |

- `install` 是装载的主要成本：首次 Core Text shaping、字形缓存构建与图层创建。
- 120 行 word 文档的 `install` 约占总计 70%–80%。
- 字体解析与文本度量按 key 缓存；同一进程内连续切歌不会重复支付全部字体发现成本。
- 长词压力是刻意构造的极端路径（每行一个超长单词），不是普通歌词的预期耗时。

## 3. 稳态帧耗时（毫秒，n=1200）

| 文档 | p50 | p95 | p99 | max | >8.33 ms | >16.67 ms |
|---|---:|---:|---:|---:|---:|---:|
| 120 行 word | 0.42–0.43 | 0.81–0.84 | 1.26–1.49 | 2.7–3.1 | 0 | 0 |
| 400 行 word | 0.60–0.67 | 1.04–1.53 | 1.54–2.28 | 2.2–12.7 | 0–4 | 0 |
| 120 行 Ruby | 0.322 | 0.533 | 1.009 | 1.680 | 0 | 0 |
| 120 行行级计时 | 0.114 | 0.276 | 0.495 | 1.317 | 0 | 0 |
| 120 行长词压力 | 5.098 | 8.231 | 11.057 | 46.441 | 59 | 2 |

- 普通 word / Ruby / 行级计时文档在 120 fps 下没有超预算帧。
- 长词压力路径会超出 8.33 ms 预算；它被保留为回归锚点，而不是性能目标。
- 每 glyph layer 每帧约 10 µs 的重建成本只发生在正在动画的行；静止行通过模糊烘焙与缓存避免重复合成。

## 4. 复现

```sh
# 五档基线（Release）
swift run -c release MelismaKitBench --scale 120 --mode word
swift run -c release MelismaKitBench --scale 400 --mode word
swift run -c release MelismaKitBench --scale 120 --mode ruby
swift run -c release MelismaKitBench --scale 120 --mode line
swift run -c release MelismaKitBench --scale 120 --mode longWord

# 机器可读 JSON（CI 门禁输入）
swift run -c release MelismaKitBench --scale 120 --json

# Probe 口径（--load-timing 报告 decode / install / 首帧）
swift run -c release MelismaKitProbe --scale 120 --load-timing /tmp/probe 10 760 720

# 语料库字节级校验
swift run --quiet MelismaKitBench --verify-fixtures
```

`MelismaKitBench --emit-fixtures` 会重新生成 `Fixtures/` 与 `SHA256SUMS.txt`。除非确实要更新语料库，否则不要提交重新生成的结果。

## 5. CI 阈值

CI 使用 `MelismaKitBench --scale 120 --json` 的输出，交给 `script/bench_gate.py`：

| 指标 | 阈值 |
|---|---:|
| `installMS` | 4000 |
| `frameP50` | 50 |
| `frameP99` | 100 |
| `frameMax` | 600 |
| `>8.33 ms` 帧数 | 900 |
| `>16.67 ms` 帧数 | 300 |

这些阈值是宽松的护栏，用于捕捉数量级回退，不是性能目标。它们刻意给不同机器、CI 负载与工具链版本留出余量。

验证门禁本身是否有效：把单行布局人为拖慢约 40 倍，`installMS` 应超过 4000 ms 并让脚本返回非零。仅调整 `reflowBatchLimit` 不会触发门禁，因为 10 秒连续播放测量不覆盖 Seek/焦点切换后的增量布局路径。

## 6. 已知事项

- **装载热点**：首次安装仍是主要成本，主体是 Core Text shaping 与 glyph 位图构建。400 行文档的 TTML 解码约 28–34 ms。
- **首次切歌**：宿主如果在主线程同步调用 `load`，会阻塞一次 `install`。大文档建议用 `decodeAsync` 解码，并把安装安排在对帧率不敏感的时刻。
- **模糊与辉光**：它们是 GPU/合成成本的主要来源。全屏常驻表面可以通过 `renderScale`、`fpsCap` 或关闭 `glow` / `blur` 控制预算。
- **多 surface**：每个可见 `LyricsView` 都有独立的图层与字形缓存。不要为同一区域创建多个实例。
- **宿主侧验证**：`script/summarize_profile.py` 可汇总 Instruments 导出数据；组件内的 Bench 不替代真实应用的窗口、全屏与合成路径测量。

性能改动应在提交中附上前后数字与复现命令。改变视觉行为的优化必须与纯性能改动分开提交。
