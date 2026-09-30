import AppKit
import AVFoundation
import ImageIO
import MeltoramaCore
import XCTest
@testable import MeltoramaMac

final class NativeSharingTests: XCTestCase {
    @MainActor func testPickerAnchorUsesTheTopRightInBothViewCoordinateSystems() {
        let bounds = NSRect(x: 10, y: 20, width: 320, height: 240)
        let native = NativeSharingCoordinator.pickerAnchor(bounds: bounds, isFlipped: false)
        let hosting = NativeSharingCoordinator.pickerAnchor(bounds: bounds, isFlipped: true)
        XCTAssertEqual(native.rect.maxX, bounds.maxX - 20)
        XCTAssertEqual(hosting.rect.maxX, native.rect.maxX)
        XCTAssertGreaterThan(native.rect.minY, bounds.midY)
        XCTAssertLessThan(hosting.rect.maxY, bounds.midY)
        XCTAssertEqual(native.edge, .minY)
        XCTAssertEqual(hosting.edge, .maxY)
        XCTAssertTrue(bounds.contains(native.rect))
        XCTAssertTrue(bounds.contains(hosting.rect))
    }
    @MainActor private func window() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        return window
    }

    @MainActor private func prepared() throws -> NativeSharingCoordinator {
        let coordinator = try NativeSharingCoordinator(format: .png, name: "Photo.meltorama")
        try Data("private sharing output".utf8).write(to: coordinator.fileURL)
        return coordinator
    }

    @MainActor private func inertService() -> NSSharingService {
        NSSharingService(title: "Test service", image: NSImage(size: NSSize(width: 1, height: 1)),
                         alternateImage: nil) { XCTFail("Lifecycle tests must never perform a sharing service") }
    }

    private func requireGPU() throws {
        do { _ = try WarpEngine() }
        catch WarpError.unavailable { throw XCTSkip("The process has no Mac GPU context for sharing encoder tests.") }
    }

    private func source() throws -> Data {
        let sample = try XCTUnwrap(ResourceBundle.url(forResource: "goo-guy", withExtension: "png"))
        let image = try WarpEngine.decodedImage(data: Data(contentsOf: sample), maxDimension: 128)
        let bytes = NSMutableData()
        let encoder = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(encoder, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(encoder))
        return bytes as Data
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

    @MainActor func testPreparedOutputsAreUniquePrivateAndUseTheirFormatExtension() throws {
        var directories = Set<URL>()
        for format in ExportFormat.allCases {
            let coordinator = try NativeSharingCoordinator(format: format, name: "../Photo.meltorama")
            XCTAssertTrue(directories.insert(coordinator.directory).inserted)
            XCTAssertEqual(coordinator.fileURL.deletingLastPathComponent(), coordinator.directory)
            XCTAssertEqual(coordinator.fileURL.lastPathComponent, "Photo.\(format.fileExtension)")
            let attributes = try FileManager.default.attributesOfItem(atPath: coordinator.directory.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o700)
            XCTAssertFalse(coordinator.directory.path.hasPrefix(EditorSession.recoveryDirectory.path))
            coordinator.cancelBeforeSharing()
            XCTAssertFalse(FileManager.default.fileExists(atPath: coordinator.directory.path))
        }
    }

    @MainActor func testPickerDismissalCleansFilesExactlyOnce() async throws {
        let coordinator = try prepared(), window = window()
        defer { window.close() }
        var picker: NSSharingServicePicker?, completions = 0
        coordinator.onCompletion = { outcome in
            if case .cancelled = outcome { completions += 1 } else { XCTFail("Expected picker cancellation") }
        }
        try await coordinator.present(in: window) { shown, rect, view in
            picker = shown
            XCTAssertTrue(view.window === window)
            XCTAssertTrue(view.bounds.contains(rect))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: coordinator.fileURL.path))
        let shown = try XCTUnwrap(picker)
        coordinator.sharingServicePicker(shown, didChoose: nil)
        coordinator.sharingServicePicker(shown, didChoose: nil)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(coordinator.stage, .finished)
        XCTAssertFalse(FileManager.default.fileExists(atPath: coordinator.directory.path))
    }

    @MainActor func testChosenServiceRetainsFileAfterWindowCloseUntilItsCompletion() async throws {
        var coordinator: NativeSharingCoordinator? = try prepared()
        let file = try XCTUnwrap(coordinator?.fileURL), directory = try XCTUnwrap(coordinator?.directory)
        let window = window(), service = inertService()
        var picker: NSSharingServicePicker?, completions = 0
        coordinator?.onCompletion = { outcome in
            if case .shared = outcome { completions += 1 } else { XCTFail("Expected service completion") }
        }
        try await coordinator?.present(in: window) { shown, _, _ in picker = shown }
        let shown = try XCTUnwrap(picker)
        XCTAssertTrue(coordinator?.sharingServicePicker(shown, delegateFor: service) === coordinator)
        coordinator?.sharingServicePicker(shown, didChoose: service)
        coordinator?.sharingServicePicker(shown, didChoose: nil)
        window.close()
        await Task.yield()
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        weak var retained = coordinator
        coordinator = nil
        XCTAssertNotNil(retained, "Weak AppKit delegates require explicit ownership through service completion")
        retained?.sharingService(service, didShareItems: [file])
        XCTAssertEqual(completions, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertNil(retained)
    }

    @MainActor func testServiceFailureAndWindowCloseBeforeChoiceCleanTheirFiles() async throws {
        let coordinator = try prepared(), window = window(), service = inertService()
        defer { window.close() }
        var picker: NSSharingServicePicker?, failure: Error?
        coordinator.onCompletion = { if case .failed(let error) = $0 { failure = error } }
        try await coordinator.present(in: window) { shown, _, _ in picker = shown }
        coordinator.sharingServicePicker(try XCTUnwrap(picker), didChoose: service)
        let expected = NSError(domain: "SharingTest", code: 42)
        coordinator.sharingService(service, didFailToShareItems: [coordinator.fileURL], error: expected)
        XCTAssertEqual((failure as NSError?)?.code, 42)
        XCTAssertFalse(FileManager.default.fileExists(atPath: coordinator.directory.path))

        let cancelled = try prepared()
        try await cancelled.present(in: window) { _, _, _ in }
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        for _ in 0..<20 where cancelled.stage != .finished { await Task.yield() }
        XCTAssertEqual(cancelled.stage, .finished)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cancelled.directory.path))
    }

    @MainActor func testCancellingAChosenServiceCleansFilesWithoutReportingFailure() async throws {
        let coordinator = try prepared(), window = window(), service = inertService()
        defer { window.close() }
        var picker: NSSharingServicePicker?, cancelled = false
        coordinator.onCompletion = {
            if case .cancelled = $0 { cancelled = true } else { XCTFail("User cancellation must not become a failure alert") }
        }
        try await coordinator.present(in: window) { shown, _, _ in picker = shown }
        coordinator.sharingServicePicker(try XCTUnwrap(picker), didChoose: service)
        coordinator.sharingService(service, didFailToShareItems: [coordinator.fileURL],
            error: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        XCTAssertTrue(cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: coordinator.directory.path))
    }

    @MainActor func testShareEncodesAllFormatsFromTheCommittedImmutableSnapshot() async throws {
        try requireGPU()
        let document = GooDocument(), session = document.session, window = window()
        defer { session.stopTimers(); session.removeRecovery(); window.close() }
        session.source = try source()
        session.imageSize = try WarpEngine.imageSize(data: session.source)
        for format in ExportFormat.allCases {
            session.state = ProjectDocument(globals: GlobalParams(twirl: 0.25),
                keyframes: [KeyframeRecord(revision: 0), KeyframeRecord(revision: 0)])
            session.tool = .grow
            session.beginStroke(CGPoint(x: 0.3, y: 0.4))
            var picker: NSSharingServicePicker?
            let task = try XCTUnwrap(session.share(options: ExportOptions(format: format), from: window,
                                                   presentation: { shown, _, _ in picker = shown }))
            XCTAssertNil(session.activeStroke)
            let snapshot = session.state
            session.state.globals.twirl = 0.8
            let coordinator = try XCTUnwrap(session.sharingCoordinator)
            await task.value
            XCTAssertNil(session.error)
            XCTAssertNil(session.progress)
            XCTAssertNil(session.activeExportID)
            XCTAssertFalse(session.canShare)
            XCTAssertTrue(session.canExport)
            XCTAssertEqual(coordinator.stage, .picking)
            XCTAssertTrue(FileManager.default.fileExists(atPath: coordinator.fileURL.path))
            if format == .mp4 {
                let asset = AVURLAsset(url: coordinator.fileURL)
                let tracks = try await asset.loadTracks(withMediaType: .video)
                XCTAssertEqual(tracks.count, 1)
            } else {
                let decoder = try XCTUnwrap(CGImageSourceCreateWithURL(coordinator.fileURL as CFURL, nil))
                let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoder, 0, nil))
                XCTAssertEqual(image.width, 128); XCTAssertEqual(image.height, 96)
                if format == .png {
                    let source = session.source
                    let expected = try await Task.detached {
                        try ExportService.renderStill(document: snapshot, source: source, fusion: nil)
                    }.value
                    XCTAssertEqual(try pixels(image), try pixels(expected))
                }
            }
            coordinator.sharingServicePicker(try XCTUnwrap(picker), didChoose: nil)
            XCTAssertNil(session.sharingCoordinator)
            XCTAssertTrue(session.canShare)
            XCTAssertFalse(FileManager.default.fileExists(atPath: coordinator.directory.path))
        }
    }

    @MainActor func testCancelledShareEncodingCleansPrivateOutputAndNeverPresentsAService() async throws {
        try requireGPU()
        let document = GooDocument(), session = document.session, window = window()
        defer { session.stopTimers(); session.removeRecovery(); window.close() }
        session.source = try source()
        session.state.keyframes = Array(repeating: KeyframeRecord(revision: 0), count: 64)
        let task = try XCTUnwrap(session.share(options: ExportOptions(format: .mp4, speed: .half), from: window,
            presentation: { _, _, _ in XCTFail("A cancelled encoder must not open sharing") }))
        let directory = try XCTUnwrap(session.sharingCoordinator?.directory)
        for _ in 0..<1000 where (session.progress ?? 0) == 0 { try await Task.sleep(nanoseconds: 1_000_000) }
        XCTAssertGreaterThan(session.progress ?? 0, 0)
        session.cancelExport()
        XCTAssertFalse(session.canExport)
        await task.value
        XCTAssertNil(session.error)
        XCTAssertNil(session.sharingCoordinator)
        XCTAssertTrue(session.canShare)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor func testFailedShareEncodingCleansPrivateOutputAndReportsAnError() async throws {
        let document = GooDocument(), session = document.session, window = window()
        defer { session.stopTimers(); window.close() }
        session.source = Data("not a photo".utf8)
        let task = try XCTUnwrap(session.share(options: ExportOptions(), from: window,
            presentation: { _, _, _ in XCTFail("A failed encoder must not open sharing") }))
        let directory = try XCTUnwrap(session.sharingCoordinator?.directory)
        await task.value
        XCTAssertNotNil(session.error)
        XCTAssertNil(session.sharingCoordinator)
        XCTAssertNil(session.progress)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    @MainActor func testUnavailableAnchorCleansFilesAndReleasesWaitingLifetime() async throws {
        var coordinator: NativeSharingCoordinator? = try prepared()
        let directory = try XCTUnwrap(coordinator?.directory), window = window()
        defer { window.close() }
        window.orderOut(nil)
        do {
            try await coordinator?.present(in: window) { _, _, _ in XCTFail("A hidden document cannot anchor sharing") }
            XCTFail("Expected an unavailable-window cancellation")
        } catch is CancellationError { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        weak var released = coordinator
        coordinator = nil
        XCTAssertNil(released)
    }
}
