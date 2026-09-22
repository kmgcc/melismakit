import AppKit
import MelismaKit
import MelismaKitBenchCore
import QuartzCore
import Metal

// MARK: - Headless CARenderer (real CA renderer, honors CALayer.filters)

final class HeadlessRenderer {
    private let device: MTLDevice
    let pixelWidth: Int
    let pixelHeight: Int

    init(size: CGSize, scale: CGFloat) {
        pixelWidth = Int(size.width * scale)
        pixelHeight = Int(size.height * scale)
        device = MTLCreateSystemDefaultDevice()!
    }

    func capture(of layer: CALayer, size: CGSize, scale: CGFloat) -> CGImage {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: pixelWidth, height: pixelHeight, mipmapped: false
        )
        desc.usage = [.renderTarget, .shaderRead]
        let texture = device.makeTexture(descriptor: desc)!
        let renderer = CARenderer(mtlTexture: texture)
        renderer.layer = layer
        renderer.bounds = CGRect(origin: .zero, size: size)
        // Warm-up frames: CARenderer needs a few commit cycles to reflect the tree.
        for _ in 0..<4 {
            renderer.addUpdate(CGRect(origin: .zero, size: size))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
            renderer.render()
            renderer.endFrame()
        }
        let bytesPerRow = pixelWidth * 4
        var data = [UInt8](repeating: 0, count: bytesPerRow * pixelHeight)
        texture.getBytes(&data, bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, pixelWidth, pixelHeight), mipmapLevel: 0)
        let ctx = CGContext(data: &data, width: pixelWidth, height: pixelHeight,
                            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        return ctx.makeImage()!
    }
}

// MARK: - Pixel comparison

struct DiffResult {
    var differing0 = 0          // per-channel threshold 0
    var differing16 = 0         // per-channel threshold 16
    var total = 0
    var meanAbs: Double = 0
    var sumAbs: UInt64 = 0
    var bandEdge95: [Double] = []
}

func compare(_ a: CGImage, _ b: CGImage, bandHeight: Int) -> DiffResult {
    let w = min(a.width, b.width), h = min(a.height, b.height)
    let ac = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ac.draw(a, in: CGRect(x: 0, y: 0, width: w, height: h))
    let bc = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    bc.draw(b, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let ad = ac.data, let bd = bc.data else { return DiffResult() }
    let ab = ad.assumingMemoryBound(to: UInt8.self)
    let bb = bd.assumingMemoryBound(to: UInt8.self)
    let rowBytes = w * 4
    var result = DiffResult()
    result.total = w * h
    var bandCount = (h + bandHeight - 1) / bandHeight
    result.bandEdge95 = Array(repeating: 0, count: bandCount)
    var bandSamples = Array(repeating: 0, count: bandCount)
    for y in 0..<h {
        let band = min(bandCount - 1, y / bandHeight)
        for x in 0..<w {
            let o = y * rowBytes + x * 4
            let d0 = abs(Int(ab[o]) - Int(bb[o]))
            let d1 = abs(Int(ab[o+1]) - Int(bb[o+1]))
            let d2 = abs(Int(ab[o+2]) - Int(bb[o+2]))
            let d = max(d0, max(d1, d2))
            if d > 0 { result.differing0 += 1 }
            if d >= 16 { result.differing16 += 1 }
            result.sumAbs += UInt64(d)
            bandSamples[band] += 1
            // simple local-gradient proxy: max diff in 2px window along x
            if x + 1 < w {
                let n = y * rowBytes + (x + 1) * 4
                let ga = abs(Int(ab[o]) - Int(ab[n])) + abs(Int(ab[o+1]) - Int(ab[n+1])) + abs(Int(ab[o+2]) - Int(ab[n+2]))
                let gb = abs(Int(bb[o]) - Int(bb[n])) + abs(Int(bb[o+1]) - Int(bb[n+1])) + abs(Int(bb[o+2]) - Int(bb[n+2]))
                result.bandEdge95[band] = max(result.bandEdge95[band], Double(max(ga, gb)))
            }
        }
    }
    result.meanAbs = Double(result.sumAbs) / Double(result.total * 3)
    return result
}

func savePNG(_ image: CGImage, _ path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

// MARK: - Main

@MainActor func makeView(viewSize: CGSize) -> LyricsView {
    let view = LyricsView(frame: NSRect(origin: .zero, size: viewSize))
    let ttml = SyntheticTTML.scaled(lines: 14, mode: .word)
    try! view.load(ttml: Data(ttml.utf8), time: 0, playing: false)
    // Mirror the player's window-surface configuration so the blur ramp,
    // spring and render scale match the real app.
    view.configuration.profile = .currentPlayer
    view.configuration.surface = .window
    view.configuration.blur = true
    view.configuration.spring = true
    view.configuration.renderScale = 0.75
    view.configuration.wordFadeWidth = 0.7
    view.configuration.overscan = 260
    return view
}

@main
struct MelismaKitParity {
    static func main() {
        _ = NSApplication.shared
        let viewSize = CGSize(width: 600, height: 300)
        let scale: CGFloat = 2
        let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "settled"

        let view = makeView(viewSize: viewSize)
        let renderer = HeadlessRenderer(size: viewSize, scale: scale)
        let base = CACurrentMediaTime()

        if mode == "transition" {
            runTransition(view: view, renderer: renderer, viewSize: viewSize, scale: scale, base: base)
        } else {
            runSettled(view: view, renderer: renderer, viewSize: viewSize, scale: scale, base: base)
        }
    }

    @MainActor static func runSettled(view: LyricsView, renderer: HeadlessRenderer, viewSize: CGSize, scale: CGFloat, base: Double) {
        // Settle at a fixed media position with blurred neighbours around the focus.
        view.configuration.bakeSettledBlur = false
        for i in 0..<360 {
            _ = view.render(at: base + Double(i) * (1.0 / 60.0))
        }
        _ = view.render(at: base + 6.0)
        let dbg = view.lastFrame!.timeline
        print("timeline: focus=\(dbg.focus) playing=\(dbg.playing) highlighted=\(dbg.highlighted) groups=\(view.lastFrame!.groups.count)")
        let live = renderer.capture(of: view.layer!, size: viewSize, scale: scale)
        savePNG(live, "/tmp/parity_live.png")
        let frameLive = view.lastFrame!
        print("LIVE frame: focus-blur rows: " + frameLive.groups.map { String(format: "i%d b%.2f a%d", $0.index, $0.blur, $0.active ? 1 : 0) }.joined(separator: " "))

        // Same position, baked mode
        view.configuration.bakeSettledBlur = true
        _ = view.render(at: base + 6.0)
        _ = view.render(at: base + 6.0)
        _ = view.render(at: base + 6.0)
        let baked = renderer.capture(of: view.layer!, size: viewSize, scale: scale)
        savePNG(baked, "/tmp/parity_baked.png")

        let r = compare(live, baked, bandHeight: 20)
        print("SETTLED parity: differing@0=\(r.differing0)/\(r.total) (\(String(format: "%.3f", Double(r.differing0) / Double(r.total) * 100))%) differing@16=\(r.differing16) meanAbs=\(String(format: "%.2f", r.meanAbs))")
        print("bands(y20px): " + r.bandEdge95.enumerated().map { String(format: "%d:%.1f", $0.offset, $0.element) }.joined(separator: " "))
    }

    /// Step frames across the line-2 boundary (media 4.0s) in both modes and
    /// report per-frame baked-vs-live parity. Line 1 is baked at 2.7 and
    /// becomes active at 4.0 (baked→live switch); line 0 exits at 4.0 and is
    /// re-baked after its fall (~6.4s, live→baked switch). The view starts
    /// already settled (no seek re-animation) so only the focus transition is
    /// measured.
    @MainActor static func runTransition(view: LyricsView, renderer: HeadlessRenderer, viewSize: CGSize, scale: CGFloat, base: Double) {
        view.configuration.bakeSettledBlur = false
        // Settle at media 0 while paused.
        for i in 0..<300 {
            _ = view.render(at: base + Double(i) * (1.0 / 60.0))
        }
        // Resume playback at media 0.5s (line 1 active, everything settled).
        view.synchronize(time: 0.5, playing: true, seek: false, motion: .immediate, hostTime: base)
        let dt = 1.0 / 30.0
        let steps = 150 // 5.0s of playback: crosses 4.0 (enter) and the ~6.4s exit re-bake
        // Pre-warm the CARenderer capture pipeline so the first measured
        // captures are not stale (the baked pass lags ~1s at pass start).
        for k in 0..<40 {
            _ = view.render(at: base + Double(k) * dt)
            _ = renderer.capture(of: view.layer!, size: viewSize, scale: scale)
        }
        var liveFrames: [CGImage] = []
        var bakeFrames: [CGImage] = []
        var focusHistory: [Int] = []
        var bakeFocusHistory: [Int] = []
        for k in 0..<steps {
            let t = base + Double(k + 40) * dt
            _ = view.render(at: t)
            liveFrames.append(renderer.capture(of: view.layer!, size: viewSize, scale: scale))
            focusHistory.append(view.lastFrame!.timeline.focus)
        }
        print("transition focus history: " + focusHistory.enumerated().map { "\($0.offset):\($0.element)" }.joined(separator: " "))
        // Baked pass: same time sequence, starting from a fresh settle.
        view.configuration.bakeSettledBlur = true
        for i in 0..<300 {
            _ = view.render(at: base + Double(i) * (1.0 / 60.0))
        }
        view.synchronize(time: 0.5, playing: true, seek: false, motion: .immediate, hostTime: base)
        for k in 0..<40 {
            _ = view.render(at: base + Double(k) * dt)
            _ = renderer.capture(of: view.layer!, size: viewSize, scale: scale)
        }
        for k in 0..<steps {
            let t = base + Double(k + 40) * dt
            _ = view.render(at: t)
            bakeFrames.append(renderer.capture(of: view.layer!, size: viewSize, scale: scale))
            bakeFocusHistory.append(view.lastFrame!.timeline.focus)
        }
        print("bake focus history: " + bakeFocusHistory.enumerated().map { "\($0.offset):\($0.element)" }.joined(separator: " "))
        print("TRANSITION per-frame parity (frame: differing@16, differing@0, meanAbs):")
        var worst = (frame: -1, d16: 0, d0: 0, mean: 0.0)
        for k in 0..<steps {
            let r = compare(liveFrames[k], bakeFrames[k], bandHeight: 20)
            print(String(format: "%3d: %6d %6d %.2f", k, r.differing16, r.differing0, r.meanAbs))
            if r.differing16 > worst.d16 { worst = (k, r.differing16, r.differing0, r.meanAbs) }
        }
        print("WORST frame: \(worst)")
        for saveK in [0, 10, 26, 46] where saveK < steps {
            savePNG(liveFrames[saveK], "/tmp/parity_t\(saveK)_live.png")
            savePNG(bakeFrames[saveK], "/tmp/parity_t\(saveK)_baked.png")
        }
        if worst.frame >= 0 {
            savePNG(liveFrames[worst.frame], "/tmp/parity_t_live.png")
            savePNG(bakeFrames[worst.frame], "/tmp/parity_t_baked.png")
        }
    }
}
