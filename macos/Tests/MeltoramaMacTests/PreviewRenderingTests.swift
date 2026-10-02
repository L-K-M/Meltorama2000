import AppKit
import ImageIO
import MeltoramaCore
import XCTest
@testable import MeltoramaMac

final class PreviewRenderingTests: XCTestCase {
    @MainActor private final class ControlledWorker {
        struct Job {
            let request: EditorSession.PreviewRequest
            let completion: (Result<CGImage, Error>) -> Void
        }
        var jobs: [Job] = []
        func render(_ request: EditorSession.PreviewRequest,
                    completion: @escaping (Result<CGImage, Error>) -> Void) {
            jobs.append(Job(request: request, completion: completion))
        }
        func finish(_ index: Int, with image: CGImage) {
            jobs[index].completion(.success(image))
        }
        func fail(_ index: Int) { jobs[index].completion(.failure(PreviewFailure())) }
    }

    private struct PreviewFailure: LocalizedError {
        var errorDescription: String? { "Obsolete preview failed" }
    }

    private func image(_ shade: UInt8) throws -> CGImage {
        let bytes = Data([shade, 0, 0, 255])
        return try XCTUnwrap(CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: bytes as CFData)!, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent))
    }

    private func source() throws -> Data {
        let data = NSMutableData()
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, try image(127), nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        return data as Data
    }

    @MainActor private func session(_ worker: ControlledWorker) -> EditorSession {
        let session = EditorSession(renderPreview: worker.render)
        // The controlled worker owns rendering; these bytes only identify a source.
        session.source = Data([1])
        session.imageSize = CGSize(width: 100, height: 80)
        return session
    }

    private func finishMainQueueTurn() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    @MainActor func testContinuousInputPublishesCompletedFramesAndCoalescesLatestRequest() async throws {
        let worker = ControlledWorker(), session = session(worker)
        let first = try image(20), second = try image(40), latest = try image(60)
        session.requestRender()
        for value in 1...100 {
            session.state.globals.twirl = Float(value) / 100
            session.requestRender()
        }
        XCTAssertEqual(worker.jobs.count, 1, "Only one preview may execute at a time")
        worker.finish(0, with: first)
        await finishMainQueueTurn()
        XCTAssertTrue(session.image === first, "Continuing input must not starve completed frames")
        XCTAssertEqual(worker.jobs.count, 2)
        XCTAssertEqual(worker.jobs[1].request.document.globals.twirl, 1)

        session.state.globals.twirl = 0.25
        session.requestRender()
        worker.finish(1, with: second)
        await finishMainQueueTurn()
        XCTAssertTrue(session.image === second)
        XCTAssertEqual(worker.jobs.count, 3)
        XCTAssertEqual(worker.jobs[2].request.document.globals.twirl, 0.25)

        worker.finish(2, with: latest)
        await finishMainQueueTurn()
        XCTAssertTrue(session.image === latest)
        XCTAssertEqual(worker.jobs.count, 3)
        XCTAssertFalse(session.rendering)
    }

    @MainActor func testContinuousStrokeShowsProgressBeforePointerInputStops() async throws {
        let worker = ControlledWorker(), session = session(worker)
        let progress = try image(10), final = try image(80)
        session.activeStroke = Stroke(tool: .smear, radius: 0.12, strength: 0.8,
                                      stamps: [Stamp(cx: 0.3, cy: 0.4, dx: 0.01, dy: 0)])
        session.requestRender()
        for _ in 0..<50 {
            session.activeStroke?.stamps.append(Stamp(cx: 0.4, cy: 0.4, dx: 0.01, dy: 0))
            session.requestRender()
        }
        worker.finish(0, with: progress)
        await finishMainQueueTurn()
        XCTAssertTrue(session.image === progress)
        XCTAssertEqual(worker.jobs.count, 2)
        XCTAssertEqual(worker.jobs[0].request.activeStroke?.stamps.count, 1)
        XCTAssertEqual(worker.jobs[1].request.activeStroke?.stamps.count, 51)
        worker.finish(1, with: final)
        await finishMainQueueTurn()
        XCTAssertTrue(session.image === final)
    }

    @MainActor func testSourceFusionCropAndCompareChangesDiscardObsoleteResultsAndErrors() async throws {
        let changes: [(String, (EditorSession) -> Void)] = [
            ("source", { $0.source = Data([2]) }),
            ("fusion", { $0.fusion = Data([3]) }),
            ("crop", { $0.state.crop = CropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9) }),
            ("compare", { $0.compareOriginal = true }),
            ("freeze visualization", { $0.tool = .freeze })
        ]
        for (name, change) in changes {
            for fails in [false, true] {
                let worker = ControlledWorker(), session = session(worker)
                let shown = try image(10), obsolete = try image(20), latest = try image(30)
                session.image = shown
                session.requestRender()
                change(session)
                session.requestRender()
                if fails { worker.fail(0) } else { worker.finish(0, with: obsolete) }
                await finishMainQueueTurn()
                XCTAssertTrue(session.image === shown, name)
                XCTAssertNil(session.error, name)
                XCTAssertEqual(worker.jobs.count, 2, name)
                worker.finish(1, with: latest)
                await finishMainQueueTurn()
                XCTAssertTrue(session.image === latest, name)
            }
        }
    }

    @MainActor func testSameSourcePackageReplacementIncludingRevertDiscardsOldPreview() async throws {
        for fails in [false, true] {
            let worker = ControlledWorker(), session = session(worker)
            session.source = try source()
            session.state.globals.twirl = 0.75
            let shown = try image(10), obsolete = try image(20), latest = try image(30)
            session.image = shown
            session.requestRender()
            let restored = ProjectDocument(globals: GlobalParams(bulge: 0.2))
            session.replacePackage(ProjectPackage(document: restored, sourceData: session.source),
                                   name: "Saved Photo", markEdited: false)
            if fails { worker.fail(0) } else { worker.finish(0, with: obsolete) }
            await finishMainQueueTurn()
            XCTAssertTrue(session.image === shown)
            XCTAssertNil(session.error)
            XCTAssertEqual(worker.jobs.count, 2)
            XCTAssertEqual(worker.jobs[1].request.document, restored)
            worker.finish(1, with: latest)
            await finishMainQueueTurn()
            XCTAssertTrue(session.image === latest)
        }
    }

    @MainActor func testUndoAndResetDiscardOldPreviewWithoutChangingLatestState() async throws {
        _ = NSApplication.shared
        for reset in [false, true] {
            let worker = ControlledWorker(), session = session(worker)
            session.source = try source()
            let document = GooDocument()
            document.undoManager?.groupsByEvent = false
            session.document = document
            defer { session.stopTimers() }
            let shown = try image(10), obsolete = try image(20), latest = try image(30)
            session.image = shown
            document.undoManager?.beginUndoGrouping()
            session.edit("Twirl") { $0.globals.twirl = 0.5 }
            document.undoManager?.endUndoGrouping()
            if reset {
                document.undoManager?.beginUndoGrouping()
                session.resetGoo()
                document.undoManager?.endUndoGrouping()
            } else { document.undoManager?.undo() }
            XCTAssertEqual(session.state.globals.twirl, 0)
            worker.finish(0, with: obsolete)
            await finishMainQueueTurn()
            XCTAssertTrue(session.image === shown)
            XCTAssertEqual(worker.jobs.count, 2)
            XCTAssertEqual(worker.jobs[1].request.document.globals.twirl, 0)
            worker.finish(1, with: latest)
            await finishMainQueueTurn()
            XCTAssertTrue(session.image === latest)
        }
    }

    @MainActor func testTweenProgressPublishesWhileFrameSelectionAndLiveModeDiscardOldPreview() async throws {
        let worker = ControlledWorker(), session = session(worker)
        session.state.keyframes = [KeyframeRecord(revision: 0),
                                  KeyframeRecord(revision: 0, globals: GlobalParams(twirl: 0.5))]
        session.live = false
        let advancing = try image(10), selected = try image(20), live = try image(30)
        session.requestRender()
        session.scrub = 0.4
        session.requestRender()
        worker.finish(0, with: advancing)
        await finishMainQueueTurn()
        XCTAssertTrue(session.image === advancing, "An advancing animation must publish progress")
        XCTAssertEqual(worker.jobs.count, 2)

        session.selectFrame(1)
        worker.finish(1, with: selected)
        await finishMainQueueTurn()
        XCTAssertTrue(session.image === advancing, "Changing frame selection must not flash the old tween")
        XCTAssertEqual(worker.jobs.count, 3)
        session.live = true
        session.requestRender()
        worker.fail(2)
        await finishMainQueueTurn()
        XCTAssertNil(session.error, "Errors from a frame preview cannot affect the live document")
        XCTAssertEqual(worker.jobs.count, 4)
        XCTAssertNil(worker.jobs[3].request.tween)
        worker.finish(3, with: live)
        await finishMainQueueTurn()
        XCTAssertTrue(session.image === live)
    }

    @MainActor func testReplacingSourceAwayAndBackStillInvalidatesQueuedPreview() async throws {
        let worker = ControlledWorker(), session = session(worker)
        let shown = try image(10), obsolete = try image(20), latest = try image(30)
        session.image = shown
        session.requestRender()
        let source = session.source
        session.source = Data([99])
        session.requestRender()
        session.source = source
        session.requestRender()
        worker.finish(0, with: obsolete)
        await finishMainQueueTurn()
        XCTAssertTrue(session.image === shown)
        XCTAssertEqual(worker.jobs.count, 2)
        XCTAssertEqual(worker.jobs[1].request.source, source)
        worker.finish(1, with: latest)
        await finishMainQueueTurn()
        XCTAssertTrue(session.image === latest)
    }

    @MainActor func testOnlyTheLatestCompatibleErrorIsPresentedAndStoppingDiscardsCompletion() async throws {
        let worker = ControlledWorker(), session = session(worker)
        session.requestRender()
        session.state.globals.twirl = 0.1
        session.requestRender()
        worker.fail(0)
        await finishMainQueueTurn()
        XCTAssertNil(session.error)
        XCTAssertEqual(worker.jobs.count, 2)
        worker.fail(1)
        await finishMainQueueTurn()
        XCTAssertEqual(session.error, PreviewFailure().localizedDescription)

        session.error = nil
        let shown = try image(10), obsolete = try image(20)
        session.image = shown
        session.requestRender()
        session.state.globals.twirl = 0.2
        session.requestRender()
        session.stopTimers()
        worker.finish(2, with: obsolete)
        await finishMainQueueTurn()
        XCTAssertTrue(session.image === shown)
        XCTAssertEqual(worker.jobs.count, 3, "Closing the session must not start queued work")
        XCTAssertFalse(session.rendering)
    }

}
