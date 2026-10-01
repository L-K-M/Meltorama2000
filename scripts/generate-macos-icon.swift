// Packages the original elastic-photograph artwork into a standard Mac iconset.
// Usage: swift scripts/generate-macos-icon.swift OUTPUT.iconset
import AppKit
import ImageIO

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("!! \(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 2 else {
    fail("Usage: swift scripts/generate-macos-icon.swift OUTPUT.iconset")
}

let repository = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
let artwork = repository.appendingPathComponent("macos/Artwork/MeltoramaIcon.png")
guard let source = CGImageSourceCreateWithURL(artwork as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width == image.height, image.width >= 1024 else {
    fail("The Mac icon master must be a readable square PNG of at least 1024 pixels: \(artwork.path)")
}
guard [.first, .last, .premultipliedFirst, .premultipliedLast].contains(image.alphaInfo) else {
    fail("The Mac icon master must preserve transparent edges.")
}

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

// The freeform photograph has its own contour. Leave breathing room around
// it so it has a comfortable Dock footprint, rather than adding another tile.
let canvasInset: CGFloat = 1 / 16
let representations: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024)
]
var rendered: [Int: Data] = [:]
for representation in representations {
    let size = representation.pixels
    if rendered[size] == nil {
        let output = NSMutableData()
        guard let context = CGContext(data: nil, width: size, height: size,
                                      bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let encoder = CGImageDestinationCreateWithData(output as CFMutableData, "public.png" as CFString, 1, nil) else {
            fail("Could not allocate a \(size)-pixel icon representation.")
        }
        let side = CGFloat(size)
        let inset = side * canvasInset
        context.clear(CGRect(x: 0, y: 0, width: side, height: side))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2))
        guard let scaled = context.makeImage() else { fail("Could not render the \(size)-pixel icon.") }
        CGImageDestinationAddImage(encoder, scaled, nil)
        guard CGImageDestinationFinalize(encoder) else { fail("Could not encode the \(size)-pixel icon.") }
        rendered[size] = output as Data
    }
    try rendered[size]!.write(to: destination.appendingPathComponent(representation.name + ".png"))
}
