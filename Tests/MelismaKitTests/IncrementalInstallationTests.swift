import AppKit
import XCTest
@testable import MelismaKit

final class IncrementalInstallationTests: XCTestCase {
    private func document(count: Int = 100, longLines: Bool = true) -> LyricsDocument {
        let groups = (0..<count).map { index in
            let range = LyricRange(Double(index * 3), Double(index * 3 + 3))
            let word = LyricWord(
                id: "word-\(index)",
                text: longLines ? String(repeating: "A long lyric line for wrapping ", count: 6) : "Upcoming line \(index)",
                range: range
            )
            return LyricGroup(main: LyricLine(id: "line-\(index)", range: range, words: [word]))
        }
        return LyricsDocument(groups: groups, title: "Incremental layout", duration: Double(count * 3), diagnostics: [])
    }

    @MainActor
    private func view(width: Double = 760) -> LyricsView {
        let view = LyricsView(frame: NSRect(x: 0, y: 0, width: width, height: 720))
        view.automaticDisplayUpdates = false
        view.configuration.timing.enabled = false
        view.configuration.spring = false
        return view
    }

    @MainActor
    func testDeepInstallationShapesFocusBeforeTheWholeSong() {
        let view = view()
        view.install(document: document(), time: 211, hostTime: 0)
        let first = view.render(at: 0)
        XCTAssertEqual(first.timeline.focus, 70)
        XCTAssertEqual(first.groups.map(\.index), Array(0..<100))
        XCTAssertLessThan(first.layoutCount, 100)
        XCTAssertGreaterThan(first.groups[70].height, view.configuration.fontSize * 2)

        // The time budget guarantees one row per render even on a slow host.
        for frame in 1...100 { view.render(at: Double(frame) / 60) }
        XCTAssertEqual(view.render(at: 2).layoutCount, 100)
        view.releaseRenderingResources()
    }

    @MainActor
    func testEntryPrewarmsOneUpcomingRowPerTickAfterInstallation() {
        let view = view()
        view.configuration.spring = true
        view.install(document: document(count: 20, longLines: false), hostTime: 0)
        XCTAssertEqual(view.glyphContentGroupIndices, [0])

        // Reflow is also budgeted by wall time, so use display-frame spacing
        // and let the initial layouts reach the prewarm queue before asserting.
        var previous = view.glyphContentGroupIndices
        for frame in 1...60 {
            let result = view.render(at: Double(frame) / 60)
            let current = view.glyphContentGroupIndices
            let added = current.filter { !previous.contains($0) }
            XCTAssertLessThanOrEqual(added.count, 1, "entry should shape at most one upcoming row per tick")
            for index in added {
                let row = result.groups.first { $0.index == index }
                XCTAssertGreaterThan(
                    try XCTUnwrap(row).y,
                    Double(view.bounds.height),
                    "row \(index) should be prewarmed before entering the viewport"
                )
            }
            previous = current
            if (0...2).allSatisfy(current.contains) { break }
        }
        XCTAssertEqual(Array(view.glyphContentGroupIndices.prefix(3)), [0, 1, 2])
        view.releaseRenderingResources()
    }

    @MainActor
    func testResizeDuringInstallationReflowsExistingRowsAtTheNewWidth() {
        let view = view()
        let document = document()
        view.install(document: document, hostTime: 0)
        view.setFrameSize(NSSize(width: 360, height: 720))
        for frame in 1...100 { view.render(at: Double(frame) / 60) }
        let resized = view.render(at: 2)

        let reference = self.view(width: 360)
        reference.install(document: document, hostTime: 0)
        for frame in 1...100 { reference.render(at: Double(frame) / 60) }
        let expected = reference.render(at: 2)
        XCTAssertEqual(resized.groups.count, expected.groups.count)
        for (actual, expected) in zip(resized.groups, expected.groups) {
            XCTAssertEqual(actual.height, expected.height, accuracy: 0.001)
        }
        view.releaseRenderingResources()
        reference.releaseRenderingResources()
    }

    @MainActor
    func testSeekAndReplacementDiscardThePreviousPendingWork() {
        let view = view()
        view.install(document: document(), hostTime: 0)
        view.synchronize(time: 241, playing: false, seek: true, hostTime: 0)
        let sought = view.render(at: 0)
        XCTAssertEqual(sought.timeline.focus, 80)
        XCTAssertGreaterThan(sought.groups[80].height, view.configuration.fontSize * 2)

        view.install(document: document(count: 2), hostTime: 1)
        for frame in 1...5 { view.render(at: 1 + Double(frame) / 60) }
        XCTAssertEqual(view.render(at: 2).groups.map(\.index), [0, 1])
        view.clear(hostTime: 2)
        XCTAssertTrue(view.render(at: 3).groups.isEmpty)
        view.releaseRenderingResources()
    }

    @MainActor
    func testSeekDuringIncrementalInstallationPrioritizesTheNewFocus() {
        let view = view()
        view.install(document: document(), hostTime: 0)
        view.render(at: 1.0 / 60.0)

        XCTAssertFalse(view.glyphContentGroupIndices.contains(80))

        view.synchronize(time: 241, playing: false, seek: true, hostTime: 2.0 / 60.0)
        let sought = view.render(at: 2.0 / 60.0)

        XCTAssertEqual(sought.timeline.focus, 80)
        XCTAssertGreaterThan(sought.groups[80].height, view.configuration.fontSize * 2)
        XCTAssertTrue(view.glyphContentGroupIndices.contains(80))
        view.releaseRenderingResources()
    }
}
