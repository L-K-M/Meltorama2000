import AppKit
import ImageIO
import MeltoramaCore
import XCTest
@testable import MeltoramaMac

final class CopyImageTests: XCTestCase {
    private func requireGPU() throws {
        do { _ = try WarpEngine() }
        catch WarpError.unavailable {
            throw XCTSkip("The process has no macOS GPU context. Run Copy Image boundary tests on a logged-in Mac outside the filesystem sandbox.")
        }
    }

    private func source() throws -> Data {
        let url = try XCTUnwrap(ResourceBundle.url(forResource: "goo-guy", withExtension: "png"))
        return try Data(contentsOf: url)
    }

    private func pixels(_ image: CGImage) throws -> Data {
        var bytes = Data(count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    @MainActor private func pasteboard() throws -> NSPasteboard {
        _ = NSApplication.shared
        let board = NSPasteboard.withUniqueName()
        guard board.setString("existing clipboard", forType: .string) else {
            throw XCTSkip("The process has no macOS pasteboard service.")
        }
        return board
    }

    @MainActor func testCopyRendersFullLiveDocumentAndExcludesCachedPreviewAndTransientModes() async throws {
        try requireGPU()
        let document = GooDocument(), session = document.session
        let board = try pasteboard()
        defer { session.stopTimers(); board.releaseGlobally() }
        session.source = try source()
        session.imageSize = try WarpEngine.imageSize(data: session.source)
        var log = StrokeLog()
        try log.push(Stroke(tool: .freeze, radius: 0.2, strength: 1,
                            stamps: [Stamp(cx: 0.45, cy: 0.45, dx: 0, dy: 0)]))
        session.state = ProjectDocument(globals: GlobalParams(twirl: 0.35), log: log.snapshot(pins: [0]),
                                       keyframes: [KeyframeRecord(revision: 0)])
        session.tool = .grow
        session.beginStroke(CGPoint(x: 0.3, y: 0.4), displayHeight: 600)
        XCTAssertTrue(session.activeStroke?.hasContent == true)
        session.image = try WarpEngine.decodedImage(data: session.source, maxDimension: 16)
        session.tool = .freeze
        session.compareOriginal = true
        session.live = false
        session.selectedKeyframe = 0
        let task = try XCTUnwrap(session.copyImage(to: board))
        XCTAssertNil(session.activeStroke)
        await task.value
        XCTAssertNil(session.error)
        let clipboard = try XCTUnwrap(board.data(forType: .tiff))
        let decoder = try XCTUnwrap(CGImageSourceCreateWithData(clipboard as CFData, nil))
        let copied = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoder, 0, nil))
        XCTAssertEqual(copied.width, Int(session.imageSize.width))
        XCTAssertEqual(copied.height, Int(session.imageSize.height))

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let png = folder.appendingPathComponent("still.png")
        _ = try await ExportService.export(document: session.state, source: session.source, fusion: session.fusion,
                                            options: ExportOptions(format: .png), to: png)
        let expectedSource = try XCTUnwrap(CGImageSourceCreateWithURL(png as CFURL, nil))
        let expected = try XCTUnwrap(CGImageSourceCreateImageAtIndex(expectedSource, 0, nil))
        XCTAssertEqual(try pixels(copied), try pixels(expected))
    }

    @MainActor func testFailedCopyPreservesExistingClipboardAndReportsError() async throws {
        let document = GooDocument(), session = document.session
        let board = try pasteboard()
        defer { session.stopTimers(); board.releaseGlobally() }
        session.image = try WarpEngine.decodedImage(data: source(), maxDimension: 16)
        session.source = Data("invalid image".utf8)
        let previousCount = board.changeCount
        let task = try XCTUnwrap(session.copyImage(to: board))
        await task.value
        XCTAssertEqual(board.changeCount, previousCount)
        XCTAssertEqual(board.string(forType: .string), "existing clipboard")
        XCTAssertNotNil(session.error)
    }
}
