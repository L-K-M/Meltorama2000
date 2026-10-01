import AppKit
import MeltoramaCore
import SwiftUI
import XCTest
@testable import MeltoramaMac

private struct NumericBoundaryHost: View {
    @ObservedObject var session: EditorSession
    var body: some View {
        InspectorNumericField(title: "Amount", value: Binding(get: { session.state.globals.twirl }, set: { value in
            session.edit("Adjust Twirl") { $0.globals.twirl = value }
        }), range: -1...1, percent: true)
    }
}

final class NumericDocumentBoundaryTests: XCTestCase {
    @MainActor private func host(_ document: GooDocument) async throws -> (NSWindow, NSTextField) {
        _ = NSApplication.shared
        let view = NSHostingView(rootView: NumericBoundaryHost(session: document.session))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 160, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        document.addWindowController(NSWindowController(window: window))
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 30_000_000)
        func field(in view: NSView) -> NSTextField? {
            if let field = view as? NSTextField { return field }
            return view.subviews.lazy.compactMap { field(in: $0) }.first
        }
        return (window, try XCTUnwrap(field(in: view)))
    }

    @MainActor func testNativeEndEditingCommitsBeforeDocumentSerialization() async throws {
        let document = GooDocument()
        document.session.state.globals.twirl = 0.8
        let sample = try XCTUnwrap(ResourceBundle.url(forResource: "goo-guy", withExtension: "png"))
        document.session.source = try Data(contentsOf: sample)
        let (window, field) = try await host(document)
        defer { document.session.stopTimers(); window.close() }
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("45", replacementRange: editor.selectedRange())
        XCTAssertEqual(editor.string, "45")
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(document.session.state.globals.twirl, 0.8)
        window.endEditing(for: nil)
        let wrapper = try document.fileWrapper(ofType: "ch.lkmc.goo.project")
        let bytes = try XCTUnwrap(wrapper.fileWrappers?["project.json"]?.regularFileContents)
        let saved = try MeltoramaCore.ProjectDocument.decode(bytes)
        XCTAssertEqual(saved.globals.twirl, 0.45, accuracy: 0.000001)
    }

    @MainActor func testCommitForSaveOrExportPreservesFocusAndNativeTextUndo() async throws {
        let document = GooDocument()
        document.session.state.globals.twirl = 0.8
        let (window, field) = try await host(document)
        defer { document.session.stopTimers(); window.close() }
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("45", replacementRange: editor.selectedRange())
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(document.session.state.globals.twirl, 0.8)
        let undo = try XCTUnwrap(editor.undoManager)
        XCTAssertFalse(undo === document.undoManager, "Native text undo must stay separate from document edits")
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(editor.string, "80")
        XCTAssertEqual(document.session.state.globals.twirl, 0.8)
        undo.redo()
        XCTAssertEqual(editor.string, "45")
        commitPendingNumericEditing(in: window)
        XCTAssertEqual(document.session.state.globals.twirl, 0.45, accuracy: 0.000001)
        XCTAssertTrue(field.currentEditor() === editor)
        commitPendingNumericEditing(in: window)
        XCTAssertEqual(document.session.state.globals.twirl, 0.45, accuracy: 0.000001)
    }

    @MainActor func testTabCommitsNativeFieldBeforeMovingFocus() async throws {
        let document = GooDocument()
        document.session.state.globals.twirl = 0.8
        let (window, field) = try await host(document)
        defer { document.session.stopTimers(); window.close() }
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("45", replacementRange: editor.selectedRange())
        editor.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(document.session.state.globals.twirl, 0.45, accuracy: 0.000001)
    }

    @MainActor func testExplicitDocumentWriteCommitsBeforeSerializationAndPreservesFocus() async throws {
        let document = GooDocument()
        document.session.state.globals.twirl = 0.8
        let sample = try XCTUnwrap(ResourceBundle.url(forResource: "goo-guy", withExtension: "png"))
        document.session.source = try Data(contentsOf: sample)
        let (window, field) = try await host(document)
        let savedURL = FileManager.default.temporaryDirectory.appendingPathComponent("explicit-save-\(UUID().uuidString).meltorama")
        defer { document.session.stopTimers(); window.close(); try? FileManager.default.removeItem(at: savedURL) }
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("45", replacementRange: editor.selectedRange())
        try document.write(to: savedURL, ofType: "ch.lkmc.goo.project", for: .saveOperation, originalContentsURL: nil)
        XCTAssertEqual(try ProjectPackage.read(url: savedURL).document.globals.twirl, 0.45, accuracy: 0.000001)
        XCTAssertTrue(field.currentEditor() === editor)
    }

    @MainActor func testAutosaveDoesNotCommitPartialNumericText() async throws {
        let document = GooDocument()
        document.session.state.globals.twirl = 0.8
        let sample = try XCTUnwrap(ResourceBundle.url(forResource: "goo-guy", withExtension: "png"))
        document.session.source = try Data(contentsOf: sample)
        let (window, field) = try await host(document)
        let savedURL = FileManager.default.temporaryDirectory.appendingPathComponent("partial-autosave-\(UUID().uuidString).meltorama")
        defer { document.session.stopTimers(); window.close(); try? FileManager.default.removeItem(at: savedURL) }
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("0", replacementRange: editor.selectedRange())
        try document.write(to: savedURL, ofType: "ch.lkmc.goo.project", for: .autosaveInPlaceOperation, originalContentsURL: nil)
        XCTAssertEqual(document.session.state.globals.twirl, 0.8)
        XCTAssertEqual(try ProjectPackage.read(url: savedURL).document.globals.twirl, 0.8)
        XCTAssertEqual(editor.string, "0")
        XCTAssertTrue(field.currentEditor() === editor)
        editor.insertText(".45", replacementRange: editor.selectedRange())
        window.endEditing(for: nil)
        XCTAssertEqual(document.session.state.globals.twirl, 0.0045, accuracy: 0.000001)
    }

    @MainActor func testSuccessfulReadDiscardsNumericDraftBeforeReplacingDocument() async throws {
        let document = GooDocument()
        document.session.state.globals.twirl = 0.8
        let sample = try XCTUnwrap(ResourceBundle.url(forResource: "goo-guy", withExtension: "png"))
        let bytes = try Data(contentsOf: sample)
        document.session.source = bytes
        let (window, field) = try await host(document)
        defer { document.session.stopTimers(); window.close() }
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("45", replacementRange: editor.selectedRange())
        let reverted = ProjectPackage(document: ProjectDocument(globals: GlobalParams(twirl: 0.2)), sourceData: bytes)
        try document.read(from: reverted.fileWrapper(), ofType: "ch.lkmc.goo.project")
        document.commitPendingEditing()
        XCTAssertEqual(document.session.state.globals.twirl, 0.2, accuracy: 0.000001,
                       "A draft from before Revert must not be reapplied to the restored document")
        try await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(field.stringValue, "20")
    }

    @MainActor func testFailedReadPreservesNumericDraftAndFocus() async throws {
        let document = GooDocument()
        document.session.state.globals.twirl = 0.8
        let (window, field) = try await host(document)
        defer { document.session.stopTimers(); window.close() }
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("45", replacementRange: editor.selectedRange())
        let invalidImage = ProjectPackage(document: ProjectDocument(), sourceData: Data("not an image".utf8))
        XCTAssertThrowsError(try document.read(from: invalidImage.fileWrapper(), ofType: "ch.lkmc.goo.project"))
        XCTAssertEqual(document.session.state.globals.twirl, 0.8)
        XCTAssertEqual(editor.string, "45")
        XCTAssertTrue(field.currentEditor() === editor)
        document.commitPendingEditing()
        XCTAssertEqual(document.session.state.globals.twirl, 0.45, accuracy: 0.000001)
    }
}
