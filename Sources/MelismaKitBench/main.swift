import CryptoKit
import Foundation
import MelismaKit
import MelismaKitBenchCore

// MARK: - 命令行参数

private struct Options {
    enum Action { case bench, emitFixtures, verifyFixtures, help }

    var action: Action = .bench
    var scale = 120
    var mode: SyntheticTTML.ScaleMode = .word
    var seconds = 10.0
    var width = 760.0
    var height = 720.0
    var measureLoad = true
    var measureFrames = true
    var json = false
    var fixturesDir = "Fixtures"
}

private let helpText = """
用法:
  MelismaKitBench [选项]

规模测量（默认）:
  --scale <N>        生成 N 行文档（默认 120）
  --mode <word|line|ruby|longWord>   文档类型（默认 word）
  --seconds <S>      帧测量时长，秒（默认 10，即 1200 帧 @120fps）
  --width/--height   视口尺寸（默认 760×720）
  --load-only / --frames-only   只测装载 / 只测帧
  --json             追加输出单行 JSON 摘要（CI 阈值护栏解析用）

语料库:
  --emit-fixtures [dir]     重新生成 Fixtures/ 语料库 + SHA256SUMS.txt（默认目录 Fixtures）
  --verify-fixtures [dir]   重新生成并与磁盘比对（字节一致 + 哈希），不一致退出码 1

示例:
  swift run MelismaKitBench --scale 120
  swift run MelismaKitBench --scale 400 --mode ruby --seconds 10
  swift run MelismaKitBench --emit-fixtures
"""

private func parseArgs() -> Options {
    var o = Options()
    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    func next(_ fallback: String) -> String {
        defer { i += 1 }
        guard i + 1 < args.count else { return fallback }
        return args[i + 1]
    }
    while i < args.count {
        switch args[i] {
        case "--scale": o.scale = Int(next("120")) ?? o.scale
        case "--mode": o.mode = SyntheticTTML.ScaleMode(rawValue: next("word")) ?? .word
        case "--seconds": o.seconds = Double(next("10")) ?? o.seconds
        case "--width": o.width = Double(next("760")) ?? o.width
        case "--height": o.height = Double(next("720")) ?? o.height
        case "--load-only": o.measureFrames = false
        case "--frames-only": o.measureLoad = false
        case "--json": o.json = true
        case "--emit-fixtures":
            o.action = .emitFixtures
            if i + 1 < args.count, !args[i + 1].hasPrefix("--") { i += 1; o.fixturesDir = args[i] }
        case "--verify-fixtures":
            o.action = .verifyFixtures
            if i + 1 < args.count, !args[i + 1].hasPrefix("--") { i += 1; o.fixturesDir = args[i] }
        case "--help", "-h": o.action = .help
        default: break
        }
        i += 1
    }
    return o
}

// MARK: - 语料库生成与校验

private func emitFixtures(_ dir: String) throws {
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var manifest: [String] = []
    for file in SyntheticTTML.CorpusFile.allCases {
        let data = Data(SyntheticTTML.corpus(file).utf8)
        try data.write(to: URL(fileURLWithPath: (dir as NSString).appendingPathComponent(file.fileName)))
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        manifest.append("\(digest)  \(file.fileName)")
    }
    let manifestText = manifest.joined(separator: "\n") + "\n"
    try Data(manifestText.utf8).write(to: URL(fileURLWithPath: (dir as NSString).appendingPathComponent("SHA256SUMS.txt")))
    print("生成 \(SyntheticTTML.CorpusFile.allCases.count) 个语料文件 + SHA256SUMS.txt -> \(dir)")
}

private func verifyFixtures(_ dir: String) -> Bool {
    var ok = true
    var recomputed: [String] = []
    for file in SyntheticTTML.CorpusFile.allCases {
        let expected = Data(SyntheticTTML.corpus(file).utf8)
        let path = URL(fileURLWithPath: (dir as NSString).appendingPathComponent(file.fileName))
        guard let disk = try? Data(contentsOf: path) else {
            print("FAIL\t缺失\t\(file.fileName)")
            ok = false
            continue
        }
        let digest = SHA256.hash(data: expected).map { String(format: "%02x", $0) }.joined()
        recomputed.append("\(digest)  \(file.fileName)")
        if disk == expected {
            print("OK\t字节一致\t\(file.fileName)")
        } else {
            print("FAIL\t字节不一致\t\(file.fileName)")
            ok = false
        }
    }
    let manifestExpected = (recomputed.joined(separator: "\n") + "\n")
    let manifestPath = URL(fileURLWithPath: (dir as NSString).appendingPathComponent("SHA256SUMS.txt"))
    if let diskManifest = try? String(contentsOf: manifestPath, encoding: .utf8), diskManifest == manifestExpected {
        print("OK\tSHA256SUMS.txt 与生成器一致")
    } else {
        print("FAIL\tSHA256SUMS.txt 与生成器不一致")
        ok = false
    }
    return ok
}

// MARK: - 测量主流程

@MainActor private func runBench(_ o: Options) throws {
    let ttml = Data(SyntheticTTML.scaled(lines: o.scale, mode: o.mode).utf8)

    var load: Measure.LoadTiming?
    if o.measureLoad {
        load = try Measure.loadTiming(ttml: ttml, width: o.width, height: o.height)
    }
    var frames: [LyricsFrame] = []
    var stats: Measure.FrameStats?
    var cacheBytes = 0
    if o.measureFrames {
        let result = try Measure.frameTiming(ttml: ttml, seconds: o.seconds, width: o.width, height: o.height)
        frames = result.frames
        stats = result.stats
        cacheBytes = result.frames.last?.glyphCacheBytes ?? 0
    }

    // 人类可读表格（--json 时走 stderr，保证 stdout 只有 JSON 一行，供 CI 解析）
    let table = """
    == 测量: \(o.scale) 行 / mode=\(o.mode.rawValue) / 视口 \(Int(o.width))×\(Int(o.height)) / \(o.seconds)s @120fps ==
    """ + (load.map {
        String(format: "\n装载 (decode / install / 首帧 / 总计): %.1f / %.1f / %.1f / %.1f ms", $0.decodeMS, $0.installMS, $0.firstRenderMS, $0.totalMS)
    } ?? "") + (stats.map {
        String(format: "\n帧分布 (丢首帧, n=%d): p50 %.3f  p95 %.3f  p99 %.3f  max %.3f ms  | >8.33ms: %d  >16.67ms: %d  | cache %.0f KB", $0.count, $0.p50, $0.p95, $0.p99, $0.max, $0.over8ms, $0.over16ms, Double(cacheBytes) / 1024)
    } ?? "") + "\n"
    if o.json {
        FileHandle.standardError.write(Data(table.utf8))
    } else {
        FileHandle.standardOutput.write(Data(table.utf8))
    }

    // 机器可读 JSON（CI 阈值护栏用）
    if o.json {
        var dict: [String: Any] = [
            "tool": "MelismaKitBench",
            "scale": o.scale,
            "mode": o.mode.rawValue,
            "groups": frames.last?.groups.count ?? 0,
            "cacheBytes": cacheBytes,
        ]
        if let load {
            dict["loadMilliseconds"] = [
                "decodeMS": load.decodeMS,
                "installMS": load.installMS,
                "firstRenderMS": load.firstRenderMS,
                "totalMS": load.totalMS,
            ]
        }
        if let stats {
            dict["frames"] = [
                "count": stats.count,
                "p50": stats.p50,
                "p95": stats.p95,
                "p99": stats.p99,
                "max": stats.max,
                "over8ms": stats.over8ms,
                "over16ms": stats.over16ms,
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([10]))
    }
}

// MARK: - 入口

@MainActor private func main() -> Int32 {
    do {
        let o = parseArgs()
        switch o.action {
        case .help:
            print(helpText)
            return 0
        case .emitFixtures:
            try emitFixtures(o.fixturesDir)
            return 0
        case .verifyFixtures:
            return verifyFixtures(o.fixturesDir) ? 0 : 1
        case .bench:
            try runBench(o)
            return 0
        }
    } catch {
        FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
        return 1
    }
}

MainActor.assumeIsolated {
    exit(main())
}
