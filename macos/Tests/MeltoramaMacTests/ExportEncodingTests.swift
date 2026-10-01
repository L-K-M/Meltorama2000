import AVFoundation
import CoreGraphics
import ImageIO
import MeltoramaCore
import XCTest
@testable import MeltoramaMac

final class ExportEncodingTests: XCTestCase {
    private let size = CGSize(width: 128, height: 96)

    private func requireGPU() throws {
        do { _ = try WarpEngine() }
        catch WarpError.unavailable {
            throw XCTSkip("The process has no macOS GPU context. Run export boundary tests outside the filesystem sandbox on a logged-in Mac.")
        }
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func source() throws -> Data {
        let width = Int(size.width), height = Int(size.height)
        let pixels = Data((0..<(width * height)).flatMap { point -> [UInt8] in
            point / width < height / 2 ? [255, 0, 0, 255] : [0, 0, 255, 255]
        })
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: pixels as CFData)!, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private var document: ProjectDocument {
        ProjectDocument(keyframes: [KeyframeRecord(revision: 0), KeyframeRecord(revision: 0)])
    }

    private func assertDimensionsAndOrientation(_ image: CGImage, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(image.width, Int(size.width), file: file, line: line)
        XCTAssertEqual(image.height, Int(size.height), file: file, line: line)
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let upper = (image.width / 2 + image.width * (image.height / 4)) * 4
        let lower = (image.width / 2 + image.width * (image.height * 3 / 4)) * 4
        XCTAssertGreaterThan(pixels[upper], 180, file: file, line: line)
        XCTAssertLessThan(pixels[upper + 2], 50, file: file, line: line)
        XCTAssertLessThan(pixels[lower], 50, file: file, line: line)
        XCTAssertGreaterThan(pixels[lower + 2], 180, file: file, line: line)
    }

    func testStillExportsDecodeAtSourceSizeWithUprightRows() async throws {
        try requireGPU()
        let directory = try directory(), source = try source()
        defer { try? FileManager.default.removeItem(at: directory) }
        for format in [ExportFormat.png, .jpeg] {
            let url = directory.appendingPathComponent("still.\(format.fileExtension)")
            _ = try await ExportService.export(document: document, source: source, fusion: nil,
                                                options: ExportOptions(format: format), to: url)
            let decoder = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetCount(decoder), 1)
            try assertDimensionsAndOrientation(try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoder, 0, nil)))
        }
    }

    func testGIFDecodesEveryFrameWithNominalDelayAndSelectedLoopBehavior() async throws {
        try requireGPU()
        let directory = try directory(), source = try source()
        defer { try? FileManager.default.removeItem(at: directory) }
        for loop in [true, false] {
            let options = ExportOptions(format: .gif, loop: loop)
            let spec = ExportService.movieSpec(for: document, options: options)
            let url = directory.appendingPathComponent("loop-\(loop).gif")
            _ = try await ExportService.export(document: document, source: source, fusion: nil, options: options, to: url)
            let decoder = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
            XCTAssertEqual(CGImageSourceGetCount(decoder), spec.totalFrames)
            for index in 0..<spec.totalFrames {
                try assertDimensionsAndOrientation(try XCTUnwrap(CGImageSourceCreateImageAtIndex(decoder, index, nil)))
                let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(decoder, index, nil) as? [CFString: Any])
                let gif = try XCTUnwrap(properties[kCGImagePropertyGIFDictionary] as? [CFString: Any])
                let delay = try XCTUnwrap(gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double)
                XCTAssertEqual(delay, 1 / Double(spec.frameRate), accuracy: 0.00001)
            }
            // ImageIO reports a default loop value even without an extension;
            // inspect the encoded extension to distinguish a one-shot file.
            let bytes = try Data(contentsOf: url)
            XCTAssertEqual(bytes.range(of: Data("NETSCAPE2.0".utf8)) != nil, loop)
        }
    }

    func testH264SpeedChangesSampleCountWhileKeepingNominalFrameRate() async throws {
        try requireGPU()
        let directory = try directory(), source = try source()
        defer { try? FileManager.default.removeItem(at: directory) }
        for speed in [MovieSpeed.half, .quadruple] {
            let options = ExportOptions(format: .mp4, speed: speed)
            let spec = ExportService.movieSpec(for: document, options: options)
            let url = directory.appendingPathComponent("movie-\(speed.rawValue).mp4")
            _ = try await ExportService.export(document: document, source: source, fusion: nil, options: options, to: url)
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let track = try XCTUnwrap(tracks.first)
            let rate = try await track.load(.nominalFrameRate)
            XCTAssertEqual(rate, 30, accuracy: 0.01)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            let (image, _) = try await generator.image(at: .zero)
            try assertDimensionsAndOrientation(image)
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            reader.add(output)
            XCTAssertTrue(reader.startReading())
            var samples = 0
            while let sample = output.copyNextSampleBuffer() { samples += CMSampleBufferGetNumSamples(sample) }
            XCTAssertEqual(reader.status, .completed)
            XCTAssertEqual(samples, spec.totalFrames)
        }
    }

    func testCancellingAnimatedExportsPreservesDestinationAndRemovesStagingFile() async throws {
        try requireGPU()
        let directory = try directory(), source = try source()
        defer { try? FileManager.default.removeItem(at: directory) }
        var longDocument = document
        longDocument.keyframes = Array(repeating: KeyframeRecord(revision: 0), count: 64)
        for format in [ExportFormat.gif, .mp4] {
            let url = directory.appendingPathComponent("cancel.\(format.fileExtension)")
            let sentinel = Data("existing output must survive".utf8)
            try sentinel.write(to: url)
            let signal = ExportFrameSignal()
            let task = Task {
                try await ExportService.export(document: longDocument, source: source, fusion: nil,
                    options: ExportOptions(format: format, speed: .half), to: url,
                    progress: { signal.record($0) })
            }
            for _ in 0..<1000 where !signal.hasFrame { try await Task.sleep(nanoseconds: 1_000_000) }
            XCTAssertTrue(signal.hasFrame, "The export never rendered its first frame")
            task.cancel()
            do { _ = try await task.value; XCTFail("A cancelled export completed") }
            catch is CancellationError { }
            XCTAssertEqual(try Data(contentsOf: url), sentinel)
            let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            XCTAssertFalse(contents.contains(where: { $0.hasPrefix(".cancel-export-") }))
        }
    }
}

private final class ExportFrameSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var firstFrame = false

    func record(_ progress: Double) {
        lock.lock(); defer { lock.unlock() }
        if progress > 0 { firstFrame = true }
    }
    var hasFrame: Bool {
        lock.lock(); defer { lock.unlock() }
        return firstFrame
    }
}
