import XCTest
import MelismaKit

/// 解码器对抗性健壮性测试。
///
/// 每条用例明确断言「抛错」或「成功 + 预期结构」。当前行为即基线契约，
/// 后续任何改动不得静默改变这些行为；要改变必须先改这里的断言并说明理由。
final class DecoderRobustnessTests: XCTestCase {

    private let decoder = TTMLDecoder()

    // MARK: - 工具

    private func decode(_ xml: String) throws -> LyricsDocument {
        try decoder.decode(Data(xml.utf8))
    }

    private func assertThrows(_ xml: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try decode(xml), "应抛错", file: file, line: line)
    }

    @discardableResult
    private func assertDecodes(_ xml: String, file: StaticString = #filePath, line: UInt = #line) -> LyricsDocument? {
        do {
            return try decode(xml)
        } catch {
            XCTFail("应成功解码，实际抛错：\(error)", file: file, line: line)
            return nil
        }
    }

    /// 组装标准 AMLL 绝对时间文档骨架。
    private func tt(_ body: String, rootAttrs: String = "", dur: String? = nil) -> String {
        let bodyDur = dur.map { " dur=\"\($0)\"" } ?? ""
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml" xmlns:ttm="http://www.w3.org/ns/ttml#metadata" xmlns:tts="http://www.w3.org/ns/ttml#styling" xmlns:ttp="http://www.w3.org/ns/ttml#parameter" xmlns:amll="http://www.example.com/ns/amll"\(rootAttrs)>
          <body\(bodyDur)>
        \(body)
          </body>
        </tt>
        """
    }

    // MARK: - 基础畸形输入

    func testEmptyData() {
        XCTAssertThrowsError(try decoder.decode(Data()))
    }

    func testNonXMLData() {
        assertThrows("this is definitely not xml at all")
    }

    func testWrongRootElement() {
        assertThrows("""
        <?xml version="1.0" encoding="UTF-8"?>
        <html><body><p>x</p></body></html>
        """)
    }

    func testMissingBody() {
        assertThrows("""
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml"></tt>
        """)
    }

    func testUnclosedDocument() {
        assertThrows("""
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://www.w3.org/ns/ttml"><body><p begin="0s" end="1s">x
        """)
    }

    func testWrongNamespace() {
        assertThrows("""
        <?xml version="1.0" encoding="UTF-8"?>
        <tt xmlns="http://example.invalid/ns/not-ttml"><body/></tt>
        """)
    }

    func testNULByte() {
        let xml = tt("<p begin=\"0s\" end=\"1s\">a\u{0}b</p>")
        XCTAssertThrowsError(try decode(xml))
    }

    // MARK: - 时间边界

    func testZeroDurationLine() throws {
        let doc = try XCTUnwrap(assertDecodes(tt("<p begin=\"5s\" end=\"5s\">x</p>")))
        XCTAssertEqual(doc.groups.count, 1)
        XCTAssertEqual(doc.groups[0].main.range.duration, 0, accuracy: 0.0001)
    }

    func testZeroDurationWord() throws {
        let doc = try XCTUnwrap(assertDecodes(tt("<p begin=\"0s\" end=\"2s\"><span begin=\"1s\" end=\"1s\">x</span></p>")))
        XCTAssertEqual(doc.groups[0].main.words[0].range.duration, 0, accuracy: 0.0001)
    }

    func testInvertedRangeLargeThrows() {
        // 超过 0.05s 的时间倒流是硬错误，防止畸形源静默重排歌词时间线。
        assertThrows(tt("<p begin=\"0s\" end=\"2s\"><span begin=\"5s\" end=\"3s\">x</span></p>"))
    }

    func testInvertedRangeSmallIsCorrected() throws {
        // AMLL 导出物中偶尔有一帧左右的倒流（如 03:30.349 → 03:30.331），
        // 解码器应保留 begin 并折叠范围，同时留下诊断。
        let doc = try XCTUnwrap(assertDecodes(tt("<p begin=\"0s\" end=\"2s\"><span begin=\"1.5s\" end=\"1.48s\">x</span></p>")))
        XCTAssertEqual(doc.groups[0].main.words[0].range.start, 1.5, accuracy: 0.0001)
        XCTAssertEqual(doc.groups[0].main.words[0].range.end, 1.5, accuracy: 0.0001)
        XCTAssertTrue(doc.diagnostics.contains { $0.contains("Corrected") })
    }

    func testOverlappingWords() throws {
        let doc = try XCTUnwrap(assertDecodes(
            tt("<p begin=\"0s\" end=\"4s\"><span begin=\"0s\" end=\"2s\">a</span><span begin=\"1.5s\" end=\"4s\">b</span></p>")
        ))
        let words = doc.groups[0].main.words
        XCTAssertEqual(words.count, 2)
        XCTAssertLessThan(words[0].range.end, words[1].range.end)
    }

    // MARK: - 结构与元数据

    func testDuplicateLineIDs() throws {
        let doc = try XCTUnwrap(assertDecodes(tt("""
        <p xml:id="same" begin="0s" end="1s">a</p>
        <p xml:id="same" begin="2s" end="3s">b</p>
        """)))
        XCTAssertEqual(doc.groups.count, 2)
        XCTAssertEqual(doc.groups[0].main.id, doc.groups[1].main.id)
    }

    func testEmptyParagraph() throws {
        let doc = try XCTUnwrap(assertDecodes(tt("<p begin=\"0s\" end=\"1s\"></p>")))
        XCTAssertEqual(doc.groups.count, 1)
        XCTAssertTrue(doc.groups[0].main.words.isEmpty)
    }

    func testWhitespaceOnlyLine() throws {
        let doc = try XCTUnwrap(assertDecodes(tt("<p begin=\"0s\" end=\"1s\">   \n  </p>")))
        XCTAssertEqual(doc.groups.count, 1)
        XCTAssertTrue(doc.groups[0].main.words.isEmpty)
    }

    func testNestedBackgroundIsDropped() throws {
        // x-bg 内的 x-bg 不再提升为伴唱行，内容静默丢弃（当前契约）。
        let doc = try XCTUnwrap(assertDecodes(tt("""
        <p begin="0s" end="4s"><span begin="0s" end="4s">main</span><span ttm:role="x-bg"><span ttm:role="x-bg">inner</span></span></p>
        """)))
        XCTAssertEqual(doc.groups[0].main.words.count, 1)
        XCTAssertEqual(doc.groups[0].background?.words.count ?? 0, 0)
    }

    func testCDATABlock() throws {
        let doc = try XCTUnwrap(assertDecodes(tt("<p begin=\"0s\" end=\"2s\"><![CDATA[city lights]]></p>")))
        XCTAssertEqual(doc.groups[0].main.words.first?.text, "city lights")
    }

    // MARK: - 时钟语法

    func testSubFrameClock() throws {
        let doc = try XCTUnwrap(assertDecodes(
            tt("<p begin=\"00:00:01:15.1\" end=\"00:00:03:00.0\">x</p>",
               rootAttrs: " ttp:frameRate=\"30\" ttp:subFrameRate=\"2\"")
        ))
        // 1s + 15/30 + 1/(2*30) = 1.516667
        XCTAssertEqual(doc.groups[0].main.range.start, 1 + 15.0 / 30 + 1.0 / 60, accuracy: 0.0001)
    }

    func testTickClock() throws {
        let doc = try XCTUnwrap(assertDecodes(
            tt("<p begin=\"120t\" end=\"240t\">x</p>", rootAttrs: " ttp:tickRate=\"24\"")
        ))
        XCTAssertEqual(doc.groups[0].main.range.start, 5.0, accuracy: 0.0001)
        XCTAssertEqual(doc.groups[0].main.range.end, 10.0, accuracy: 0.0001)
    }

    func testFrameClock() throws {
        let doc = try XCTUnwrap(assertDecodes(
            tt("<p begin=\"00:00:02:15\" end=\"00:00:03:00\">x</p>", rootAttrs: " ttp:frameRate=\"30\"")
        ))
        XCTAssertEqual(doc.groups[0].main.range.start, 2.5, accuracy: 0.0001)
    }

    func testFrameRateMultiplier() throws {
        let doc = try XCTUnwrap(assertDecodes(
            tt("<p begin=\"00:00:01:15\" end=\"00:00:02:00\">x</p>",
               rootAttrs: " ttp:frameRate=\"30\" ttp:frameRateMultiplier=\"1000 1001\"")
        ))
        // 30 × 1000/1001 ≈ 29.97fps；1s + 15/29.97 ≈ 1.5005
        let expected = 1 + 15.0 / (30.0 * 1000.0 / 1001.0)
        XCTAssertEqual(doc.groups[0].main.range.start, expected, accuracy: 0.001)
    }

    func testCompactMmSsClock() throws {
        // Apple Music 曲库文件常用 mm:ss.fff 紧凑形式，必须被接受。
        let doc = try XCTUnwrap(assertDecodes(tt("<p begin=\"04:24.615\" end=\"04:28.000\">x</p>")))
        XCTAssertEqual(doc.groups[0].main.range.start, 264.615, accuracy: 0.0001)
    }

    func testUnsupportedTimeBase() {
        assertThrows(tt("<p begin=\"0s\" end=\"1s\">x</p>", rootAttrs: " ttp:timeBase=\"clock\""))
    }

    // MARK: - 文本内容

    func testEmojiText() throws {
        let doc = try XCTUnwrap(assertDecodes(tt("<p begin=\"0s\" end=\"2s\">🎵🎶</p>")))
        XCTAssertEqual(doc.groups[0].main.words.first?.text, "🎵🎶")
    }

    func testZWJEmoji() throws {
        let family = "👩\u{200D}👩\u{200D}👧\u{200D}👦"
        let doc = try XCTUnwrap(assertDecodes(tt("<p begin=\"0s\" end=\"2s\">\(family)</p>")))
        XCTAssertEqual(doc.groups[0].main.words.first?.text, family)
    }

    func testRTLText() throws {
        let arabic = "أنوار المدينة تلمع في الليل"
        let doc = try XCTUnwrap(assertDecodes(tt("<p begin=\"0s\" end=\"2s\">\(arabic)</p>")))
        XCTAssertEqual(doc.groups[0].main.words.first?.text, arabic)
    }

    func testCombiningCharacters() throws {
        let text = "cafe\u{301} elegant"
        let doc = try XCTUnwrap(assertDecodes(tt("<p begin=\"0s\" end=\"2s\">\(text)</p>")))
        XCTAssertEqual(doc.groups[0].main.words.first?.text, text)
    }

    func testVeryLongLine() throws {
        // 2000 个词的超长行：解码必须成功且结构完整（布局性能是另一回事）。
        var spans = ""
        for j in 0..<2000 {
            let s = Double(j) * 0.001
            spans += "<span begin=\"\(String(format: "%.3f", s))s\" end=\"\(String(format: "%.3f", s + 0.001))s\">w\(j)</span>"
        }
        let doc = try XCTUnwrap(assertDecodes(tt("<p begin=\"0s\" end=\"2s\">\(spans)</p>")))
        XCTAssertEqual(doc.groups[0].main.words.count, 2000)
    }

    func testBrLineBreak() throws {
        // 逐行定时（无时间化 span）下，整行文本折叠为单个词，`<br/>` 折叠为词内换行。
        let doc = try XCTUnwrap(assertDecodes(tt("<p begin=\"0s\" end=\"2s\">a<br/>b</p>")))
        let words = doc.groups[0].main.words
        XCTAssertEqual(words.count, 1)
        XCTAssertEqual(words[0].text, "a\nb")
    }

    // MARK: - DOCTYPE 四种形态
    //
    // 现状契约：`TTMLDecoder.swift` 的 `hasDoctype` 守卫依赖
    // XMLParserDelegate.foundExternalEntityDeclarationWithName，但该回调在
    // `shouldResolveExternalEntities = false` 下不会被触发 —— 无论 DOCTYPE 是
    // 内部子集、SYSTEM、PUBLIC 还是带外部实体声明，解析都静默成功。
    // 由于外部实体不会被解析（resolveExternalEntityName 返回 nil），当前没有
    // 实体注入面，但「拒绝 DOCTYPE」的意图未达成。这里锁定现状；
    // 收紧守卫需要单独修改实现并同步更新这些断言。

    func testDoctypeInternalSubsetWithoutEntities() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE tt [<!ELEMENT tt ANY>]>
        <tt xmlns="http://www.w3.org/ns/ttml"><body dur="2s"><p begin="0s" end="1s">x</p></body></tt>
        """
        let doc = try XCTUnwrap(assertDecodes(xml))
        XCTAssertEqual(doc.groups.count, 1)
    }

    func testDoctypeSystemExternal() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE tt SYSTEM "http://www.example.com/tt.dtd">
        <tt xmlns="http://www.w3.org/ns/ttml"><body dur="2s"><p begin="0s" end="1s">x</p></body></tt>
        """
        let doc = try XCTUnwrap(assertDecodes(xml))
        XCTAssertEqual(doc.groups.count, 1)
    }

    func testDoctypePublicExternal() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE tt PUBLIC "-//W3C//DTD TTML 1.0//EN" "http://www.example.com/tt.dtd">
        <tt xmlns="http://www.w3.org/ns/ttml"><body dur="2s"><p begin="0s" end="1s">x</p></body></tt>
        """
        let doc = try XCTUnwrap(assertDecodes(xml))
        XCTAssertEqual(doc.groups.count, 1)
    }

    func testDoctypeWithExternalEntityDeclaration() throws {
        // 内部子集里声明外部实体：实体不会展开（解析器不解析外部实体），文档仍可解码。
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE tt [<!ENTITY xxe SYSTEM "http://www.example.com/evil">]>
        <tt xmlns="http://www.w3.org/ns/ttml"><body dur="2s"><p begin="0s" end="1s">x</p></body></tt>
        """
        let doc = try XCTUnwrap(assertDecodes(xml))
        XCTAssertEqual(doc.groups.count, 1)
    }

    // MARK: - 实体引用

    func testBuiltinEntityReferences() throws {
        let doc = try XCTUnwrap(assertDecodes(tt("<p begin=\"0s\" end=\"2s\">a &amp; b &lt; c &gt; d &quot;e&quot; &apos;f&apos;</p>")))
        let text = doc.groups[0].main.words.map(\.text).joined()
        XCTAssertEqual(text, "a & b < c > d \"e\" 'f'")
    }

    func testNumericCharacterReference() throws {
        let doc = try XCTUnwrap(assertDecodes(tt("<p begin=\"0s\" end=\"2s\">&#x4F60;&#22909;</p>")))
        XCTAssertEqual(doc.groups[0].main.words.first?.text, "你好")
    }

    func testUndefinedEntityReference() {
        assertThrows(tt("<p begin=\"0s\" end=\"2s\">&nosuch;</p>"))
    }

    // MARK: - 生命周期与扩展属性

    func testUnboundedLine() {
        // p 没有 end/dur，body 也没有 dur，且行内有关键词 → 硬错误。
        assertThrows(tt("<p begin=\"5s\">text</p>"))
    }

    func testEmptyBeatAttribute() throws {
        let doc = try XCTUnwrap(assertDecodes(
            tt("<p begin=\"0s\" end=\"2s\"><span begin=\"0s\" end=\"2s\" amll:empty-beat=\"2\">x</span></p>")
        ))
        XCTAssertEqual(doc.groups[0].main.words[0].emptyBeat, 2)
    }

    func testLegacyNamespaceAcceptedInAMLLProfile() throws {
        // AMLL profile 下，历史遗留的无命名空间内容被接受并给出诊断。
        let doc = try XCTUnwrap(assertDecodes("""
        <?xml version="1.0" encoding="UTF-8"?>
        <tt><body dur="2s"><p begin="0s" end="1s">x</p></body></tt>
        """))
        XCTAssertEqual(doc.groups.count, 1)
        XCTAssertTrue(doc.diagnostics.contains { $0.contains("legacy AMLL") })
    }
}
