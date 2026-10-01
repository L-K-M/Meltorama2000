import AppKit
import XCTest
@testable import MeltoramaMac

private final class MagnificationProbe: NSEvent {
    override var magnification: CGFloat { 0 }
}

final class NativeZoomTests: XCTestCase {
    @MainActor func testRepeatedZoomStepsKeepCanvasUsable() async {
        let session = EditorSession()
        defer { session.stopTimers() }
        for _ in 0..<200 { session.scaleZoom(by: 0.8) }
        XCTAssertEqual(session.zoom, 0.1, accuracy: 0.000001)
        for _ in 0..<200 { session.scaleZoom(by: 1.25) }
        XCTAssertEqual(session.zoom, 16, accuracy: 0.000001)
        XCTAssertTrue(session.displayedZoom.isFinite)
    }

    @MainActor func testPinchUsesTheSameBoundsAsZoomSteps() async {
        _ = NSApplication.shared
        let session = EditorSession(), canvas = PhotoCanvas(frame: .zero)
        defer { session.stopTimers() }
        canvas.session = session
        let pinch = MagnificationProbe()
        // The zero-magnification event repairs an out-of-range view scale
        // through the same path used by menu and gesture input.
        session.zoom = 0.0000001
        canvas.magnify(with: pinch)
        XCTAssertEqual(session.zoom, 0.1, accuracy: 0.000001)
        session.zoom = 100
        canvas.magnify(with: pinch)
        XCTAssertEqual(session.zoom, 16, accuracy: 0.000001)
    }

    @MainActor func testActualSizeRetainsOriginalPixelScaleForLargePhotos() async {
        let session = EditorSession()
        defer { session.stopTimers() }
        session.imageSize = CGSize(width: 65535, height: 1)
        session.updateViewport(size: CGSize(width: 900, height: 700), backingScale: 2)
        session.actualSize()
        XCTAssertGreaterThan(session.zoom, 16)
        XCTAssertEqual(session.displayedZoom, 1, accuracy: 0.000001)
        session.scaleZoom(by: 0.8)
        XCTAssertEqual(session.zoom, 16, accuracy: 0.000001)
    }

    @MainActor func testInvalidGestureMultiplierPreservesTheView() async {
        let session = EditorSession()
        defer { session.stopTimers() }
        for invalid: CGFloat in [.nan, .infinity, -.infinity] {
            session.scaleZoom(by: invalid)
            XCTAssertEqual(session.zoom, 1)
        }
        session.scaleZoom(by: -1)
        XCTAssertEqual(session.zoom, 0.1, accuracy: 0.000001)
    }
}
