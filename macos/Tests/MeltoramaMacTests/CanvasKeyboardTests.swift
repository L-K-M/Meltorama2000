import AppKit
import MeltoramaCore
import XCTest
@testable import MeltoramaMac

private final class CanvasKeyEventProbe: NSResponder {
    var events: [NSEvent] = []
    override func keyDown(with event: NSEvent) { events.append(event) }
}

final class CanvasKeyboardTests: XCTestCase {
    @MainActor private func key(_ characters: String, ignoring: String? = nil,
                               modifiers: NSEvent.ModifierFlags = [], code: UInt16 = 0,
                               type: NSEvent.EventType = .keyDown) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: modifiers,
                                      timestamp: 0, windowNumber: 0, context: nil,
                                      characters: characters, charactersIgnoringModifiers: ignoring ?? characters,
                                      isARepeat: false, keyCode: code))
    }

    @MainActor func testOptionGeneratedSwissBracketsResizeBrush() async throws {
        _ = NSApplication.shared
        let session = EditorSession(), canvas = PhotoCanvas(frame: .zero)
        defer { session.stopTimers() }
        canvas.session = session
        session.radius = 0.12
        canvas.keyDown(with: try key("[", ignoring: "5", modifiers: .option, code: 23))
        XCTAssertEqual(session.radius, 0.12 / 1.15, accuracy: 0.000001)
        canvas.keyDown(with: try key("]", ignoring: "6", modifiers: .option, code: 22))
        XCTAssertEqual(session.radius, 0.12, accuracy: 0.000001)
        XCTAssertEqual(session.mode, .brush)
    }

    @MainActor func testCommandAndControlKeysForwardWithoutChangingCanvas() async throws {
        _ = NSApplication.shared
        let session = EditorSession(), canvas = PhotoCanvas(frame: .zero)
        defer { session.stopTimers() }
        canvas.session = session
        let probe = CanvasKeyEventProbe()
        canvas.nextResponder = probe
        session.radius = 0.12
        for modifiers: NSEvent.ModifierFlags in [.command, .control, [.command, .option], [.control, .shift]] {
            for character in ["b", "h", "l", "c", "[", "]"] {
                session.mode = .brush
                canvas.keyDown(with: try key(character, modifiers: modifiers))
                XCTAssertEqual(session.mode, .brush, "\(modifiers.rawValue) + \(character) must reach the responder chain")
                XCTAssertEqual(session.radius, 0.12, accuracy: 0.000001)
            }
        }
        XCTAssertEqual(probe.events.count, 24)
    }

    @MainActor func testOptionGeneratedNonBracketsForwardWithoutSelectingModes() async throws {
        _ = NSApplication.shared
        let session = EditorSession(), canvas = PhotoCanvas(frame: .zero)
        defer { session.stopTimers() }
        canvas.session = session
        let probe = CanvasKeyEventProbe()
        canvas.nextResponder = probe
        for (generated, base) in [("∫", "b"), ("Ω", "h"), ("¬", "l"), ("©", "c")] {
            session.mode = .brush
            canvas.keyDown(with: try key(generated, ignoring: base, modifiers: .option))
            XCTAssertEqual(session.mode, .brush, "Option + \(base) must reach the responder chain")
        }
        XCTAssertEqual(probe.events.count, 4)
    }

    @MainActor func testNormalCanvasModeEscapeAndDeleteCommandsStillWork() async throws {
        _ = NSApplication.shared
        let session = EditorSession(), canvas = PhotoCanvas(frame: .zero)
        defer { session.stopTimers() }
        canvas.session = session
        for (character, mode) in [("h", EditorSession.CanvasMode.hand), ("l", .lenses), ("c", .crop), ("b", .brush)] {
            canvas.keyDown(with: try key(character))
            XCTAssertEqual(session.mode, mode)
        }
        session.cropRect = CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5)
        session.playing = true
        session.live = false
        canvas.keyDown(with: try key("\u{1b}", code: 53))
        XCTAssertNil(session.cropRect)
        XCTAssertFalse(session.playing)
        XCTAssertTrue(session.live)

        session.mode = .lenses
        session.state.globals.lenses = [Lens()]
        session.selectedLens = 0
        canvas.keyDown(with: try key("\u{7f}", code: 51))
        XCTAssertTrue(session.state.globals.lenses.isEmpty)
        XCTAssertNil(session.selectedLens)

        session.mode = .brush
        session.showTimeline = true
        session.state.keyframes = [KeyframeRecord(revision: 0)]
        session.selectedKeyframe = 0
        canvas.keyDown(with: try key("\u{7f}", code: 51))
        XCTAssertTrue(session.state.keyframes.isEmpty)
        XCTAssertNil(session.selectedKeyframe)
    }

    @MainActor func testPlainBracketAndSpaceCommandsStillWork() async throws {
        _ = NSApplication.shared
        let session = EditorSession(), canvas = PhotoCanvas(frame: .zero)
        defer { session.stopTimers() }
        canvas.session = session
        session.radius = 0.12
        canvas.keyDown(with: try key("[", code: 33))
        XCTAssertEqual(session.radius, 0.12 / 1.15, accuracy: 0.000001)
        canvas.keyDown(with: try key("]", code: 30))
        XCTAssertEqual(session.radius, 0.12, accuracy: 0.000001)
        let previousCursor = NSCursor.current
        canvas.keyDown(with: try key(" ", code: 49))
        XCTAssertEqual(NSCursor.current, NSCursor.openHand)
        canvas.keyUp(with: try key(" ", code: 49, type: .keyUp))
        XCTAssertEqual(NSCursor.current, previousCursor)
    }
}
