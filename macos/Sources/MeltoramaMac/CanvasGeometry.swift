import CoreGraphics
import Foundation

/// The workspace zoom is relative to Fit; the percentage is measured in
/// display pixels per image pixel, including the window's Retina scale.
enum CanvasGeometry {
    private static let padding: CGFloat = 48

    static func fitScale(image: CGSize, viewport: CGSize) -> CGFloat {
        min(max(1, viewport.width - padding) / max(1, image.width),
            max(1, viewport.height - padding) / max(1, image.height))
    }

    static func imageRect(image: CGSize, viewport: CGSize, zoom: CGFloat, pan: CGPoint) -> CGRect {
        let scale = fitScale(image: image, viewport: viewport) * zoom
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (viewport.width - size.width) / 2 + pan.x,
                      y: (viewport.height - size.height) / 2 + pan.y,
                      width: size.width, height: size.height)
    }

    static func displayPixelScale(image: CGSize, viewport: CGSize, zoom: CGFloat, backingScale: CGFloat) -> CGFloat {
        fitScale(image: image, viewport: viewport) * zoom * max(1, backingScale)
    }

    static func actualSizeZoom(image: CGSize, viewport: CGSize, backingScale: CGFloat) -> CGFloat {
        1 / displayPixelScale(image: image, viewport: viewport, zoom: 1, backingScale: backingScale)
    }

    static func sourcePoint(_ point: CGPoint, imageRect rect: CGRect, rotation: CGFloat) -> CGPoint {
        let angle = -rotation * .pi / 180, c = cos(angle), s = sin(angle)
        let x = point.x - rect.midX, y = point.y - rect.midY
        return CGPoint(x: ((x * c - y * s) + rect.width / 2) / rect.width,
                       y: ((x * s + y * c) + rect.height / 2) / rect.height)
    }
}
