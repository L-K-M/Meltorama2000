import AppKit
import ImageIO
import MeltoramaCore
import XCTest
@testable import MeltoramaMac

final class ExtremeInputTests: XCTestCase {
    private func fixture(width: Int, height: Int) throws -> Data {
        let pixels = Data(repeating: 255, count: width * height * 4)
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                        bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                        provider: CGDataProvider(data: pixels as CFData)!, decode: nil,
                                        shouldInterpolate: true, intent: .defaultIntent))
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return encoded as Data
    }

    private func requireGPU() throws {
        do { _ = try WarpEngine() }
        catch WarpError.unavailable {
            throw XCTSkip("The process has no macOS GPU context. Run extreme canvas tests on a logged-in Mac outside the filesystem sandbox.")
        }
    }

    func testImageIOAcceptsExtremeSourcesAndBoundsTheirPreviewDecode() throws {
        for (width, height) in [(65535, 1), (1, 65535)] {
            let data = try fixture(width: width, height: height)
            XCTAssertEqual(try WarpEngine.imageSize(data: data), CGSize(width: width, height: height))
            let thumbnail = try WarpEngine.decodedImage(data: data, maxDimension: 2048)
            XCTAssertEqual(thumbnail.width, width > height ? 2048 : 1)
            XCTAssertEqual(thumbnail.height, height > width ? 2048 : 1)
        }
    }

    @MainActor func testExtremeSourcesKeepCanvasDragAndCommittedStrokeBounded() async throws {
        _ = NSApplication.shared
        try requireGPU()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("extreme-input-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for (width, height) in [(65535, 1), (1, 65535)] {
            let document = GooDocument(), session = document.session
            let undo = try XCTUnwrap(document.undoManager)
            undo.groupsByEvent = false
            session.recoveryURL = folder.appendingPathComponent("\(width)x\(height)-recovery.meltorama")
            defer { session.stopTimers(); session.removeRecovery() }
            session.source = try fixture(width: width, height: height)
            session.imageSize = try WarpEngine.imageSize(data: session.source)
            document.updateChangeCount(.changeCleared)
            let original = session.state
            session.updateViewport(size: CGSize(width: 900, height: 700), backingScale: 2)
            session.zoom = 0.1
            session.tool = .smear
            session.radius = 0.01
            session.sectors = 12
            session.mirrored = true
            let rect = CanvasGeometry.imageRect(image: session.imageSize, viewport: session.viewportSize,
                                               zoom: session.zoom, pan: .zero)
            let screenStart = CGPoint(x: rect.midX, y: rect.midY)
            let screenEnd = CGPoint(x: rect.midX + (height > width ? 100 : 0),
                                    y: rect.midY + (width > height ? 100 : 0))
            let start = CanvasGeometry.sourcePoint(screenStart, imageRect: rect, rotation: 0)
            let end = CanvasGeometry.sourcePoint(screenEnd, imageRect: rect, rotation: 0)
            XCTAssertEqual(start.x, 0.5, accuracy: 0.000001)
            XCTAssertEqual(start.y, 0.5, accuracy: 0.000001)

            session.beginStroke(start, displayHeight: rect.height)
            session.extendStroke(end, displayHeight: rect.height)
            let active = try XCTUnwrap(session.activeStroke)
            XCTAssertFalse(active.stamps.isEmpty)
            // The per-event budget bounds the resampler before 24-way symmetry.
            XCTAssertLessThanOrEqual(active.stamps.count, 4096 * 24)
            XCTAssertTrue(active.stamps.allSatisfy(\.isFinite))
            if width > height {
                let finalPrimary = try XCTUnwrap(active.stamps.dropLast(23).last)
                XCTAssertEqual(finalPrimary.cx, Float(end.x), accuracy: 0.02)
                XCTAssertEqual(finalPrimary.cy, Float(end.y), accuracy: 0.02)
            }
            undo.beginUndoGrouping()
            session.finishStroke()
            undo.endUndoGrouping()
            XCTAssertNil(session.activeStroke)
            XCTAssertEqual(try session.state.log.materialize().first, active)
            XCTAssertNoThrow(try session.state.validate())
            let committed = session.state
            XCTAssertTrue(document.isDocumentEdited)
            XCTAssertTrue(undo.canUndo)
            undo.undo()
            // Immutable revisions remain reachable after undo. The live
            // cursor and editing state must return to the original document.
            XCTAssertEqual(session.state.log.history, original.log.history)
            XCTAssertEqual(session.state.log.cursor, original.log.cursor)
            XCTAssertEqual(try session.state.log.materialize(), try original.log.materialize())
            XCTAssertEqual(session.state.globals, original.globals)
            XCTAssertEqual(session.state.crop, original.crop)
            XCTAssertEqual(session.state.keyframes, original.keyframes)
            XCTAssertFalse(document.isDocumentEdited)
            XCTAssertTrue(undo.canRedo)
            undo.redo()
            XCTAssertEqual(session.state, committed)
            XCTAssertEqual(try session.state.log.materialize(), [active], "Redo must restore every bounded stamp and its exact delta")
            XCTAssertTrue(document.isDocumentEdited)

            let url = folder.appendingPathComponent("\(width)x\(height).meltorama")
            try document.fileWrapper(ofType: "ch.lkmc.goo.project").write(to: url, options: .atomic, originalContentsURL: nil)
            let reopened = GooDocument()
            reopened.session.recoveryURL = folder.appendingPathComponent("\(width)x\(height)-reopened-recovery.meltorama")
            defer { reopened.session.stopTimers(); reopened.session.removeRecovery() }
            try reopened.read(from: FileWrapper(url: url, options: .immediate), ofType: "ch.lkmc.goo.project")
            XCTAssertEqual(reopened.session.source, session.source)
            XCTAssertEqual(reopened.session.imageSize, session.imageSize)
            XCTAssertEqual(reopened.session.state.log, committed.log)
            let restored = try reopened.session.state.log.materialize()
            XCTAssertEqual(restored, [active], "Saving and reopening must preserve all stamp coordinates and deltas")
            XCTAssertTrue(restored.flatMap(\.stamps).allSatisfy(\.isFinite))
            XCTAssertNoThrow(try reopened.session.state.validate())

            let deadline = Date().addingTimeInterval(10)
            while session.image == nil, session.error == nil, Date() < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTAssertNil(session.error)
            let preview = try XCTUnwrap(session.image, "The bounded edit must finish its native GPU preview")
            XCTAssertEqual(preview.width, width > height ? 1400 : 1)
            XCTAssertEqual(preview.height, height > width ? 1400 : 1)
        }
    }
}
