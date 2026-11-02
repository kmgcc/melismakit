import XCTest
import MelismaKit
import MelismaKitBenchCore

/// 可复现语料库的生成器驱动完整性测试。
///
/// `Fixtures/` 下的语料文件由 `MelismaKitBenchCore.SyntheticTTML` 确定性生成
/// （字节一致，SHA256 清单可复核）。本测试直接驱动生成器，校验每个语料文档
/// 都能被解码器正确读取并具备预期结构 —— 生成器与解码器任一方的漂移都会在此红。
final class SyntheticCorpusTests: XCTestCase {

    private func decode(_ file: SyntheticTTML.CorpusFile) throws -> LyricsDocument {
        try TTMLDecoder().decode(Data(SyntheticTTML.corpus(file).utf8))
    }

    // MARK: - 确定性

    func testGeneratorIsDeterministic() {
        for file in SyntheticTTML.CorpusFile.allCases {
            XCTAssertEqual(SyntheticTTML.corpus(file), SyntheticTTML.corpus(file), "\(file.fileName) 必须确定性生成")
        }
        for mode in SyntheticTTML.ScaleMode.allCases {
            XCTAssertEqual(
                SyntheticTTML.scaled(lines: 120, mode: mode),
                SyntheticTTML.scaled(lines: 120, mode: mode),
                "scale=120 mode=\(mode.rawValue) 必须确定性生成"
            )
        }
    }

    // MARK: - 全部语料可解码

    func testAllCorpusFilesDecode() throws {
        for file in SyntheticTTML.CorpusFile.allCases {
            let doc = try decode(file)
            XCTAssertGreaterThan(doc.groups.count, 0, "\(file.fileName) 至少 1 组")
            for group in doc.groups {
                XCTAssertTrue(group.main.range.end.isFinite, "\(file.fileName) 主行范围必须有界")
                XCTAssertFalse(group.main.text.isEmpty, "\(file.fileName) 主行文本非空")
            }
        }
    }

    // MARK: - 各语料的特性断言

    func testWordTimedCorpus() throws {
        let doc = try decode(.wordTimed)
        XCTAssertTrue(doc.groups.allSatisfy { $0.main.isWordTimed })
        XCTAssertGreaterThan(doc.groups[0].main.words.count, 1)
    }

    func testLineTimedCorpus() throws {
        let doc = try decode(.lineTimed)
        XCTAssertTrue(doc.groups.allSatisfy { !$0.main.isWordTimed })
    }

    func testRubyCorpus() throws {
        let doc = try decode(.ruby)
        XCTAssertTrue(doc.groups.contains { group in
            group.main.words.contains { !$0.ruby.isEmpty }
        })
    }

    func testDuetCorpus() throws {
        let doc = try decode(.duet)
        let agents = Set(doc.groups.map(\.main.agent))
        XCTAssertGreaterThanOrEqual(agents.count, 2)
        XCTAssertTrue(doc.groups.contains { $0.main.isDuet })
    }

    func testTranslationCorpus() throws {
        let doc = try decode(.translation)
        XCTAssertTrue(doc.groups.contains { group in
            group.main.translations.contains { !$0.text.isEmpty }
        })
    }

    func testRomanizationCorpus() throws {
        let doc = try decode(.romanization)
        XCTAssertTrue(doc.groups.contains { group in
            group.main.romanizations.contains { !$0.text.isEmpty }
        })
    }

    func testBackgroundCorpus() throws {
        let doc = try decode(.background)
        let backgrounds = doc.groups.compactMap(\.background).filter { !$0.words.isEmpty }
        XCTAssertFalse(backgrounds.isEmpty)
        // 括号剥离：首词不以（( 开头，末词不以 ）) 结尾。
        for bg in backgrounds {
            XCTAssertFalse(bg.words[0].text.hasPrefix("("))
            XCTAssertFalse(bg.words[bg.words.count - 1].text.hasSuffix(")"))
        }
    }

    func testInterludeCorpus() throws {
        let doc = try decode(.interlude)
        var maxGap = 0.0
        for i in 1..<doc.groups.count {
            let gap = doc.groups[i].main.range.start - doc.groups[i - 1].main.range.end
            maxGap = max(maxGap, gap)
        }
        // 语料特意在第 4 行后留出 5.6s 空白（间奏阈值 ≥ 4s）。
        XCTAssertGreaterThanOrEqual(maxGap, 4.0)
    }

    func testLongWordsCorpus() throws {
        let doc = try decode(.longWords)
        XCTAssertTrue(doc.groups.contains { group in
            group.main.words.contains { $0.text.count > 40 }
        })
    }

    func testCJKEmojiRTLCombiningCorpus() throws {
        let doc = try decode(.cjkEmojiRTLCombining)
        let text = doc.groups.flatMap { $0.main.words.map(\.text) }.joined()
        XCTAssertTrue(text.contains("城市"))
        XCTAssertTrue(text.contains("🌃"))
        XCTAssertTrue(text.contains("أنوار"))
        XCTAssertTrue(text.contains("cafe\u{301}"))
        // ZWJ 家庭 emoji 是一个 grapheme cluster，必须整串匹配。
        XCTAssertTrue(text.contains("👩\u{200D}👩\u{200D}👧\u{200D}👦"))
    }
}
