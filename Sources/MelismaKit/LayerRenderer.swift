// Portions of this file are derived from AMLL (https://github.com/steve-xmh/applemusic-like-lyrics),
// licensed AGPL-3.0-only, and modified for native AppKit. See Documentation/PROVENANCE.md.

import AppKit
import CoreText
import QuartzCore
import CoreImage

extension LyricsColor {
    var cgColor: CGColor {
        if displayP3 { return NSColor(displayP3Red:red,green:green,blue:blue,alpha:alpha).cgColor }
        return NSColor(srgbRed:red,green:green,blue:blue,alpha:alpha).cgColor
    }
}

/// Linear interpolation in the same color space supplied by the host.  The
/// interlude marker uses this instead of opacity to express its per-dot walk,
/// keeping inactive and active dots on the exact main-lyric palette.
func interpolateLyricsColor(_ from: LyricsColor, _ to: LyricsColor, _ amount: Double) -> LyricsColor {
    let t = Curves.clamp(amount)
    return LyricsColor(
        from.red + (to.red-from.red)*t,
        from.green + (to.green-from.green)*t,
        from.blue + (to.blue-from.blue)*t,
        alpha: from.alpha + (to.alpha-from.alpha)*t,
        displayP3: from.displayP3 || to.displayP3
    )
}

/// Bounded, shared glyph bitmap cache. Text is shaped only on layout/cache misses.
final class GlyphCache {
    struct Entry { let image: CGImage; let size: CGSize; let padding: Double; let bytes: Int; var stamp: UInt64 }
    private var entries: [String:Entry] = [:]
    private var stamp: UInt64 = 0
    private(set) var bytes = 0
    private(set) var misses = 0
    var budget = 64*1024*1024
    func glyph(_ placement: GlyphPlacement, scale: Double) -> Entry? {
        let font = placement.font, size = CTFontGetSize(font)
        let key = "\(CTFontCopyPostScriptName(font))|\(size)|\(scale)|\(placement.text)"
        stamp &+= 1
        if var entry = entries[key] { entry.stamp = stamp; entries[key] = entry; return entry }
        let pad = max(3,size*0.45), height = max(size*1.2,CTFontGetAscent(font)+CTFontGetDescent(font)+CTFontGetLeading(font))
        let logical = CGSize(width:ceil(placement.width+pad*2),height:ceil(height+pad*2))
        let w = max(1,Int(ceil(logical.width*scale))), h = max(1,Int(ceil(logical.height*scale)))
        guard w<32768, h<32768, let context = CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x:scale,y:scale)
        context.setFillColor(NSColor.white.cgColor)
        context.textPosition = CGPoint(x:pad,y:logical.height-pad-CTFontGetAscent(font))
        CTLineDraw(TextLayoutEngine.shape(placement.text,font:font),context)
        guard let image = context.makeImage() else { return nil }
        let entry = Entry(image:image,size:logical,padding:pad,bytes:w*h*4,stamp:stamp)
        while bytes+entry.bytes>budget, let oldest = entries.min(by:{$0.value.stamp<$1.value.stamp}) {
            bytes -= oldest.value.bytes; entries.removeValue(forKey:oldest.key)
        }
        if entry.bytes<=budget { entries[key] = entry; bytes += entry.bytes }
        misses += 1; return entry
    }
    func removeAll() { entries.removeAll(); bytes = 0 }
}

/// Premultiplied ink composition, independent of the surface backdrop.
func compositeInk(base: LyricsColor, highlight: LyricsColor, baseAlpha: Double, highlightAlpha: Double, mode: LyricsBlendMode) -> LyricsColor {
    let da = Curves.clamp(baseAlpha*base.alpha), sa = Curves.clamp(highlightAlpha*highlight.alpha)
    let alpha = mode == .plusLighter ? min(1,sa+da) : sa+da*(1-sa)
    func channel(_ d: Double, _ s: Double) -> Double {
        guard alpha > 0 else { return 0 }
        if mode == .plusLighter { return min(alpha,s*sa+d*da)/alpha }
        if mode == .plusDarker { return (max(0,s+d-1)*sa*da+s*sa*(1-da)+d*da*(1-sa))/alpha }
        return (s*sa+d*da*(1-sa))/alpha
    }
    return LyricsColor(channel(base.red,highlight.red),channel(base.green,highlight.green),channel(base.blue,highlight.blue),alpha:alpha,displayP3:base.displayP3 || highlight.displayP3)
}

final class GlyphLayers {
    let root = CALayer(), glow = CALayer()
    private(set) var baseOpacity = 0.0, highlightOpacity = 0.0
    private var inkColors: [LyricsColor] = []
    private var inkKey: InkKey?
    private struct InkKey: Equatable { var base: LyricsColor; var high: LyricsColor; var baseAlpha: Double; var highAlpha: Double; var mode: LyricsBlendMode }
    let gradient = CAGradientLayer()
    let glowBlur = CIFilter(name:"CIGaussianBlur")
    let placement: GlyphPlacement
    let padding: Double
    private var appliedGlowRadius = -1.0
    private var appliedGlowColor: LyricsColor?
    private var glowFiltersInstalled = false
    private var lastPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
    private var lastScale = Double.nan
    private var lastGradientStart = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
    private var lastGradientEnd = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
    private var lastGlowOpacity = -1.0
    private var blendKey = ""
    func updateBlend(active: Bool, config: LyricsConfiguration) {
        let base = config.channelBlend.isExplicit ? (active ? config.channelBlend.current : config.channelBlend.inactive) : nil
        let highlight = config.channelBlend.isExplicit ? config.channelBlend.highlight : nil
        let key = "\(base?.rawValue ?? "normal")/\(highlight?.rawValue ?? "normal")"
        guard key != blendKey else { return }; blendKey = key
        root.compositingFilter = blendFilter(base)
    }
    var x: SpringTrack, y: SpringTrack
    init?(_ placement: GlyphPlacement, cache: GlyphCache, scale: Double, previous: CGPoint?, now: Double) {
        guard let bitmap = cache.glyph(placement,scale:scale) else { return nil }
        self.placement = placement; padding = bitmap.padding
        x = SpringTrack(Double(previous?.x ?? placement.origin.x)); y = SpringTrack(Double(previous?.y ?? placement.origin.y))
        x.retarget(placement.origin.x,at:now); y.retarget(placement.origin.y,at:now)
        root.bounds = CGRect(origin:.zero,size:bitmap.size); root.anchorPoint = CGPoint(x:0.5,y:0.5)
        glow.frame = root.bounds; root.addSublayer(glow)
        gradient.frame = root.bounds; root.addSublayer(gradient)
        let mask = CALayer(); mask.frame = root.bounds; mask.contents = bitmap.image; mask.contentsScale = scale
        gradient.mask = mask
        // Keep the glyph bitmap as the source for the halo. Applying a second
        // mask after the blur would clip the halo back to the glyph silhouette;
        // the bitmap's padding provides the bounded expansion area instead.
        glow.contents = bitmap.image; glow.contentsScale = scale; glow.contentsGravity = .resize
        // Do not install the Core Image filter graph until the glyph actually
        // emits a visible glow. Most visible glyphs are inactive on most
        // frames; keeping a Gaussian blur, monochrome filter and additive
        // compositor attached to every one of them needlessly expands the
        // high-DPI Core Animation render passes.
        glow.filters = nil
        glow.compositingFilter = nil
        glow.backgroundColor = nil
        appliedGlowColor = nil
        gradient.startPoint = CGPoint(x:0,y:0.5); gradient.endPoint = CGPoint(x:1,y:0.5)
        gradient.colors = [NSColor.white.cgColor,NSColor.white.cgColor,NSColor.clear.cgColor,NSColor.clear.cgColor]
    }
    func update(now: Double, media: Double, logicalX: Double, cursor: Double, fade: Double, darkAlpha: Double, brightAlpha: Double, emphasis: EmphasisEnvelope?, fontSize: Double, config: LyricsConfiguration, float: Double, background: Bool = false, subline: Bool = false, lifetime: Double = 1, floatLifetime: Double? = nil, emphasisExitMedia: Double? = nil, emphasisExitElapsed: Double? = nil, baseVisible: Bool = true, highlightVisible: Bool = true, glowVisible: Bool = true, lineTimed: Bool = false, discreteOpacity: Double? = nil, animateGradient: Bool = true) {
        x.resolve(now); y.resolve(now)
        var e = EmphasisSample()
        if config.emphasis, let emphasis, let character = placement.characterIndex {
            e = emphasis.sample(media,character:character,fontSize:fontSize,radiusScale:config.glowRadiusScale,exitMedia:emphasisExitMedia,exitElapsed:emphasisExitElapsed)
        }
        e.scale = 1+(e.scale-1)*lifetime
        e.x *= lifetime; e.y *= lifetime; e.glowOpacity *= lifetime
        let w = root.bounds.width
        let motionLifetime = floatLifetime ?? lifetime
        // Float is an independent element animation. During an exit its
        // lifetime must not collapse together with the highlight fade, or a
        // line will snap down before the authored exit motion has finished.
        let position = CGPoint(x:x.value(now)-padding+w/2+e.x,y:y.value(now)-padding+root.bounds.height/2+e.y+e.floatY*motionLifetime+float*motionLifetime)
        if position != lastPosition {
            root.position = position
            lastPosition = position
        }
        if !lastScale.isFinite || abs(lastScale-e.scale) > 0.0001 {
            root.transform = CATransform3DMakeScale(e.scale,e.scale,1)
            lastScale = e.scale
        }
        let baseColor: LyricsColor, highColor: LyricsColor
        if let discreteOpacity, !subline, !lineTimed {
            let opacity = min(1, max(0, discreteOpacity.isFinite ? discreteOpacity : 0))
            let color = background ? config.palette.backgroundKaraoke : config.palette.mainActive
            baseColor = color
            highColor = color

            // Discrete highlighting is a single opacity value per word. Keep
            // it in whichever ink channel is currently visible so the same
            // renderer works for both the window and fullscreen surfaces.
            if baseVisible {
                baseOpacity = opacity
                highlightOpacity = 0
            } else if highlightVisible {
                baseOpacity = 0
                highlightOpacity = opacity
            } else {
                baseOpacity = 0
                highlightOpacity = 0
            }
        } else if config.usesOpaqueCompositing {
            if subline {
                // Cover-blur keeps a dedicated line-timing sub color.  The
                // artistic fullscreen CSS intentionally uses the regular
                // sub-color for this layer, so only the cover profile opts in.
                baseColor = lineTimed && config.usesCoverBlurCompositing
                    ? config.palette.lineTimingSubInactive
                    : config.palette.translation
            } else if background {
                baseColor = config.palette.backgroundInactive
            } else {
                baseColor = lineTimed ? config.palette.lineTimingInactive : config.palette.mainInactive
            }
            highColor = background ? config.palette.backgroundKaraoke : config.palette.mainActive
            baseOpacity = baseVisible ? (subline ? 1 : background ? config.palette.backgroundBaseOpacity : 1) : 0
            highlightOpacity = highlightVisible && !subline ? lifetime*(background ? config.palette.backgroundKaraokeOpacity : 1) : 0
        } else {
            if lineTimed && !subline {
                // A line-level LRC span still needs a visible left-to-right
                // sweep. Keep its inactive ink opaque and use the same mask
                // cursor as karaoke timing instead of dimming the whole row
                // to a flat, already-bright colour.
                baseColor = config.palette.mainInactive
                highColor = config.palette.mainActive
                baseOpacity = baseVisible ? 1 : 0
                highlightOpacity = highlightVisible ? lifetime : 0
            } else {
                // Dynamic rows retain the composited alpha model used by the
                // native window surface. A line-timed translation has no
                // independent mask, so it remains a single translation tone.
                baseColor = config.palette.mainActive
                highColor = config.palette.mainActive
                let intrinsicBase = lineTimed ? 1 : darkAlpha
                baseOpacity = baseVisible ? intrinsicBase : 0
                let highlightBase = lineTimed ? 1 : darkAlpha
                highlightOpacity = highlightVisible
                    ? max(0,(brightAlpha-highlightBase)/max(0.0001,1-highlightBase))
                    : 0
            }
        }
        // Compose ink before applying the glyph silhouette. Highlight never
        // samples the window backdrop, and glyph edges are masked only once.
        let mode = config.channelBlend.highlight ?? .normal
        let key = InkKey(base:baseColor,high:highColor,baseAlpha:baseOpacity,highAlpha:highlightOpacity,mode:mode)
        // The smooth highlight solver approaches its target asymptotically.
        // Once the color delta is below half a 1/2048 step, resubmitting the
        // same nine-color gradient only creates another Core Animation layer
        // commit; it cannot produce a visible pixel change at the backing
        // scales used by the player. Keep the exact value when a real change
        // crosses the threshold so the displayed effect and its timing remain
        // continuous without introducing a frame-rate cap.
        let inkChanged: Bool = {
            guard let previous = inkKey else { return true }
            return previous.base != key.base
                || previous.high != key.high
                || previous.mode != key.mode
                || abs(previous.baseAlpha - key.baseAlpha) >= 0.00048828125
                || abs(previous.highAlpha - key.highAlpha) >= 0.00048828125
        }()
        if inkChanged {
            inkKey = key
            let colors = (0...8).map { i in
                compositeInk(base:baseColor,highlight:highColor,baseAlpha:baseOpacity,highlightAlpha:highlightOpacity*Double(8-i)/8,mode:mode)
            }
            if colors != inkColors { inkColors = colors; gradient.colors = colors.map(\.cgColor) }
        }
        // Inactive rows keep their existing mask state. Rewriting gradient
        // endpoints on every display tick makes Core Animation re-encode the
        // whole gradient layer tree, which is disproportionately expensive on
        // high-resolution displays.
        if animateGradient {
            let boundary = min(root.bounds.width+fade,max(-fade,cursor-logicalX-placement.origin.x+padding))
            let gradientStart = CGPoint(x:(boundary-fade/2)/max(1,w),y:0.5)
            let gradientEnd = CGPoint(x:(boundary+fade/2)/max(1,w),y:0.5)
            if gradientStart != lastGradientStart {
                gradient.startPoint = gradientStart
                lastGradientStart = gradientStart
            }
            if gradientEnd != lastGradientEnd {
                gradient.endPoint = gradientEnd
                lastGradientEnd = gradientEnd
            }
        }
        let wantsGlow = config.glow
            && !config.coverBlurSuppressEmphasisGlow
            && glowVisible
            && e.glowOpacity > 0.0001
        let glowOpacity = wantsGlow ? e.glowOpacity : 0
        if abs(lastGlowOpacity-glowOpacity) > 0.0001 {
            glow.opacity = Float(glowOpacity)
            lastGlowOpacity = glowOpacity
        }
        // The image alpha is the glow source. Its transparent padding bounds
        // the blur expansion while keeping the glyph silhouette as the only
        // painted source; the tile itself is never filled as a rectangle.
        if wantsGlow {
            if !glowFiltersInstalled {
                glowFiltersInstalled = true
                appliedGlowRadius = -1
                appliedGlowColor = nil
                // Emphasis is a light contribution, not an opaque second ink
                // pass. Addition compositing keeps the halo additive over the
                // lyric/backdrop and matches the intended plus-lighter glow.
                glow.compositingFilter = CIFilter(name:"CIAdditionCompositing")
            }
            let glowRadius = e.glowRadius
            let glowColorChanged = appliedGlowColor != config.palette.emphasisGlow
            if glowColorChanged {
                appliedGlowColor = config.palette.emphasisGlow
                if let color = CIFilter(name:"CIColorMonochrome") {
                    color.setValue(CIColor(cgColor:config.palette.emphasisGlow.cgColor),forKey:kCIInputColorKey)
                    color.setValue(1,forKey:kCIInputIntensityKey)
                    glowBlur?.setValue(appliedGlowRadius >= 0 ? appliedGlowRadius : glowRadius,forKey:kCIInputRadiusKey)
                    glow.filters = [color,glowBlur].compactMap { $0?.copy() as? CIFilter }
                }
            }
            if abs(appliedGlowRadius-glowRadius)>0.001 {
                appliedGlowRadius = glowRadius
                glowBlur?.setValue(appliedGlowRadius,forKey:kCIInputRadiusKey)
                if let color = CIFilter(name:"CIColorMonochrome") {
                    color.setValue(CIColor(cgColor:config.palette.emphasisGlow.cgColor),forKey:kCIInputColorKey)
                    color.setValue(1,forKey:kCIInputIntensityKey)
                    glow.filters = [color,glowBlur].compactMap { $0?.copy() as? CIFilter }
                }
            }
        } else if glowFiltersInstalled {
            glowFiltersInstalled = false
            glow.filters = nil
            glow.compositingFilter = nil
            appliedGlowRadius = -1
            appliedGlowColor = nil
        }
    }
    func settled(_ time: Double) -> Bool { x.settled(time) && y.settled(time) }
}

final class WordLayers {
    let root = CALayer()
    let placement: WordPlacement
    let glyphs: [GlyphLayers]
    var x: SpringTrack, y: SpringTrack
    let logicalX: Double
    private var lastRootPosition = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
    init(_ placement: WordPlacement, logicalX: Double, cache: GlyphCache, scale: Double, previous: WordLayers?, now: Double) {
        self.placement = placement; self.logicalX = logicalX
        x = SpringTrack(previous.map { $0.x.value(now) } ?? placement.rect.minX)
        y = SpringTrack(previous.map { $0.y.value(now) } ?? placement.rect.minY)
        x.retarget(placement.rect.minX,at:now); y.retarget(placement.rect.minY,at:now)
        glyphs = placement.pieces.enumerated().compactMap { i,piece in
            let old = previous.flatMap { i<$0.glyphs.count ? $0.glyphs[i] : nil }
            return GlyphLayers(piece,cache:cache,scale:scale,previous:old.map { CGPoint(x:$0.x.value(now),y:$0.y.value(now)) },now:now)
        }
        root.anchorPoint = .zero
        for glyph in glyphs { root.addSublayer(glyph.root) }
    }
    func update(now: Double, media: Double, cursor: Double, fade: Double, dark: Double, bright: Double, config: LyricsConfiguration, floatTime: Double, lineFallStartMedia: Double? = nil, lineFallMultiplier: Double? = nil, background: Bool, lifetime: Double, floatLifetime: Double? = nil, emphasisExitMedia: Double? = nil, emphasisExitElapsed: Double? = nil, baseVisible: Bool = true, highlightVisible: Bool = true, glowVisible: Bool = true, lineTimed: Bool = false, discreteOpacity: Double? = nil, animateGradient: Bool = true) {
        x.resolve(now); y.resolve(now)
        let rootPosition = CGPoint(x:x.value(now),y:y.value(now))
        if rootPosition != lastRootPosition {
            root.position = rootPosition
            lastRootPosition = rootPosition
        }
        let duration = max(1,placement.atom.word.range.duration)
        let baseRise = -Curves.easeOut.value(at:Curves.clamp((floatTime-placement.atom.word.range.start)/duration))*placement.fontSize*0.05*(background ? 2 : 1)
        let baseRiseAtFall = lineFallStartMedia.map {
            -Curves.easeOut.value(at:Curves.clamp(($0-placement.atom.word.range.start)/duration))*placement.fontSize*0.05*(background ? 2 : 1)
        }
        let float = lineFallMultiplier.flatMap { multiplier in
            baseRiseAtFall.map { $0 * multiplier }
        } ?? baseRise
        for glyph in glyphs {
            glyph.update(now:now,media:media,logicalX:logicalX,cursor:cursor,fade:fade,darkAlpha:dark,brightAlpha:bright,emphasis:placement.atom.emphasis,fontSize:placement.fontSize,config:config,float:float,background:background,lifetime:lifetime,floatLifetime:floatLifetime,emphasisExitMedia:emphasisExitMedia,emphasisExitElapsed:emphasisExitElapsed,baseVisible:baseVisible,highlightVisible:highlightVisible,glowVisible:glowVisible,lineTimed:lineTimed,discreteOpacity:discreteOpacity,animateGradient:animateGradient)
        }
    }
    func settled(_ time: Double) -> Bool { x.settled(time) && y.settled(time) && glyphs.allSatisfy { $0.settled(time) } }
}

final class LineLayers {
    let root = CALayer()
    private(set) var words: [WordLayers] = []
    private(set) var sublines: [GlyphLayers] = []
    let layout: LineTextLayout
    let mask: MaskPath
    let fade: Double
    private var highlight = Tween(0)
    private var wasActive = false
    private var brightAlpha = 1.0, darkAlpha = 0.4
    private var previousTime: Double?
    private var cursor = HighlightSmoother()
    private(set) var renderedCursor = 0.0
    private var emphasisExitMedia: Double?
    private var emphasisExitHost: Double?
    private var lastRootAnchor: CGPoint?
    private var lastRootPosition: CGPoint?
    private var lastRootScale: Double?
    private var lastRootOpacity: Float?
    init(_ layout: LineTextLayout, cache: GlyphCache, scale: Double, config: LyricsConfiguration, previous: LineLayers?, now: Double, buildContent: Bool = true, preserveWordMotion: Bool = true) {
        self.layout = layout; fade = max(0.01,(layout.words.first?.fadeHeight ?? layout.fontSize*1.2)*config.wordFadeWidth)
        mask = MaskPath(layout.words,fadeWidth:fade)
        root.anchorPoint = .zero; root.bounds = CGRect(x:0,y:0,width:layout.width,height:layout.height)
        if let previous {
            brightAlpha = previous.brightAlpha; darkAlpha = previous.darkAlpha
            highlight = previous.highlight; wasActive = previous.wasActive
            previousTime = previous.previousTime; cursor = previous.cursor
            emphasisExitMedia = previous.emphasisExitMedia
            emphasisExitHost = previous.emphasisExitHost
        }
        if buildContent {
            // A width/font reflow is a layout correction, not a lyric event.
            // Keep the line-level state (highlight, alpha and cursor) but let
            // the newly measured glyphs start at their final positions instead
            // of animating every word/character from its old wrapping.
            build(cache:cache,scale:scale,config:config,previous:preserveWordMotion ? previous : nil,now:now)
        }
    }
    func ensureContent(cache: GlyphCache, scale: Double, config: LyricsConfiguration, now: Double) {
        if words.isEmpty && !layout.words.isEmpty { build(cache:cache,scale:scale,config:config,previous:nil,now:now) }
    }
    func discardContent() {
        words.forEach { $0.root.removeFromSuperlayer() }; sublines.forEach { $0.root.removeFromSuperlayer() }
        words.removeAll(); sublines.removeAll()
    }
    func setPresentation(anchor: CGPoint, position: CGPoint, scale: Double) {
        if lastRootAnchor != anchor {
            root.anchorPoint = anchor
            lastRootAnchor = anchor
        }
        if lastRootPosition != position {
            root.position = position
            lastRootPosition = position
        }
        if lastRootScale.map({ abs($0-scale) > 0.0001 }) ?? true {
            root.transform = CATransform3DMakeScale(scale,scale,1)
            lastRootScale = scale
        }
    }
    func setOpacity(_ opacity: Float) {
        if lastRootOpacity != opacity {
            root.opacity = opacity
            lastRootOpacity = opacity
        }
    }
    private func build(cache: GlyphCache, scale: Double, config: LyricsConfiguration, previous: LineLayers?, now: Double) {
        var logical = 0.0
        words = layout.words.map { word in
            defer { logical += word.width }
            return WordLayers(word,logicalX:logical,cache:cache,scale:scale,previous:previous?.words.first { $0.placement.atom.word.id == word.atom.word.id },now:now)
        }
        sublines = layout.sublines.compactMap { GlyphLayers($0,cache:cache,scale:scale,previous:nil,now:now) }
        for word in words { root.addSublayer(word.root) }
        for subline in sublines { root.addSublayer(subline.root) }
    }
    func update(now: Double, media: Double, floatTime: Double, active: Bool, alpha: Double, background: Bool, config: LyricsConfiguration, playing: Bool = true, seek: Bool = false, highlightHold: Bool = false, preserveHighlight: Bool = false) {
        // `preserveHighlight` is the completed member of a parallel
        // foreground span.  It remains fully bright until the whole span is
        // gone; it is deliberately separate from `active` so a normal line
        // transition still gets the authored enter/exit fade.
        let keepHighlight = active || preserveHighlight
        if seek {
            highlight.snap(keepHighlight ? 1 : 0)
            wasActive = keepHighlight
            emphasisExitMedia = nil; emphasisExitHost = nil
            brightAlpha = keepHighlight ? 1 : 0.2+0.2*alpha
            darkAlpha = 0.2+0.2*alpha
            cursor.reset(mask.position(at:media))
        } else if keepHighlight != wasActive {
            if keepHighlight {
                emphasisExitMedia = nil; emphasisExitHost = nil
            } else {
                emphasisExitMedia = media; emphasisExitHost = now
            }
            highlight.set(keepHighlight ? 1 : 0,at:now,duration:keepHighlight ? 0.2 : config.motion.exitFade)
            if keepHighlight && config.lineTimingOnly { highlight.start += 0.05 }
            wasActive = keepHighlight
        }
        let lifetime = highlight.value(now)
        let visualActive = keepHighlight || highlightHold
        let highlightLifetime = preserveHighlight ? 1 : lifetime
        // Only the active row and its short exit transition need a moving
        // karaoke mask. Future/settled rows can leave their gradient endpoints
        // untouched until they re-enter this state.
        let animateGradient = visualActive || highlightLifetime > 0.001
        let smooth = layout.isDynamic && !config.lineTimingOnly && config.highlightMode == .smooth
        // Discrete mode is a presentation choice, not a statement that the
        // source must contain independent word spans.  A line-timed document
        // still has one real timed atom; treating that atom as a single
        // discrete word removes the left-to-right mask instead of silently
        // falling back to smooth highlighting.
        let discrete = !config.lineTimingOnly && config.highlightMode == .discrete
        let renderLayer = config.effectiveRenderLayer
        let highlightOnly = renderLayer == .highlight
        let baseOnly = renderLayer == .base
        let exitElapsed = emphasisExitHost.map { max(0,now-$0) }
        let floatLifetime: Double? = exitElapsed == nil ? nil : 1
        let lineEnd = layout.words.map { $0.atom.word.range.end }
            .filter { $0.isFinite }
            .max()
        let lineFallStartMedia = lyricLineFallStartMedia(
            lineEnd: lineEnd ?? .infinity,
            exitMedia: emphasisExitMedia
        )
        let lineFallMultiplier = lyricLineFallMultiplier(
            time: media,
            lineEnd: lineEnd ?? .infinity,
            exitMedia: emphasisExitMedia,
            exitElapsed: exitElapsed
        )
        // A host can render a cover-blur base and highlight surface separately.
        // Keep the exit channel alive for the same half-second line fade that
        // the reference behavior uses, so the highlight surface does not pop
        // out when a line leaves the hot set.
        let hasHighlightLifetime = visualActive || highlightLifetime > 0.001
        let hideActiveMain = !background && config.coverBlurHideActiveMainLine && active
        let baseVisible = !highlightOnly && !hideActiveMain
        let highlightVisible = !baseOnly && (!highlightOnly || hasHighlightLifetime) && !hideActiveMain
        let glowVisible = renderLayer != .base && !config.coverBlurSuppressEmphasisGlow
        let delta = max(0,now-(previousTime ?? now)); previousTime = now
        let targetDark = 0.2+0.2*alpha, targetBright = active || preserveHighlight ? 1 : targetDark+(1-targetDark)*highlightLifetime
        brightAlpha = active || preserveHighlight ? brightAlpha+(targetBright-brightAlpha)*(1-exp(-50*delta)) : targetBright
        darkAlpha += (targetDark-darkAlpha)*(1-exp(-(targetDark>darkAlpha ? 50 : 7)*delta))
        let bright = smooth ? (active || preserveHighlight ? brightAlpha : darkAlpha+(1-darkAlpha)*highlightLifetime) : ((background ? 0.4 : 0.28)+(background ? 0.6 : 0.72)*highlightLifetime)
        let dark = smooth ? darkAlpha : bright
        let target = playing && active ? mask.anticipatedPosition(at:media,amount:config.motion.highlightAnticipation) : mask.position(at:media)
        let maskCursor = smooth
            ? cursor.sample(target:target,now:now,playing:playing && visualActive,reset:seek,fadeWidth:fade)
            : mask.position(at:media)
        renderedCursor = maskCursor
        for word in words {
            var wordDark = dark, wordBright = bright, wordLifetime = highlightLifetime
            var discreteOpacity: Double?
            if discrete {
                let range = word.placement.atom.word.range
                let duration = max(0.3,min(2,range.duration))
                // A line-timed source has one atom for the whole line.  There
                // is no word boundary to sweep through, so discrete mode
                // must switch that atom as a unit instead of turning the
                // entire line into a slow continuous opacity ramp.
                let progress = layout.isDynamic
                    ? Curves.sampled((media-range.start)/duration,count:18) { log1p($0*2.2)/log1p(2.2) }
                    : (keepHighlight ? 1 : 0)
                // An opaque fullscreen surface still needs an inactive ink
                // baseline.  Zero here makes every non-current word fully
                // transparent, which was why some songs appeared to have no
                // inactive lyrics at all when discrete mode was enabled.
                let inactive = background ? 0.4 : 0.28
                let target: Double
                if keepHighlight {
                    target = inactive + (1 - inactive) * (preserveHighlight ? 1 : progress)
                } else if highlightLifetime > 0.001 {
                    // Let an exiting line fade from its current bright state
                    // instead of snapping every word back to inactive.
                    target = 1
                } else {
                    target = inactive
                }
                discreteOpacity = inactive + (target - inactive) * highlightLifetime
                wordDark = discreteOpacity ?? inactive
                wordBright = wordDark
            }
            // Discrete mode is an opacity transition per word. The continuous
            // line cursor must not remain active in fullscreen, otherwise the
            // opaque base/highlight channels still reveal a left-to-right
            // sweep even though the setting says one word at a time.
            let wordCursor = discrete
                ? word.placement.rect.maxX + fade + 1
                : maskCursor
            let lineTimed = !layout.isDynamic && !config.lineTimingOnly && !discrete
            word.update(now:now,media:media,cursor:wordCursor,fade:fade,dark:wordDark,bright:wordBright,config:config,floatTime:config.lineTimingOnly ? -1e9 : floatTime,lineFallStartMedia:lineFallStartMedia,lineFallMultiplier:lineFallMultiplier,background:background,lifetime:wordLifetime,floatLifetime:floatLifetime,emphasisExitMedia:emphasisExitMedia,emphasisExitElapsed:exitElapsed,baseVisible:baseVisible,highlightVisible:highlightVisible,glowVisible:glowVisible,lineTimed:lineTimed,discreteOpacity:discreteOpacity,animateGradient:animateGradient)
            for glyph in word.glyphs { glyph.updateBlend(active:keepHighlight,config:config) }
        }
        for subline in sublines {
            subline.update(now:now,media:media,logicalX:0,cursor:1e9,fade:1,darkAlpha:0.3,brightAlpha:0.3,emphasis:nil,fontSize:layout.fontSize,config:config,float:0,background:background,subline:true,lifetime:highlightLifetime,baseVisible:baseVisible,highlightVisible:highlightVisible,glowVisible:false,lineTimed:!layout.isDynamic && !config.lineTimingOnly && !discrete,animateGradient:false)
            subline.updateBlend(active:keepHighlight,config:config)
        }
    }
    func settled(_ time: Double) -> Bool { highlight.settled(time) && words.allSatisfy { $0.settled(time) } }
}

private func blendFilter(_ mode: LyricsBlendMode?) -> CIFilter? {
    switch mode {
    case .plusLighter: return CIFilter(name:"CIAdditionCompositing")
    case .plusDarker: return CIFilter(name:"CILinearBurnBlendMode")
    default: return nil
    }
}

final class GroupLayers {
    let root = CALayer(), hover = CALayer(), backgroundWrapper = CALayer()
    var main: LineLayers
    var background: LineLayers?
    var layout: GroupTextLayout
    var y: SpringTrack
    var scale = SpringTrack(0.97,.scale)
    var reveal = Tween(0)
    /// Absolute host time through which the current entry delay is owned by
    /// the entry animation. It is not recomputed from moving lyric targets.
    var entryDelayUntil = 0.0
    var cascadeStart = 0.0
    var opacity = Tween(1), blur = Tween(0)
    var alpha = 0.0
    var active = false
    var exitTime: Double?
    var exitMedia = 0.0
    var lastMedia = 0.0
    /// Set for an existing group after width/font reflow. LyricsView keeps the
    /// resize spring until this track settles instead of switching back to
    /// the more lively focus spring on the very next display tick.
    var isReflowing = false
    /// First target produced for the current reflow. A lyric event can change
    /// the stack target while a resize is still settling; that event must use
    /// the normal playback spring instead of inheriting the resize track.
    var reflowTarget: Double?
    var isHovered = false
    var isVisible = true
    let index: Int
    var blurFilter: CIFilter?
    var appliedBlur = 0.0
    private var compositorKey = ""
    private var lastRootPosition: CGPoint?
    private var lastRootOpacity: Float?
    private var lastRootBounds: CGRect?
    private var lastRootHidden: Bool?
    private var lastHoverFrame: CGRect?
    private var lastHoverHidden: Bool?
    private var lastBackgroundPosition: CGPoint?
    private var lastBackgroundOpacity: Float?
    private var rasterizationEnabled = false
    private var lastRasterizationScale = CGFloat.nan
    private let lighterCompositor = CIFilter(name:"CIAdditionCompositing")
    private let darkerCompositor = CIFilter(name:"CILinearBurnBlendMode")
    init(index: Int, layout: GroupTextLayout, initialY: Double, cache: GlyphCache, scale: Double, config: LyricsConfiguration, now: Double) {
        self.index = index; self.layout = layout; y = SpringTrack(initialY,.position)
        main = LineLayers(layout.main,cache:cache,scale:scale,config:config,previous:nil,now:now,buildContent:false)
        background = layout.background.map { LineLayers($0,cache:cache,scale:scale,config:config,previous:nil,now:now,buildContent:false) }
        root.anchorPoint = .zero; hover.cornerRadius = 12; hover.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor; hover.isHidden = true
        root.addSublayer(hover); root.addSublayer(main.root); root.addSublayer(backgroundWrapper)
        if let background { backgroundWrapper.addSublayer(background.root) }
        backgroundWrapper.anchorPoint = .zero
    }
    func setPresentation(position: CGPoint, opacity: Float, bounds: CGRect, hidden: Bool, hoverFrame: CGRect, hoverHidden: Bool) {
        if lastRootPosition != position {
            root.position = position
            lastRootPosition = position
        }
        if lastRootOpacity != opacity {
            root.opacity = opacity
            lastRootOpacity = opacity
        }
        if lastRootBounds != bounds {
            root.bounds = bounds
            lastRootBounds = bounds
        }
        if lastRootHidden != hidden {
            root.isHidden = hidden
            lastRootHidden = hidden
        }
        if lastHoverFrame != hoverFrame {
            hover.frame = hoverFrame
            lastHoverFrame = hoverFrame
        }
        if lastHoverHidden != hoverHidden {
            hover.isHidden = hoverHidden
            lastHoverHidden = hoverHidden
        }
    }
    func setBackgroundPresentation(position: CGPoint, opacity: Float) {
        if lastBackgroundPosition != position {
            backgroundWrapper.position = position
            lastBackgroundPosition = position
        }
        if lastBackgroundOpacity != opacity {
            backgroundWrapper.opacity = opacity
            lastBackgroundOpacity = opacity
        }
    }
    /// Cache a settled, inactive lyric group at the exact backing scale. The
    /// active row remains a live layer tree, while static rows can move with
    /// the window without forcing Core Animation to walk every glyph/filter
    /// layer on each display-cycle commit.
    func setRasterized(_ enabled: Bool, scale: Double) {
        let resolvedScale = max(0.5, CGFloat(scale.isFinite ? scale : 1))
        if rasterizationEnabled != enabled {
            root.shouldRasterize = enabled
            rasterizationEnabled = enabled
        }
        guard enabled, abs(lastRasterizationScale - resolvedScale) > 0.0001 else { return }
        root.rasterizationScale = resolvedScale
        lastRasterizationScale = resolvedScale
    }

    var isRasterized: Bool { rasterizationEnabled }

    func disableRasterization() {
        setRasterized(false, scale: 1)
        unbakeBlur()
    }

    // MARK: - Baked row blur

    /// A settled, inactive row keeps a constant blur radius, so its blurred
    /// appearance is a fixed image. `CALayer.filters` cannot exploit that: the
    /// render server evaluates a filter chain on every composite of the layer,
    /// and `shouldRasterize` only caches the layer content *before* filters are
    /// applied. A static blurred row therefore costs a Gaussian pass on every
    /// display refresh even while the host is idle and nothing on screen
    /// changes. Rendering the row once, blurring that bitmap and installing it
    /// as the row contents yields the same pixels with no per-frame filter work.
    private var bakedBlurRadius = Double.nan
    private var bakedBlurScale = Double.nan
    private var bakedBlurHidden: [CALayer] = []
    var isBlurBaked: Bool { !bakedBlurHidden.isEmpty }

    /// `radius` is a live `CIGaussianBlur` radius, and a layer filter is measured
    /// in the backing pixels the compositor works in — not in the row's own
    /// render scale. `scale` must therefore be the display backing scale, so the
    /// snapshot reproduces "upscale to the display, then blur" exactly. Rendering
    /// at the (lower) lyrics render scale and blurring there produced a blur of
    /// `radius * backingScale / renderScale` once the bitmap was stretched to the
    /// display, and the row visibly changed sharpness every time it switched
    /// between the baked and the live path.
    @discardableResult
    func bakeBlur(radius: Double, scale: Double, renderScale: Double = 1, context: CIContext, colorSpace: CGColorSpace? = nil, tolerance: Double = 0.02) -> Bool {
        guard radius > 0.01, scale > 0.01 else { unbakeBlur(); return false }
        // A CALayer filter's `inputRadius` is interpreted in the layer's point
        // coordinate space, so the compositor displays a blur of
        // `radius × backingScale` effective pixels. The bake blurs in the
        // display-scale bitmap, so it must use that same effective value or a
        // row that switches to the live path visibly softens. Calibrated with
        // the headless parity harness (bake vs CARenderer live render): the
        // live edge is ~2× wider at backing scale 2.0, matching radius×scale.
        // `KMGCCC_BAKE_RADIUS_K` overrides the multiplier for calibration.
        var radiusMultiplier = scale
        if let raw = ProcessInfo.processInfo.environment["KMGCCC_BAKE_RADIUS_K"], let k = Double(raw), k > 0.01 {
            radiusMultiplier = k
        }
        let effectiveRadius = radius * radiusMultiplier
        if isBlurBaked, abs(bakedBlurRadius - radius) <= tolerance, abs(bakedBlurScale - scale) <= 0.0001 { return false }
        let bounds = root.bounds
        guard bounds.width > 0.5, bounds.height > 0.5 else { return false }
        // The blur needs room to expand into, otherwise the row would be
        // clipped at its edges instead of fading out the way a live filter does.
        let pad = effectiveRadius * 3 + 2
        let pixelWidth = Int(((bounds.width + pad * 2) * scale).rounded())
        let pixelHeight = Int(((bounds.height + pad * 2) * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0, pixelWidth <= 8192, pixelHeight <= 8192 else { return false }
        // A/B knob: render the snapshot at the lyrics render scale and let the
        // bake upscale it to the display, replicating the live path (content at
        // renderScale, compositor bilinear-upscales to the display, then the
        // filter runs in display pixels). Unset keeps the old 1:1 display-scale
        // snapshot.
        let snapshotScale: Double = {
            guard let raw = ProcessInfo.processInfo.environment["KMGCCC_BAKE_SNAPSHOT_SCALE"],
                  let value = Double(raw), value > 0.01, abs(value - scale) > 0.001
            else { return scale }
            return min(2, value)
        }()
        let snapshotPixelWidth = Int(((bounds.width + pad * 2) * snapshotScale).rounded())
        let snapshotPixelHeight = Int(((bounds.height + pad * 2) * snapshotScale).rounded())
        guard snapshotPixelWidth > 0, snapshotPixelHeight > 0 else { return false }
        guard let snapshotCtx = CGContext(
            data: nil,
            width: snapshotPixelWidth,
            height: snapshotPixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return false }
        // Snapshot the live subtree, so it has to be visible first and it must not
        // still carry the previous bitmap or a live filter: otherwise the new
        // bitmap would composite stale pixels underneath the current content, and
        // a re-bake taken from already hidden layers would come out empty. Clearing
        // the baked state up front also means any failure below leaves the row on
        // the live path, where the caller reinstalls the filter in this same frame.
        bakedBlurHidden.forEach { $0.isHidden = false }
        bakedBlurHidden.removeAll(keepingCapacity: true)
        root.contents = nil
        root.filters = nil
        appliedBlur = 0
        let pointWidth = bounds.width + pad * 2
        let pointHeight = bounds.height + pad * 2
        snapshotCtx.scaleBy(x: CGFloat(snapshotScale), y: CGFloat(snapshotScale))
        // Bitmap rows run top-down while the layer draws bottom-up.
        snapshotCtx.translateBy(x: 0, y: CGFloat(pointHeight))
        snapshotCtx.scaleBy(x: 1, y: -1)
        snapshotCtx.translateBy(x: CGFloat(pad), y: CGFloat(pad))
        root.render(in: snapshotCtx)
        guard let snapshot = snapshotCtx.makeImage() else { return false }
        // Replicate the compositor's magnification: content rasterized at the
        // lyrics render scale is upscaled to the display with bilinear
        // interpolation. Draw the snapshot into a display-scale context.
        var raw = snapshot
        if abs(snapshotScale - scale) > 0.001 {
            guard let upscaleCtx = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            ) else { return false }
            upscaleCtx.interpolationQuality = .medium
            upscaleCtx.draw(snapshot, in: CGRect(x: 0, y: 0, width: CGFloat(pixelWidth), height: CGFloat(pixelHeight)))
            guard let upscaled = upscaleCtx.makeImage() else { return false }
            raw = upscaled
        }
        // `inputRadius` for a CALayer filter is measured in backing pixels, not
        // in points, so the replacement radius must not be pre-multiplied by the
        // scale again. Blur with the padding in place and crop the padding back
        // out, so the bitmap maps one-to-one onto the row bounds.
        let padPixels = pad * scale
        let contentBounds = CGRect(
            x: padPixels,
            y: padPixels,
            width: bounds.width * scale,
            height: bounds.height * scale
        )
        let blurred = CIImage(cgImage: raw)
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: effectiveRadius])
            .cropped(to: contentBounds)
        guard let image = context.createCGImage(blurred, from: contentBounds) else { return false }

        // The live line subtree stays in place and is restored verbatim when the
        // row leaves the settled state again. `hover` is deliberately left alone:
        // it draws above `root.contents` and owns its own visibility, so hiding or
        // restoring it here would strand the hover highlight on a row that is no
        // longer hovered.
        bakedBlurHidden = [main.root, backgroundWrapper]
        bakedBlurHidden.forEach { $0.isHidden = true }
        root.contents = image
        root.contentsScale = CGFloat(scale)
        root.contentsGravity = .resize
        bakedBlurRadius = radius
        bakedBlurScale = scale
        return true
    }

    func unbakeBlur() {
        guard isBlurBaked else { return }
        bakedBlurHidden.forEach { $0.isHidden = false }
        bakedBlurHidden.removeAll(keepingCapacity: true)
        root.contents = nil
        bakedBlurRadius = .nan
        bakedBlurScale = .nan
        // Let the next frame reinstall the live filter for the current radius.
        appliedBlur = 0
    }
    func updateCompositor(_ config: LyricsConfiguration) {
        if config.channelBlend.isExplicit { root.compositingFilter = nil; compositorKey = ""; return }
        let mode: LyricsBlendMode
        switch config.blendMode {
        case .normal: mode = .normal
        case .plusLighter: mode = .plusLighter
        case .plusDarker: mode = .plusDarker
        case .automatic:
            mode = config.usesCoverBlurCompositing
                ? (config.effectiveCoverBlurProfile == .darker ? .plusDarker : .plusLighter)
                : .normal
        }
        guard mode.rawValue != compositorKey else { return }
        compositorKey = mode.rawValue
        switch mode {
        case .plusLighter: root.compositingFilter = lighterCompositor
        case .plusDarker: root.compositingFilter = darkerCompositor
        case .normal, .automatic: root.compositingFilter = nil
        }
    }
    func reflow(_ layout: GroupTextLayout, cache: GlyphCache, scale: Double, config: LyricsConfiguration, now: Double) {
        disableRasterization()
        let oldMain = main, oldBG = background
        main = LineLayers(layout.main,cache:cache,scale:scale,config:config,previous:oldMain,now:now,buildContent:!oldMain.words.isEmpty,preserveWordMotion:false)
        background = layout.background.map { LineLayers($0,cache:cache,scale:scale,config:config,previous:oldBG,now:now,buildContent:!(oldBG?.words.isEmpty ?? true),preserveWordMotion:false) }
        oldMain.root.removeFromSuperlayer(); oldBG?.root.removeFromSuperlayer()
        root.addSublayer(main.root); if let background { backgroundWrapper.addSublayer(background.root) }
        self.layout = layout; isReflowing = true; reflowTarget = nil
    }
    func settled(_ time: Double) -> Bool {
        bakedContentIsStatic(time) && y.settled(time) && opacity.settled(time) && blur.settled(time)
    }

    /// Everything a baked bitmap actually freezes: the line's own position and
    /// scale inside the row box, its glyph positions and masks, and the exit
    /// fall. The row box itself (`root.position`/`root.bounds`) and
    /// `root.opacity` stay live, so scrolling the stack and fading the row do
    /// not require a new snapshot — only a change inside the box does.
    ///
    /// The blur radius is excluded on purpose. A blurred row is always rendered
    /// from its bitmap and gets its radius from a re-bake, so the blur ramp must
    /// not disqualify a row from being snapshotted; otherwise every focus change
    /// would hand the row back to a live filter.
    func bakedContentIsStatic(_ time: Double) -> Bool {
        // The exit fall keeps moving glyphs for `lyricLineFallDuration`, which is
        // longer than the highlight fade and the position springs. Freezing a row
        // before it finishes lets the frozen offset disagree with the model, and
        // the row snaps whenever live updates resume (a configuration change, a
        // reflow, or the row re-entering the animated state).
        scale.settled(time) && reveal.settled(time) && main.settled(time)
            && (background?.settled(time) ?? true)
            && (exitTime.map { time-$0>lyricLineFallDuration } ?? true)
    }
}
