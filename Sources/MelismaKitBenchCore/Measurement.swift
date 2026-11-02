import AppKit
import Foundation
import MelismaKit

/// Bench 与 Probe 共用的测量统计。
///
/// 本模块与 `MelismaKitProbe` 保持**完全相同的口径**（nearest-rank 百分位、丢首帧、
/// 120fps 渲染），确保 Bench 与 Probe 的数字可以直接互相印证。
public enum Measure {

    /// 帧耗时分布统计（单位：毫秒）。
    public struct FrameStats: Codable, Sendable {
        public var count: Int
        public var p50: Double
        public var p95: Double
        public var p99: Double
        public var max: Double
        /// > 8.33ms（120Hz 帧预算）的帧数
        public var over8ms: Int
        /// > 16.67ms（60Hz 帧预算）的帧数
        public var over16ms: Int

        public init(values: [Double]) {
            let sorted = values.sorted()
            count = sorted.count
            max = sorted.last ?? 0
            func percentile(_ q: Double) -> Double {
                guard !sorted.isEmpty else { return 0 }
                return sorted[Int(Double(sorted.count - 1) * q)]
            }
            p50 = percentile(0.50)
            p95 = percentile(0.95)
            p99 = percentile(0.99)
            over8ms = sorted.filter { $0 > 8.33 }.count
            over16ms = sorted.filter { $0 > 16.67 }.count
        }
    }

    /// 装载计时：decode / install（布局+首帧）/ 稳态首帧 分离。
    public struct LoadTiming: Codable, Sendable {
        public var decodeMS: Double
        /// 含布局与 install 内首帧，≈ §2.2「布局占比」的主体
        public var installMS: Double
        /// install 后补的一帧稳态渲染
        public var firstRenderMS: Double
        /// decode + install，≈ §2.2 的 `load()` 总计
        public var totalMS: Double
    }

    /// 装载计时：全新视图上先 decode，再 install，再补一帧稳态渲染。
    @MainActor
    public static func loadTiming(ttml: Data, width: Double, height: Double) throws -> LoadTiming {
        _ = NSApplication.shared
        let decodeStart = CACurrentMediaTime()
        let document = try TTMLDecoder().decode(ttml)
        let installStart = CACurrentMediaTime()
        let view = LyricsView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.automaticDisplayUpdates = false
        view.install(document: document, time: 0, playing: false, hostTime: 0)
        let renderStart = CACurrentMediaTime()
        view.render(at: 0)
        let end = CACurrentMediaTime()
        return LoadTiming(
            decodeMS: (installStart - decodeStart) * 1000,
            installMS: (renderStart - installStart) * 1000,
            firstRenderMS: (end - renderStart) * 1000,
            totalMS: (renderStart - decodeStart) * 1000
        )
    }

    /// 帧耗时测量：以 120fps 渲染 `seconds` 秒的播放，返回全部帧与分布统计。
    /// 统计基于 `dropFirst()`（首帧包含装载布局，不参与稳态分布，与 Probe 口径一致）。
    @MainActor
    public static func frameTiming(
        ttml: Data,
        seconds: Double,
        fps: Double = 120,
        width: Double,
        height: Double
    ) throws -> (view: LyricsView, frames: [LyricsFrame], stats: FrameStats) {
        _ = NSApplication.shared
        let view = LyricsView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        view.automaticDisplayUpdates = false
        try view.load(ttml: ttml, time: 0, playing: true, hostTime: 0)
        let total = Int(max(0, seconds) * fps)
        var frames: [LyricsFrame] = []
        frames.reserveCapacity(total + 1)
        for tick in 0...total {
            frames.append(view.render(at: Double(tick) / fps))
        }
        let stats = FrameStats(values: frames.dropFirst().map(\.renderMilliseconds))
        return (view, frames, stats)
    }
}
