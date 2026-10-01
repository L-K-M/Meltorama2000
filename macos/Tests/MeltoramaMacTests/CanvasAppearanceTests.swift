import AppKit
import XCTest
@testable import MeltoramaMac

final class CanvasAppearanceTests: XCTestCase {
    @MainActor func testInheritedAppearanceInvalidatesCanvasAndResolvesItsBackgroundForDrawing() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let canvas = PhotoCanvas(frame: NSRect(x: 0, y: 0, width: 120, height: 100))
        window.contentView = canvas

        for preference in [ThemePreference.candy, .ocean] {
            canvas.workspaceBackgroundColor = MacTheme(preference: preference).canvasBackgroundColor
            window.appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
            for name in [NSAppearance.Name.aqua, .darkAqua, .aqua] {
                canvas.needsDisplay = false
                window.appearance = try XCTUnwrap(NSAppearance(named: name))
                XCTAssertTrue(canvas.needsDisplay,
                              "AppKit must invalidate the canvas after its inherited appearance changes")
                let pixel = try renderedCenterPixel(canvas)
                let expected = try resolve(canvas.workspaceBackgroundColor, in: canvas.effectiveAppearance)
                XCTAssertEqual(pixel.redComponent, expected.redComponent, accuracy: 0.01)
                XCTAssertEqual(pixel.greenComponent, expected.greenComponent, accuracy: 0.01)
                XCTAssertEqual(pixel.blueComponent, expected.blueComponent, accuracy: 0.01)
            }
        }
    }

    @MainActor private func renderedCenterPixel(_ canvas: PhotoCanvas) throws -> NSColor {
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: Int(canvas.bounds.width),
                                              height: Int(canvas.bounds.height), bitsPerComponent: 8,
                                              bytesPerRow: 0, space: colorSpace,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                                  | CGBitmapInfo.byteOrder32Big.rawValue))
        // A display-cache bitmap uses the connected screen's profile. Draw the
        // real view into an explicit sRGB context for stable pixel assertions.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        canvas.effectiveAppearance.performAsCurrentDrawingAppearance { canvas.draw(canvas.bounds) }
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let pixel = context.height / 2 * context.bytesPerRow + context.width / 2 * 4
        return NSColor(srgbRed: CGFloat(bytes[pixel]) / 255,
                       green: CGFloat(bytes[pixel + 1]) / 255,
                       blue: CGFloat(bytes[pixel + 2]) / 255,
                       alpha: CGFloat(bytes[pixel + 3]) / 255)
    }

    private func resolve(_ color: NSColor, in appearance: NSAppearance) throws -> NSColor {
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) }
        return try XCTUnwrap(resolved)
    }
}
