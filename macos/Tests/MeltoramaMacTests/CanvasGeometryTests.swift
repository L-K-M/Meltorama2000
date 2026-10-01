import AppKit
import XCTest
@testable import MeltoramaMac

final class CanvasGeometryTests: XCTestCase {
    func testActualSizeIsOneImagePixelPerDisplayPixel() {
        for image in [CGSize(width: 1200, height: 900), CGSize(width: 900, height: 2400)] {
            for viewport in [CGSize(width: 900, height: 700), CGSize(width: 1500, height: 950)] {
                for backing: CGFloat in [1, 2] {
                    let zoom = CanvasGeometry.actualSizeZoom(image: image, viewport: viewport, backingScale: backing)
                    let rect = CanvasGeometry.imageRect(image: image, viewport: viewport, zoom: zoom, pan: .zero)
                    XCTAssertEqual(rect.width * backing, image.width, accuracy: 0.000001)
                    XCTAssertEqual(rect.height * backing, image.height, accuracy: 0.000001)
                    XCTAssertEqual(CanvasGeometry.displayPixelScale(image: image, viewport: viewport, zoom: zoom,
                                                                   backingScale: backing), 1, accuracy: 0.000001)
                }
            }
        }
    }

    func testFitPercentageMatchesTheMeasuredRetinaPixelScale() {
        let image = CGSize(width: 1200, height: 900), viewport = CGSize(width: 900, height: 700)
        let rect = CanvasGeometry.imageRect(image: image, viewport: viewport, zoom: 1, pan: .zero)
        XCTAssertEqual(rect.width, 852, accuracy: 0.000001)
        XCTAssertEqual(CanvasGeometry.displayPixelScale(image: image, viewport: viewport, zoom: 1, backingScale: 2),
                       rect.width * 2 / image.width, accuracy: 0.000001)
        XCTAssertEqual(CanvasGeometry.displayPixelScale(image: image, viewport: viewport, zoom: 1, backingScale: 2),
                       1.42, accuracy: 0.000001)
    }

    func testResizingPanAndRotationPreserveSourceCoordinateMapping() {
        let image = CGSize(width: 1200, height: 900), source = CGPoint(x: 0.2, y: 0.4)
        for viewport in [CGSize(width: 900, height: 700), CGSize(width: 1400, height: 800), CGSize(width: 640, height: 920)] {
            let rect = CanvasGeometry.imageRect(image: image, viewport: viewport, zoom: 1.7, pan: CGPoint(x: 23, y: -15))
            for rotation: CGFloat in [0, 37, -90] {
                let angle = rotation * .pi / 180
                let x = (source.x - 0.5) * rect.width, y = (source.y - 0.5) * rect.height
                let screen = CGPoint(x: rect.midX + x * cos(angle) - y * sin(angle),
                                     y: rect.midY + x * sin(angle) + y * cos(angle))
                let projected = CanvasGeometry.sourcePoint(screen, imageRect: rect, rotation: rotation)
                XCTAssertEqual(projected.x, source.x, accuracy: 0.000001)
                XCTAssertEqual(projected.y, source.y, accuracy: 0.000001)
            }
        }
    }

    @MainActor func testSessionActualSizeDisplays100PercentAndFitUsesItsMeasuredScale() {
        let session = EditorSession()
        session.imageSize = CGSize(width: 1200, height: 900)
        session.updateViewport(size: CGSize(width: 900, height: 700), backingScale: 2)
        session.zoom = 3; session.pan = CGPoint(x: 23, y: -15); session.rotation = 37
        session.actualSize()
        XCTAssertEqual(Int((session.displayedZoom * 100).rounded()), 100)
        XCTAssertEqual(session.pan, .zero)
        XCTAssertEqual(session.rotation, 0)
        session.resetView()
        XCTAssertEqual(Int((session.displayedZoom * 100).rounded()), 142)
    }

    @MainActor func testCanvasPublishesItsViewportAfterResizing() {
        let session = EditorSession(), canvas = PhotoCanvas(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
        canvas.session = session
        canvas.setFrameSize(NSSize(width: 1400, height: 800))
        XCTAssertEqual(session.viewportSize, CGSize(width: 1400, height: 800))
        XCTAssertEqual(session.viewportBackingScale, 1)
    }
}
