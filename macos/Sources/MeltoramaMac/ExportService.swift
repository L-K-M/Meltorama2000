import AVFoundation
import CoreGraphics
import Darwin
import ImageIO
import MeltoramaCore
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case png, jpeg, mp4, gif

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }
    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }
    var isMovie: Bool { self == .mp4 || self == .gif }
    var contentType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .mp4: return .mpeg4Movie
        case .gif: return .gif
        }
    }
}

struct ExportOptions: Sendable {
    var format: ExportFormat
    var jpegQuality: Double
    var speed: MovieSpeed
    var loop: Bool
    /// Nil preserves the original dimensions for still images.
    var maxDimension: Int?

    init(format: ExportFormat = .png, jpegQuality: Double = 0.95,
         speed: MovieSpeed = .normal, loop: Bool = true, maxDimension: Int? = nil) {
        self.format = format
        self.jpegQuality = jpegQuality
        self.speed = speed
        self.loop = loop
        self.maxDimension = maxDimension
    }
}

enum ExportFailure: LocalizedError {
    case invalidDestination
    case invalidOptions
    case needsKeyframes
    case imageTooLarge(width: Int, height: Int, limit: Int)
    case cannotEncode(String)
    case cannotFinalize(String)

    var errorDescription: String? {
        switch self {
        case .invalidDestination:
            return L("Choose a file on a writable local volume.")
        case .invalidOptions:
            return L("The export dimensions and JPEG quality must be positive, finite values.")
        case .needsKeyframes:
            return L("Add at least two GOOvie keyframes before exporting a movie.")
        case let .imageTooLarge(width, height, limit):
            return LF("This image is %d × %d pixels. Choose an export size of %d pixels or less on the longest side for this Mac.", width, height, limit)
        case let .cannotEncode(reason):
            return LF("The export could not be encoded. %@", reason)
        case let .cannotFinalize(reason):
            return LF("The exported file could not be saved. %@", reason)
        }
    }
}

enum CopyImageFailure: LocalizedError {
    case cannotEncode
    case cannotUpdatePasteboard

    var errorDescription: String? {
        switch self {
        case .cannotEncode: return L("The copied image could not be encoded.")
        case .cannotUpdatePasteboard: return L("The clipboard could not be updated.")
        }
    }
}

/// A separate renderer keeps exports independent of the canvas and its GL
/// context. All sinks consume the same tween recipe and nominal frame clock.
enum ExportService {
    static let movieMaxDimension = 1920
    static let gifMaxDimension = 480

    /// Progress is delivered on the export task. UI callers hop to MainActor.
    /// Cancelling the calling task removes its unfinished staging file.
    static func export(document: ProjectDocument, source: Data, fusion: Data?,
                       options: ExportOptions, to destination: URL,
                       progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws -> URL {
        let worker = Task.detached(priority: .userInitiated) {
            try await performExport(document: document, source: source, fusion: fusion,
                                    options: options, to: destination, progress: progress)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Called on a worker, with an immutable document snapshot. Still exports
    /// and the clipboard always render live edits without canvas overlays.
    static func renderStill(document: ProjectDocument, source: Data, fusion: Data?,
                            maxDimension: Int? = nil) throws -> CGImage {
        try Task.checkCancellation()
        guard maxDimension.map({ $0 > 0 }) ?? true else { throw ExportFailure.invalidOptions }
        try validateSources(document: document, fusion: fusion)
        let original = try WarpEngine.imageSize(data: source, crop: document.crop)
        let engine = try WarpEngine()
        let size = outputSize(original: original, options: ExportOptions(maxDimension: maxDimension))
        try validateSize(size, engine: engine)
        return try renderStill(engine: engine, document: document, source: source, fusion: fusion, size: size)
    }

    static func clipboardTIFF(document: ProjectDocument, source: Data, fusion: Data?) throws -> Data {
        let image = try renderStill(document: document, source: source, fusion: fusion)
        try Task.checkCancellation()
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil) else {
            throw CopyImageFailure.cannotEncode
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CopyImageFailure.cannotEncode }
        try Task.checkCancellation()
        return data as Data
    }

    static func movieSpec(for document: ProjectDocument, options: ExportOptions) -> MovieSpec {
        let count = document.keyframes.count
        let fps = options.format == .gif ? MovieSpec.gifFPS(keyframeCount: count, speed: options.speed) : 30
        return MovieSpec(keyframeCount: count, frameRate: fps, speed: options.speed)
    }

    /// The closing frame lands exactly on the final pin. Easing may
    /// extrapolate the displacement field while levers stay in range.
    static func makeTween(document: ProjectDocument, frame: Int,
                          totalFrames: Int, fps: Int) throws -> WarpTween {
        guard document.keyframes.count >= 2, totalFrames >= 2, fps > 0,
              frame >= 0, frame < totalFrames else { throw ExportFailure.needsKeyframes }
        let span = Float(document.keyframes.count - 1)
        let position = span * Float(frame) / Float(totalFrames - 1)
        let segment = GoovieTimeline.segment(position, size: document.keyframes.count)
        let fraction = GoovieTimeline.fraction(position, size: document.keyframes.count)
        let from = document.keyframes[segment]
        let to = document.keyframes[segment + 1]
        let globals = from.globals.lerp(to.globals, t: leverProgress(fraction, easing: from.easing))
        let seconds = Float(totalFrames - 1) / Float(fps)
        let safeWobble = document.wobble.cappedFor(loopSeconds: seconds)
        let phase = Float(frame) / Float(totalFrames - 1)
        return WarpTween(from: from.revision, to: to.revision,
                         fraction: tweenProgress(fraction, easing: from.easing),
                         globals: leversAt(base: globals, wobble: safeWobble, phase: phase))
    }

    private static func performExport(document: ProjectDocument, source: Data, fusion: Data?,
                                      options: ExportOptions, to destination: URL,
                                      progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        try Task.checkCancellation()
        guard destination.isFileURL, !destination.lastPathComponent.isEmpty else {
            throw ExportFailure.invalidDestination
        }
        guard options.jpegQuality.isFinite, options.jpegQuality > 0,
              options.maxDimension.map({ $0 > 0 }) ?? true else {
            throw ExportFailure.invalidOptions
        }
        if options.format.isMovie && document.keyframes.count < 2 {
            throw ExportFailure.needsKeyframes
        }
        try validateSources(document: document, fusion: fusion)
        let original = try WarpEngine.imageSize(data: source, crop: document.crop)
        let engine = try WarpEngine()
        let size = outputSize(original: original, options: options)
        try validateSize(size, engine: engine)

        let staging = destination.deletingLastPathComponent().appendingPathComponent(
            ".\(destination.deletingPathExtension().lastPathComponent)-export-\(UUID().uuidString).\(options.format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: staging) }
        progress(0)

        switch options.format {
        case .png, .jpeg:
            let image = try renderStill(engine: engine, document: document, source: source, fusion: fusion, size: size)
            try Task.checkCancellation()
            progress(0.8)
            try writeStill(image, options: options, to: staging)
        case .gif:
            try writeGIF(engine: engine, document: document, source: source, fusion: fusion,
                         size: size, options: options, to: staging, progress: progress)
        case .mp4:
            try await writeMovie(engine: engine, document: document, source: source, fusion: fusion,
                                 size: size, options: options, to: staging, progress: progress)
        }

        try Task.checkCancellation()
        // Same-volume rename is atomic and preserves an existing destination
        // throughout rendering, encoding, and cancellation.
        guard Darwin.rename(staging.path, destination.path) == 0 else {
            throw ExportFailure.cannotFinalize(String(cString: strerror(errno)))
        }
        progress(1)
        return destination
    }

    private static func validateSources(document: ProjectDocument, fusion: Data?) throws {
        try document.validate()
        if document.fusion != nil && fusion == nil {
            throw ExportFailure.cannotEncode(L("The Fusion source photo is missing. Reopen the project or import it again."))
        }
    }

    private static func validateSize(_ size: CGSize, engine: WarpEngine) throws {
        guard max(size.width, size.height) <= CGFloat(engine.maxTextureSize) else {
            throw ExportFailure.imageTooLarge(width: Int(size.width), height: Int(size.height), limit: engine.maxTextureSize)
        }
    }

    private static func renderStill(engine: WarpEngine, document: ProjectDocument,
                                    source: Data, fusion: Data?, size: CGSize) throws -> CGImage {
        try Task.checkCancellation()
        return try autoreleasepool {
            try engine.render(document: document, source: source, fusion: fusion, size: size)
        }
    }

    static func outputSize(original: CGSize, options: ExportOptions) -> CGSize {
        let formatCap: Int?
        switch options.format {
        case .png, .jpeg: formatCap = nil
        case .mp4: formatCap = movieMaxDimension
        case .gif: formatCap = gifMaxDimension
        }
        let cap = [formatCap, options.maxDimension].compactMap { $0 }.min()
        let scale = cap.map { min(1, CGFloat($0) / max(original.width, original.height)) } ?? 1
        let width = max(1, Int((original.width * scale).rounded(.down)))
        let height = max(1, Int((original.height * scale).rounded(.down)))
        if options.format == .mp4 || options.format == .gif {
            return CGSize(width: max(2, width - width % 2), height: max(2, height - height % 2))
        }
        return CGSize(width: width, height: height)
    }

    private static func writeStill(_ image: CGImage, options: ExportOptions, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL,
            options.format.contentType.identifier as CFString, 1, nil) else {
            throw ExportFailure.cannotEncode(L("The image encoder could not be opened."))
        }
        let properties: [CFString: Any] = options.format == .jpeg
            ? [kCGImageDestinationLossyCompressionQuality: min(1, options.jpegQuality)] : [:]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ExportFailure.cannotEncode(L("The image encoder could not finish writing the file."))
        }
    }

    private static func writeGIF(engine: WarpEngine, document: ProjectDocument,
                                 source: Data, fusion: Data?, size: CGSize,
                                 options: ExportOptions, to url: URL,
                                 progress: @escaping @Sendable (Double) -> Void) throws {
        let spec = movieSpec(for: document, options: options)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                               spec.totalFrames, nil) else {
            throw ExportFailure.cannotEncode(L("The GIF encoder could not be opened."))
        }
        if options.loop {
            CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary:
                [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        }
        // Every selected ladder rate divides 100, preserving exact GIF timing.
        let delay = Double(max(2, 100 / spec.frameRate)) / 100
        let properties = [kCGImagePropertyGIFDictionary:
            [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary
        for frame in 0..<spec.totalFrames {
            try Task.checkCancellation()
            try autoreleasepool {
                let tween = try makeTween(document: document, frame: frame,
                                          totalFrames: spec.totalFrames, fps: spec.frameRate)
                let image = try engine.render(document: document, source: source, fusion: fusion,
                                              size: size, tween: tween)
                CGImageDestinationAddImage(destination, image, properties)
            }
            progress(0.95 * Double(frame + 1) / Double(spec.totalFrames))
        }
        try Task.checkCancellation()
        guard CGImageDestinationFinalize(destination) else {
            throw ExportFailure.cannotEncode(L("The GIF encoder could not finish writing the file."))
        }
    }

    private static func writeMovie(engine: WarpEngine, document: ProjectDocument,
                                   source: Data, fusion: Data?, size: CGSize,
                                   options: ExportOptions, to url: URL,
                                   progress: @escaping @Sendable (Double) -> Void) async throws {
        let spec = movieSpec(for: document, options: options)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoMaxKeyFrameIntervalKey: spec.frameRate,
                AVVideoExpectedSourceFrameRateKey: spec.frameRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height),
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
            ])
        guard writer.canAdd(input) else {
            throw ExportFailure.cannotEncode(L("H.264 encoding is unavailable for this image size."))
        }
        writer.add(input)
        guard writer.startWriting() else {
            throw writer.error ?? ExportFailure.cannotEncode(L("The movie encoder could not start."))
        }
        writer.startSession(atSourceTime: .zero)
        do {
            for frame in 0..<spec.totalFrames {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing else {
                        throw writer.error ?? ExportFailure.cannotEncode(L("The movie encoder stopped unexpectedly."))
                    }
                    try await Task.sleep(nanoseconds: 5_000_000)
                }
                try autoreleasepool {
                    let tween = try makeTween(document: document, frame: frame,
                                              totalFrames: spec.totalFrames, fps: spec.frameRate)
                    let image = try engine.render(document: document, source: source, fusion: fusion,
                                                  size: size, tween: tween)
                    let buffer = try pixelBuffer(image: image, pool: adaptor.pixelBufferPool, size: size)
                    let time = CMTime(value: Int64(frame), timescale: Int32(spec.frameRate))
                    guard adaptor.append(buffer, withPresentationTime: time) else {
                        throw writer.error ?? ExportFailure.cannotEncode(L("A movie frame could not be encoded."))
                    }
                }
                progress(0.95 * Double(frame + 1) / Double(spec.totalFrames))
            }
            input.markAsFinished()
            await withCheckedContinuation { continuation in
                writer.finishWriting { continuation.resume() }
            }
            try Task.checkCancellation()
            guard writer.status == .completed else {
                throw writer.error ?? ExportFailure.cannotEncode(L("The movie encoder could not finish writing the file."))
            }
        } catch {
            writer.cancelWriting()
            throw error
        }
    }

    private static func pixelBuffer(image: CGImage, pool: CVPixelBufferPool?, size: CGSize) throws -> CVPixelBuffer {
        guard let pool else { throw ExportFailure.cannotEncode(L("The movie frame buffer pool is unavailable.")) }
        var allocated: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &allocated) == kCVReturnSuccess,
              let buffer = allocated else {
            throw ExportFailure.cannotEncode(L("There is not enough memory to encode a movie frame."))
        }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let pixels = CVPixelBufferGetBaseAddress(buffer),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: pixels, width: Int(size.width), height: Int(size.height),
                bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                    CGBitmapInfo.byteOrder32Little.rawValue) else {
            throw ExportFailure.cannotEncode(L("The movie frame drawing context is unavailable."))
        }
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}
