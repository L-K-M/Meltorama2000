import MeltoramaCore
import XCTest
@testable import MeltoramaMac

final class FrameThumbnailTests: XCTestCase {
    func testPinnedThumbnailIncludesDetachedRewindTarget() throws {
        var log = StrokeLog()
        try log.push(Stroke(tool: .smear, radius: 0.2, strength: 1,
                            stamps: [Stamp(cx: 0.4, cy: 0.5, dx: 0.05, dy: 0)]))
        let target = log.currentRevision
        try log.reset()
        try log.push(Stroke(tool: .rewind, radius: 0.2, strength: 1,
                            stamps: [Stamp(cx: 0.5, cy: 0.5)], targetRevision: target))
        let pin = KeyframeRecord(revision: log.currentRevision, globals: GlobalParams(twirl: 0.4))
        let source = Data([1, 2, 3])
        let request = FrameThumbnailRequest(document: ProjectDocument(log: log.snapshot(pins: [pin.revision])),
                                            source: source, fusion: nil, pin: pin)
        let thumbnail = try FrameThumbnailRenderer.pinnedDocument(for: request)
        try thumbnail.validate()
        XCTAssertTrue(thumbnail.log.revisions.contains { $0.id == target })
        XCTAssertEqual(thumbnail.globals, pin.globals)
        XCTAssertEqual(thumbnail.log.currentRevision, pin.revision)
    }

    func testUnrelatedLiveEditsDoNotChangeThePinnedThumbnailDocument() throws {
        var log = StrokeLog()
        try log.push(Stroke(tool: .grow, radius: 0.2, strength: 1,
                            stamps: [Stamp(cx: 0.4, cy: 0.5)]))
        let pin = KeyframeRecord(revision: log.currentRevision)
        let original = ProjectDocument(log: log.snapshot(pins: [pin.revision]))
        try log.push(Stroke(tool: .shrink, radius: 0.2, strength: 1,
                            stamps: [Stamp(cx: 0.6, cy: 0.5)]))
        let edited = ProjectDocument(globals: GlobalParams(twirl: 0.7), log: log.snapshot(pins: [pin.revision]))
        let first = try FrameThumbnailRenderer.pinnedDocument(for: FrameThumbnailRequest(document: original,
                                                source: Data(), fusion: nil, pin: pin))
        let second = try FrameThumbnailRenderer.pinnedDocument(for: FrameThumbnailRequest(document: edited,
                                                 source: Data(), fusion: nil, pin: pin))
        XCTAssertEqual(first, second)
    }
}
