import AppKit
import MeltoramaCore
import XCTest
@testable import MeltoramaMac

final class DocumentLifecycleTests: XCTestCase {
    @MainActor func testSuccessfulReadClearsRecoveryButFailedReadKeepsIt() async throws {
        _ = NSApplication.shared
        let document = GooDocument(), session = document.session
        let recovery = FileManager.default.temporaryDirectory.appendingPathComponent("read-recovery-\(UUID().uuidString).meltorama")
        defer { session.stopTimers(); try? FileManager.default.removeItem(at: recovery) }
        session.recoveryURL = recovery
        let sample = try XCTUnwrap(ResourceBundle.url(forResource: "goo-guy", withExtension: "png"))
        let package = ProjectPackage(document: ProjectDocument(), sourceData: try Data(contentsOf: sample), fusionData: nil)
        session.replacePackage(package, name: "Photo")
        session.writeRecovery()
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovery.path))
        XCTAssertThrowsError(try document.read(from: FileWrapper(directoryWithFileWrappers: [:]), ofType: "ch.lkmc.goo.project"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: recovery.path))
        try document.read(from: package.fileWrapper(), ofType: "ch.lkmc.goo.project")
        XCTAssertFalse(FileManager.default.fileExists(atPath: recovery.path))
        XCTAssertEqual(session.source, package.sourceData)
    }
}
