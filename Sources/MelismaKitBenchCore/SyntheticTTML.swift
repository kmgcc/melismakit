import Foundation

/// 确定性合成 TTML 生成器。
///
/// 本模块供 `MelismaKitBench` 与 `MelismaKitProbe` 共用，保证两个工具的测量口径
/// 完全一致。所有生成内容都是**确定性**的：没有时间戳、没有随机数，同一输入永远
/// 产出字节一致的结果 —— 这是 `Fixtures/SHA256SUMS.txt` 清单可复现的前提。
///
/// 歌词文本全部为原创占位内容，遵循 `Documentation/LICENSING.md` 的资产政策
/// （不引入任何受著作权保护的第三方歌词）。
public enum SyntheticTTML {

    // MARK: - 规模测量文档

    /// 规模测量文档的类型。
    public enum ScaleMode: String, CaseIterable, Codable {
        /// 普通歌曲，逐词定时
        case word = "word"
        /// 逐行定时
        case line = "line"
        /// 日语 + Ruby 注音
        case ruby = "ruby"
        /// 超长单词压力路径
        case longWord = "longWord"
    }

    /// 生成 N 行的规模测量文档（确定性，AMLL media-absolute profile）。
    public static func scaled(lines: Int, mode: ScaleMode) -> String {
        precondition(lines >= 1, "规模文档至少需要 1 行")
        switch mode {
        case .word: return wordScaled(lines)
        case .line: return lineScaled(lines)
        case .ruby: return rubyScaled(lines)
        case .longWord: return longWordScaled(lines)
        }
    }

    // MARK: - 可复现语料库（写入 Fixtures/）

    /// 可复现语料库中的文档。
    public enum CorpusFile: String, CaseIterable, Sendable {
        case wordTimed = "word-timed.ttml"
        case lineTimed = "line-timed.ttml"
        case ruby = "ruby.ttml"
        case duet = "duet.ttml"
        case translation = "translation.ttml"
        case romanization = "romanization.ttml"
        case background = "background.ttml"
        case interlude = "interlude.ttml"
        case longWords = "long-words.ttml"
        case cjkEmojiRTLCombining = "cjk-emoji-rtl-combining.ttml"

        /// 磁盘文件名（与 `rawValue` 相同）。
        public var fileName: String { rawValue }
    }

    /// 生成指定语料文档（确定性）。
    public static func corpus(_ file: CorpusFile) -> String {
        switch file {
        case .wordTimed: return wordCorpus
        case .lineTimed: return lineCorpus
        case .ruby: return rubyCorpus
        case .duet: return duetCorpus
        case .translation: return translationCorpus
        case .romanization: return romanizationCorpus
        case .background: return backgroundCorpus
        case .interlude: return interludeCorpus
        case .longWords: return longWordsCorpus
        case .cjkEmojiRTLCombining: return cjkEmojiRTLCombiningCorpus
        }
    }

    // MARK: - 内容素材（全部为原创文本）

    /// 原创英文歌词素材（16 行），用于 word/line 模式与语料库。
    private static let englishLines: [String] = [
        "City lights are fading in the quiet rain",
        "Every window keeps a story of its own",
        "We were running toward a softer light",
        "All the miles we made are turning gold",
        "Morning finds us where the river bends",
        "Hold the echo of a summer song",
        "Paper lanterns drifting down the street",
        "Somewhere past the bridges of the night",
        "Clouds divide above the silver lake",
        "Letters never sent still find their way",
        "Distant trains are humming through the dark",
        "We will meet again when winter ends",
        "Small fires glow along the empty shore",
        "Every breath you take becomes a song",
        "Stars are waiting for the sky to clear",
        "Home is anywhere the heart can rest",
    ]

    /// 原创中文翻译素材（与 `englishLines` 一一对应）。
    private static let chineseTranslations: [String] = [
        "城市灯火在细雨中渐渐熄灭",
        "每扇窗都藏着自己的故事",
        "我们奔向更温柔的光",
        "走过的路正渐渐镀上金色",
        "清晨在河流转弯处找到我们",
        "留住一首夏日歌的回声",
        "纸灯笼沿着街道慢慢飘远",
        "夜色中桥的那一边",
        "云层在银色湖面上分开",
        "从未寄出的信仍会抵达",
        "远方的列车在夜色中低鸣",
        "冬天结束时我们会再相见",
        "空荡海岸上燃着微小的火",
        "你的每一次呼吸都成了一首歌",
        "星星正等着天空放晴",
        "心能安放之处便是家",
    ]

    /// 原创日语歌词素材（带 Ruby 读音）：每行是一组 (基底, 读音?)。
    private static let japaneseLines: [[(String, String?)]] = [
        [("夜明け", "よあけ"), ("の", nil), ("光", "ひかり")],
        [("遠い", "とおい"), ("風", "かぜ"), ("の", nil), ("音", "おと")],
        [("静かな", "しずかな"), ("海辺", "うみべ")],
        [("小さな", "ちいさな"), ("花", "はな"), ("のように", nil)],
        [("季節", "きせつ"), ("が", nil), ("巡る", "めぐる"), ("よ", nil)],
        [("空", "そら"), ("を", nil), ("渡る", "わたる"), ("鳥", "とり")],
        [("君", "きみ"), ("の", nil), ("笑顔", "えがお"), ("が", nil)],
        [("星", "ほし"), ("が", nil), ("降る", "ふる"), ("夜", "よる")],
    ]

    /// 原创罗马音素材（与 `japaneseLines` 一一对应）。
    private static let romanizations: [String] = [
        "yoake no hikari",
        "tooi kaze no oto",
        "shizuka na umibe",
        "chiisana hana no you ni",
        "kisetsu ga meguru yo",
        "sora wo wataru tori",
        "kimi no egao ga",
        "hoshi ga furu yoru",
    ]

    /// 长词压力素材：无空格的超长单词，用于压测字形整形与遮罩。
    private static let longWords: [String] = [
        "electroencephalographically",
        "pneumonoultramicroscopicsilicovolcanoconiosis",
        "antidisestablishmentarianism",
        "floccinaucinihilipilification",
        "hippopotomonstrosesquipedaliophobia",
        "uncharacteristicallytranscendentally",
        "spectrophotometricallyrecalibrated",
        "incomprehensibilityinterconnections",
    ]

    // MARK: - 规模文档生成

    /// 逐词定时（§2.2「合成」）：每行 4.0s，行内按词数均分词时间段。
    private static func wordScaled(_ lines: Int) -> String {
        var rows: [String] = []
        for i in 0..<lines {
            rows.append(timedRow(index: i) { text in
                let words = text.split(separator: " ")
                let n = Double(words.count)
                var spans: [String] = []
                for (j, w) in words.enumerated() {
                    let ws = baseStart(i) + Double(j) * 3.6 / n
                    let we = baseStart(i) + Double(j + 1) * 3.6 / n
                    spans.append("<span begin=\"\(fmt(ws))s\" end=\"\(fmt(we))s\">\(w)</span>")
                }
                return spans.joined()
            })
        }
        return document(title: "Synthetic Word-Timed", lang: "en", dur: totalDuration(lines), body: rows.joined(separator: "\n"))
    }

    /// 逐行定时（§2.2「line-timed」）：p 内直接放整行文本，无时间化 span。
    private static func lineScaled(_ lines: Int) -> String {
        var rows: [String] = []
        for i in 0..<lines {
            rows.append(timedRow(index: i) { $0 })
        }
        return document(title: "Synthetic Line-Timed", lang: "en", dur: totalDuration(lines), body: rows.joined(separator: "\n"))
    }

    /// 日语 + Ruby（§2.2「ruby」）。
    private static func rubyScaled(_ lines: Int) -> String {
        var rows: [String] = []
        for i in 0..<lines {
            let segments = japaneseLines[i % japaneseLines.count]
            rows.append(timedRow(index: i) { _ in
                let n = Double(segments.count)
                var spans: [String] = []
                for (j, seg) in segments.enumerated() {
                    let ws = baseStart(i) + Double(j) * 3.6 / n
                    let we = baseStart(i) + Double(j + 1) * 3.6 / n
                    if let reading = seg.1 {
                        spans.append(
                            "<span begin=\"\(fmt(ws))s\" end=\"\(fmt(we))s\" tts:ruby=\"container\">"
                            + "<span tts:ruby=\"base\">\(seg.0)</span>"
                            + "<span tts:ruby=\"text\" begin=\"\(fmt(ws))s\" end=\"\(fmt(we))s\">\(reading)</span>"
                            + "</span>"
                        )
                    } else {
                        spans.append("<span begin=\"\(fmt(ws))s\" end=\"\(fmt(we))s\">\(seg.0)</span>")
                    }
                }
                return spans.joined()
            })
        }
        return document(title: "Synthetic Ruby", lang: "ja", dur: totalDuration(lines), body: rows.joined(separator: "\n"))
    }

    /// 长词压力（§2.2「长词压力」）：每行一个超长单词，长到在一行内多次回绕，
    /// 压测字形整形与遮罩的极端路径。
    private static func longWordScaled(_ lines: Int) -> String {
        var rows: [String] = []
        for i in 0..<lines {
            let word = elongatedWord(longWords[i % longWords.count], target: 360)
            rows.append(timedRow(index: i) { _ in
                "<span begin=\"\(fmt(baseStart(i)))s\" end=\"\(fmt(baseStart(i) + 3.6))s\">\(word)</span>"
            })
        }
        return document(title: "Synthetic Long-Word Stress", lang: "en", dur: totalDuration(lines), body: rows.joined(separator: "\n"))
    }

    /// 把单词重复拼接直到达到目标字符数（确定性；仅用于压力测量文档）。
    private static func elongatedWord(_ base: String, target: Int) -> String {
        var result = ""
        while result.count < target { result += base }
        return result
    }

    /// 生成一行 `<p>`：行 i 起点 = i*4s，持续 3.6s；`body` 闭包产出 p 内部内容。
    private static func timedRow(index i: Int, body: (String) -> String) -> String {
        let start = baseStart(i)
        let end = start + 3.6
        let text = englishLines[i % englishLines.count]
        return "<p begin=\"\(fmt(start))s\" end=\"\(fmt(end))s\">\(body(text))</p>"
    }

    private static func baseStart(_ i: Int) -> Double { Double(i) * 4.0 }
    private static func totalDuration(_ lines: Int) -> Double { Double(lines) * 4.0 - 0.4 }

    // MARK: - 语料库文档（小型、可读、单一特性）

    private static var wordCorpus: String {
        song(
            title: "Synthetic Word-Timed", lang: "en",
            lines: Array(englishLines.prefix(8)),
            row: { i, begin, end, text in
                let words = text.split(separator: " ")
                let n = Double(words.count)
                var spans: [String] = []
                for (j, w) in words.enumerated() {
                    spans.append("<span begin=\"\(fmt(begin + Double(j) * 3.6 / n))s\" end=\"\(fmt(begin + Double(j + 1) * 3.6 / n))s\">\(w)</span>")
                }
                return "<p begin=\"\(fmt(begin))s\" end=\"\(fmt(end))s\">\(spans.joined())</p>"
            })
    }

    private static var lineCorpus: String {
        song(
            title: "Synthetic Line-Timed", lang: "en",
            lines: Array(englishLines.prefix(8)),
            row: { _, begin, end, text in
                "<p begin=\"\(fmt(begin))s\" end=\"\(fmt(end))s\">\(text)</p>"
            })
    }

    private static var rubyCorpus: String {
        song(
            title: "Synthetic Ruby", lang: "ja",
            lines: japaneseLines,
            row: { _, begin, end, segments in
                let n = Double(segments.count)
                var spans: [String] = []
                for (j, seg) in segments.enumerated() {
                    let ws = begin + Double(j) * 3.6 / n
                    let we = begin + Double(j + 1) * 3.6 / n
                    if let reading = seg.1 {
                        spans.append(
                            "<span begin=\"\(fmt(ws))s\" end=\"\(fmt(we))s\" tts:ruby=\"container\">"
                            + "<span tts:ruby=\"base\">\(seg.0)</span>"
                            + "<span tts:ruby=\"text\" begin=\"\(fmt(ws))s\" end=\"\(fmt(we))s\">\(reading)</span>"
                            + "</span>"
                        )
                    } else {
                        spans.append("<span begin=\"\(fmt(ws))s\" end=\"\(fmt(we))s\">\(seg.0)</span>")
                    }
                }
                return "<p begin=\"\(fmt(begin))s\" end=\"\(fmt(end))s\">\(spans.joined())</p>"
            })
    }

    private static var duetCorpus: String {
        var rows: [String] = []
        let lines = englishLines
        for i in 0..<8 {
            let agent = i % 2 == 0 ? "a" : "b"
            let begin = Double(i) * 4.0
            let end = begin + 3.6
            let text = lines[i]
            let words = text.split(separator: " ")
            let n = Double(words.count)
            var spans: [String] = []
            for (j, w) in words.enumerated() {
                spans.append("<span begin=\"\(fmt(begin + Double(j) * 3.6 / n))s\" end=\"\(fmt(begin + Double(j + 1) * 3.6 / n))s\">\(w)</span>")
            }
            rows.append("<p begin=\"\(fmt(begin))s\" end=\"\(fmt(end))s\" ttm:agent=\"\(agent)\">\(spans.joined())</p>")
        }
        return document(title: "Synthetic Duet", lang: "en", agents: ["a", "b"], dur: 32.0, body: rows.joined(separator: "\n"))
    }

    private static var translationCorpus: String {
        var rows: [String] = []
        for i in 0..<8 {
            let begin = Double(i) * 4.0
            let end = begin + 3.6
            let text = englishLines[i]
            let words = text.split(separator: " ")
            let n = Double(words.count)
            var spans: [String] = []
            for (j, w) in words.enumerated() {
                spans.append("<span begin=\"\(fmt(begin + Double(j) * 3.6 / n))s\" end=\"\(fmt(begin + Double(j + 1) * 3.6 / n))s\">\(w)</span>")
            }
            rows.append(
                "<p begin=\"\(fmt(begin))s\" end=\"\(fmt(end))s\">\(spans.joined())"
                + "<span ttm:role=\"x-translation\" xml:lang=\"zh-Hans\">\(chineseTranslations[i])</span></p>"
            )
        }
        return document(title: "Synthetic Translation", lang: "en", dur: 32.0, body: rows.joined(separator: "\n"))
    }

    private static var romanizationCorpus: String {
        var rows: [String] = []
        for i in 0..<8 {
            let begin = Double(i) * 4.0
            let end = begin + 3.6
            let segments = japaneseLines[i % japaneseLines.count]
            let n = Double(segments.count)
            var spans: [String] = []
            for (j, seg) in segments.enumerated() {
                let ws = begin + Double(j) * 3.6 / n
                let we = begin + Double(j + 1) * 3.6 / n
                if let reading = seg.1 {
                    spans.append(
                        "<span begin=\"\(fmt(ws))s\" end=\"\(fmt(we))s\" tts:ruby=\"container\">"
                        + "<span tts:ruby=\"base\">\(seg.0)</span>"
                        + "<span tts:ruby=\"text\" begin=\"\(fmt(ws))s\" end=\"\(fmt(we))s\">\(reading)</span>"
                        + "</span>"
                    )
                } else {
                    spans.append("<span begin=\"\(fmt(ws))s\" end=\"\(fmt(we))s\">\(seg.0)</span>")
                }
            }
            rows.append(
                "<p begin=\"\(fmt(begin))s\" end=\"\(fmt(end))s\">\(spans.joined())"
                + "<span ttm:role=\"x-roman\" xml:lang=\"ja-Latn\">\(romanizations[i])</span></p>"
            )
        }
        return document(title: "Synthetic Romanization", lang: "ja", dur: 32.0, body: rows.joined(separator: "\n"))
    }

    private static var backgroundCorpus: String {
        var rows: [String] = []
        let lines = englishLines
        for i in 0..<8 {
            let begin = Double(i) * 4.0
            let end = begin + 3.6
            let text = lines[i]
            let words = text.split(separator: " ")
            let n = Double(words.count)
            let echo = String(words.last ?? "echo")
            var spans: [String] = []
            for (j, w) in words.enumerated() {
                spans.append("<span begin=\"\(fmt(begin + Double(j) * 3.6 / n))s\" end=\"\(fmt(begin + Double(j + 1) * 3.6 / n))s\">\(w)</span>")
            }
            let bg = "<span ttm:role=\"x-bg\"><span begin=\"\(fmt(begin))s\" end=\"\(fmt(end))s\">(\(echo))</span></span>"
            rows.append("<p begin=\"\(fmt(begin))s\" end=\"\(fmt(end))s\">\(spans.joined())\(bg)</p>")
        }
        return document(title: "Synthetic Background Vocals", lang: "en", dur: 32.0, body: rows.joined(separator: "\n"))
    }

    private static var interludeCorpus: String {
        // 第 4 行（index 3）结束后留出 5.6s 空白 → 触发间奏点（阈值 ≥ 4s）。
        var rows: [String] = []
        let timings: [(Double, Double)] = [
            (0, 3.6), (4, 7.6), (8, 11.6), (12, 15.6),
            (21.2, 24.8), (25.2, 28.8), (29.2, 32.8), (33.2, 36.8),
        ]
        for (i, pair) in timings.enumerated() {
            let text = englishLines[i]
            let begin = pair.0, end = pair.1
            let words = text.split(separator: " ")
            let n = Double(words.count)
            var spans: [String] = []
            for (j, w) in words.enumerated() {
                spans.append("<span begin=\"\(fmt(begin + Double(j) * (end - begin) / n))s\" end=\"\(fmt(begin + Double(j + 1) * (end - begin) / n))s\">\(w)</span>")
            }
            rows.append("<p begin=\"\(fmt(begin))s\" end=\"\(fmt(end))s\">\(spans.joined())</p>")
        }
        return document(title: "Synthetic Interlude", lang: "en", dur: 37.0, body: rows.joined(separator: "\n"))
    }

    private static var longWordsCorpus: String {
        var rows: [String] = []
        for (i, word) in longWords.prefix(6).enumerated() {
            let begin = Double(i) * 4.0
            let end = begin + 3.6
            rows.append(
                "<p begin=\"\(fmt(begin))s\" end=\"\(fmt(end))s\">"
                + "<span begin=\"\(fmt(begin))s\" end=\"\(fmt(end))s\">\(word)</span></p>"
            )
        }
        return document(title: "Synthetic Long-Word Stress", lang: "en", dur: 24.0, body: rows.joined(separator: "\n"))
    }

    private static var cjkEmojiRTLCombiningCorpus: String {
        // 每一行混合一类特殊字符：CJK、emoji、RTL（阿拉伯语）、组合字符、ZWJ 家庭 emoji。
        func row(_ i: Int, _ text: String) -> String {
            let begin = Double(i) * 4.0
            let end = begin + 3.6
            return "<p begin=\"\(fmt(begin))s\" end=\"\(fmt(end))s\"><span begin=\"\(fmt(begin))s\" end=\"\(fmt(end))s\">\(text)</span></p>"
        }
        let rows: [String] = [
            row(0, "城市の灯火"),
            row(1, "🌃 霓虹 🎵"),
            row(2, "أنوار المدينة تلمع في الليل"),
            row(3, "cafe\u{301} 与 e\u{301}le\u{301}gant"),
            row(4, "👩\u{200D}👩\u{200D}👧\u{200D}👦 一家"),
            row(5, "夜空の星"),
        ]
        return document(title: "Synthetic CJK Emoji RTL Combining", lang: "und", dur: 24.0, body: rows.joined(separator: "\n"))
    }

    // MARK: - 通用骨架

    /// 用一组行的内容组装完整 TTML 文档。
    private static func song(title: String, lang: String, lines: [String], row: (Int, Double, Double, String) -> String) -> String {
        var rows: [String] = []
        for (i, text) in lines.enumerated() {
            let begin = Double(i) * 4.0
            rows.append(row(i, begin, begin + 3.6, text))
        }
        return document(title: title, lang: lang, dur: Double(lines.count) * 4.0 - 0.4, body: rows.joined(separator: "\n"))
    }

    private static func song(title: String, lang: String, lines: [[(String, String?)]], row: (Int, Double, Double, [(String, String?)]) -> String) -> String {
        var rows: [String] = []
        for (i, segments) in lines.enumerated() {
            let begin = Double(i) * 4.0
            rows.append(row(i, begin, begin + 3.6, segments))
        }
        return document(title: title, lang: lang, dur: Double(lines.count) * 4.0 - 0.4, body: rows.joined(separator: "\n"))
    }

    private static func document(title: String, lang: String, agents: [String] = [], dur: Double, body: String) -> String {
        let agentMeta = agents.map { "<ttm:agent xml:id=\"\($0)\" type=\"person\"/>" }.joined()
        let metadata = "<metadata><ttm:title>\(title)</ttm:title>\(agentMeta)</metadata>"
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" xmlns:tts="http://www.w3.org/ns/ttml#styling" xml:lang="\(lang)">
          <head>\(metadata)</head>
          <body dur="\(fmt(dur))s">
        \(body)
          </body>
        </tt>
        """
    }

    /// 固定 4 位小数并去除尾零，输出稳定的最短时间字符串（如 `3.6`、`3`）。
    private static func fmt(_ x: Double) -> String {
        var s = String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), x)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}
