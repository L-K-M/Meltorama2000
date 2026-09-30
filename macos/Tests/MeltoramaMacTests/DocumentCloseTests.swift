import AppKit
import MeltoramaCore
import XCTest
@testable import MeltoramaMac

@MainActor private final class DocumentCloseProbe: NSObject {
    let completion = XCTestExpectation(description: "Document close decision")
    private(set) var allowed = false

    @objc func document(_ document: NSDocument, shouldClose: Bool, contextInfo: UnsafeMutableRawPointer?) {
        allowed = shouldClose
        completion.fulfill()
    }
}

final class DocumentCloseTests: XCTestCase {
    @MainActor private func savedDocument(at url: URL, globals: GlobalParams = GlobalParams()) throws -> GooDocument {
        _ = NSApplication.shared
        let sample = try XCTUnwrap(ResourceBundle.url(forResource: "goo-guy", withExtension: "png"))
        let package = ProjectPackage(document: ProjectDocument(globals: globals), sourceData: try Data(contentsOf: sample))
        try package.write(to: url)
        let document = GooDocument()
        document.session.recoveryURL = url.deletingLastPathComponent().appendingPathComponent("Recovery.meltorama")
        try document.read(from: package.fileWrapper(), ofType: "ch.lkmc.goo.project")
        document.fileType = "ch.lkmc.goo.project"
        document.fileURL = url
        document.updateChangeCount(.changeCleared)
        return document
    }

    @MainActor private func approveClose(_ document: GooDocument) async {
        let probe = DocumentCloseProbe()
        document.canClose(withDelegate: probe,
                          shouldClose: #selector(DocumentCloseProbe.document(_:shouldClose:contextInfo:)),
                          contextInfo: nil)
        await fulfillment(of: [probe.completion], timeout: 10)
        XCTAssertTrue(probe.allowed)
    }

    @MainActor func testCloseSavesAnActiveGestureBeforeApprovingTheDocument() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("close-gesture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Photo.meltorama")
        let document = try savedDocument(at: url), session = document.session
        defer { session.stopTimers(); session.removeRecovery() }
        session.tool = .grow
        session.beginStroke(CGPoint(x: 0.4, y: 0.5))
        XCTAssertTrue(session.activeStroke?.hasContent == true)
        XCTAssertFalse(document.isDocumentEdited, "A gesture has not entered the stroke log yet")

        await approveClose(document)
        XCTAssertNil(session.activeStroke, "The close decision must first commit the pending gesture")
        let saved = try ProjectPackage.read(url: url)
        XCTAssertEqual(try saved.document.log.materialize().count, 1,
                       "AppKit must save the pending stroke before approving close")
    }

    @MainActor func testCloseSavesAnActiveLensDragBeforeApprovingTheDocument() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("close-lens-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Photo.meltorama")
        let document = try savedDocument(at: url, globals: GlobalParams(lenses: [Lens(u: 0.4, v: 0.5)]))
        let session = document.session
        defer { session.stopTimers(); session.removeRecovery() }
        session.mode = .lenses
        session.beginStroke(CGPoint(x: 0.4, y: 0.5))
        session.extendStroke(CGPoint(x: 0.7, y: 0.6))
        XCTAssertFalse(document.isDocumentEdited)
        await approveClose(document)
        let saved = try ProjectPackage.read(url: url)
        XCTAssertEqual(saved.document.globals.lenses.first?.u, 0.7)
        XCTAssertEqual(saved.document.globals.lenses.first?.v, 0.6)
    }

    @MainActor func testClosingACleanDocumentDoesNotCreateAnEdit() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("close-clean-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Photo.meltorama")
        let document = try savedDocument(at: url), session = document.session
        defer { session.stopTimers(); session.removeRecovery() }
        let before = session.state
        await approveClose(document)
        XCTAssertFalse(document.isDocumentEdited)
        XCTAssertEqual(session.state, before)
        XCTAssertFalse(document.undoManager?.canUndo == true)
    }
}
