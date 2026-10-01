import CoreGraphics
import ImageIO
import MeltoramaCore
import XCTest
@testable import MeltoramaMac

final class WarpEngineTests: XCTestCase {
    private let width = 128
    private let height = 96
    private var size: CGSize { CGSize(width: width, height: height) }

    private func engine() throws -> WarpEngine {
        do { return try WarpEngine() }
        catch WarpError.unavailable {
            throw XCTSkip("The process has no macOS GPU context. Run native GPU tests outside the filesystem sandbox on a logged-in Mac.")
        }
    }

    private func fixture(inverted: Bool = false) throws -> (data: Data, pixels: Data) {
        let bytes = (0..<(width * height)).flatMap { point -> [UInt8] in
            let x = point % width, y = point / width
            let color = [UInt8(x * 2), UInt8(y * 2), UInt8((x * 7 + y * 3) % 256)]
            return (inverted ? color.map { 255 - $0 } : color) + [255]
        }
        let pixels = Data(bytes)
        let image = try XCTUnwrap(CGImage(width: width, height: height,
                                        bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                        provider: CGDataProvider(data: pixels as CFData)!, decode: nil,
                                        shouldInterpolate: false, intent: .defaultIntent))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return (data as Data, pixels)
    }

    private func pixels(_ image: CGImage) throws -> Data {
        try XCTUnwrap(image.dataProvider?.data) as Data
    }

    func testIdentityPreservesEveryPixelAndRowOrientation() throws {
        let renderer = try engine(), source = try fixture()
        let image = try renderer.render(document: ProjectDocument(), source: source.data, fusion: nil, size: size)
        XCTAssertEqual(try pixels(image), source.pixels)
    }

    func testFractionalCropMatchesAndroidPixelsAndExportDimensions() async throws {
        let renderer = try engine(), source = try fixture()
        let crop = CropRect(left: 0.1, top: 0.1, right: 0.9, bottom: 0.9)
        let document = ProjectDocument(crop: crop)
        let expectedSize = CGSize(width: 102, height: 77)
        XCTAssertEqual(try WarpEngine.imageSize(data: source.data, crop: crop), expectedSize)
        let decoded = try WarpEngine.decodedImage(data: source.data, crop: crop, maxDimension: width)
        XCTAssertEqual(decoded.width, 102)
        XCTAssertEqual(decoded.height, 77)
        let output = try renderer.render(document: document, source: source.data, fusion: nil, size: expectedSize)
        var expected = Data()
        for y in 10..<87 {
            let first = (y * width + 13) * 4
            expected.append(source.pixels[first..<(first + 102 * 4)])
        }
        XCTAssertTrue(try pixels(output) == expected, "Identity crop must preserve Android's exact rounded pixel rectangle")
        let sampleURL = try XCTUnwrap(ResourceBundle.url(forResource: "goo-guy", withExtension: "png"))
        XCTAssertEqual(try WarpEngine.imageSize(data: Data(contentsOf: sampleURL), crop: crop),
                       CGSize(width: 960, height: 720))
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("crop-export-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: destination) }
        _ = try await ExportService.export(document: document, source: source.data, fusion: nil,
                                           options: ExportOptions(format: .png), to: destination)
        let png = try XCTUnwrap(CGImageSourceCreateWithURL(destination as CFURL, nil))
        let exported = try XCTUnwrap(CGImageSourceCreateImageAtIndex(png, 0, nil))
        XCTAssertEqual(exported.width, 102)
        XCTAssertEqual(exported.height, 77)
    }

    func testFullFrameCropJitterUsesAndroidsUncroppedDecode() throws {
        let source = try fixture(), renderer = try engine()
        let crop = CropRect(left: 0.004, top: 0.004, right: 0.996, bottom: 0.996)
        XCTAssertTrue(crop.isFullFrame)
        XCTAssertEqual(try WarpEngine.imageSize(data: source.data, crop: crop), size)
        let decoded = try WarpEngine.decodedImage(data: source.data, crop: crop, maxDimension: width)
        XCTAssertEqual(decoded.width, width)
        XCTAssertEqual(decoded.height, height)
        let rendered = try renderer.render(document: ProjectDocument(crop: crop), source: source.data, fusion: nil, size: size)
        XCTAssertEqual(try pixels(rendered), source.pixels)
    }

    func testFailedFusionDecodePreservesThePreviouslyCachedPhoto() throws {
        let renderer = try engine(), source = try fixture(), fusion = try fixture(inverted: true)
        var log = StrokeLog()
        try log.push(Stroke(tool: .fuse, radius: 0.3, strength: 1,
                            stamps: Array(repeating: Stamp(cx: 0.5, cy: 0.5), count: 20)))
        let document = ProjectDocument(log: log.snapshot())
        let original = try renderer.render(document: document, source: source.data, fusion: fusion.data, size: size)
        XCTAssertThrowsError(try renderer.render(document: document, source: source.data,
                                                fusion: Data([0]), size: size))
        let restored = try renderer.render(document: document, source: source.data, fusion: fusion.data, size: size)
        let fresh = try engine().render(document: document, source: source.data, fusion: fusion.data, size: size)
        XCTAssertTrue(try pixels(restored) == pixels(original), "Restoring the previous Fusion photo after a decode error must keep its texture")
        XCTAssertTrue(try pixels(restored) == pixels(fresh), "Error recovery must match a fresh replay")

        var croppedDocument = document
        croppedDocument.crop = CropRect(left: 0.25, top: 0, right: 0.75, bottom: 1)
        let croppedSize = CGSize(width: 64, height: 96)
        XCTAssertThrowsError(try renderer.render(document: croppedDocument, source: source.data,
                                                fusion: Data([0]), size: croppedSize))
        let cropped = try renderer.render(document: croppedDocument, source: source.data, fusion: fusion.data, size: croppedSize)
        let croppedFresh = try engine().render(document: croppedDocument, source: source.data, fusion: fusion.data, size: croppedSize)
        XCTAssertTrue(try pixels(cropped) == pixels(croppedFresh), "Retry after a crop change must rebuild Fusion's cover crop")
    }

    func testFailedSourceDecodePreservesThePreviouslyCachedPhoto() throws {
        let renderer = try engine(), source = try fixture(), fusion = try fixture(inverted: true)
        var log = StrokeLog()
        try log.push(Stroke(tool: .fuse, radius: 0.3, strength: 1,
                            stamps: Array(repeating: Stamp(cx: 0.5, cy: 0.5), count: 20)))
        let document = ProjectDocument(log: log.snapshot())
        let original = try renderer.render(document: document, source: source.data, fusion: fusion.data, size: size)
        XCTAssertThrowsError(try renderer.render(document: document, source: Data([0]), fusion: fusion.data, size: size))
        let restored = try renderer.render(document: document, source: source.data, fusion: fusion.data, size: size)
        XCTAssertTrue(try pixels(restored) == pixels(original), "A rejected source must leave the previous decoded images usable")
    }

    func testEXIFRotationIsAppliedBeforeDocumentCrop() throws {
        let renderer = try engine(), source = try fixture()
        let decodedSource = try XCTUnwrap(CGImageSourceCreateWithData(source.data as CFData, nil))
        let original = try XCTUnwrap(CGImageSourceCreateImageAtIndex(decodedSource, 0, nil))
        let jpeg = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(jpeg, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, original,
                                  [kCGImagePropertyOrientation: 6,
                                   kCGImageDestinationLossyCompressionQuality: 1] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let rotated = try WarpEngine.imageSize(data: jpeg as Data)
        XCTAssertEqual(rotated, CGSize(width: height, height: width))
        let output = try renderer.render(document: ProjectDocument(), source: jpeg as Data,
                                           fusion: nil, size: rotated)
        let color = try pixels(output)
        // EXIF 6 rotates clockwise: the original lower-left green corner
        // arrives in the upright image's upper-left corner.
        XCTAssertLessThan(color[0], 12)
        XCTAssertGreaterThan(color[1], 170)
        let crop = CropRect(left: 0, top: 0, right: 0.5, bottom: 0.5)
        XCTAssertEqual(try WarpEngine.imageSize(data: jpeg as Data, crop: crop),
                       CGSize(width: height / 2, height: width / 2))
    }

    func testEveryStampedToolChangesTheImageAndReplaysIdentically() throws {
        let renderer = try engine(), source = try fixture(), fusion = try fixture(inverted: true)
        let seed = Stroke(tool: .smear, radius: 0.3, strength: 1,
                          stamps: [Stamp(cx: 0.45, cy: 0.5, dx: 0.07, dy: 0.02)])
        for tool in BrushTool.allCases where tool != .pins && tool != .rewind {
            var log = StrokeLog()
            try log.push(seed)
            let base = ProjectDocument(log: log.snapshot())
            let baseImage = try renderer.render(document: base, source: source.data, fusion: fusion.data, size: size)
            let points = (0..<15).map { i in
                Stamp(cx: 0.45 + Float(i) * 0.004, cy: 0.5,
                      dx: tool == .unwind ? -0.008 : 0.008, dy: 0.002)
            }
            try log.push(Stroke(tool: tool, radius: 0.26, strength: tool.strengthScale, stamps: points))
            let document = ProjectDocument(log: log.snapshot())
            let result = try renderer.render(document: document, source: source.data, fusion: fusion.data,
                                              size: size, showFreeze: tool == .freeze)
            let replay = try engine().render(document: document, source: source.data, fusion: fusion.data,
                                              size: size, showFreeze: tool == .freeze)
            XCTAssertNotEqual(try pixels(result), try pixels(baseImage), "\(tool.rawValue) did not affect the fixture")
            XCTAssertEqual(try pixels(result), try pixels(replay), "\(tool.rawValue) replay differed")
        }
    }

    func testGrowingLiveStrokeMatchesCommitAndUndoRebuild() throws {
        let renderer = try engine(), source = try fixture(), blank = ProjectDocument()
        let partial = Stroke(tool: .smear, radius: 0.2, strength: 1,
                             stamps: [Stamp(cx: 0.45, cy: 0.45, dx: 0.03, dy: 0.01)])
        var growing = partial
        growing.stamps += [Stamp(cx: 0.48, cy: 0.45, dx: 0.03, dy: 0.01),
                           Stamp(cx: 0.7, cy: 0.7, dx: -0.02, dy: 0.01)]
        _ = try renderer.render(document: blank, source: source.data, fusion: nil, size: size, activeStroke: partial)
        let incremental = try renderer.render(document: blank, source: source.data, fusion: nil,
                                               size: size, activeStroke: growing)
        var log = StrokeLog()
        try log.push(growing)
        let committed = try engine().render(document: ProjectDocument(log: log.snapshot()),
                                              source: source.data, fusion: nil, size: size)
        XCTAssertEqual(try pixels(incremental), try pixels(committed))
        let undone = try renderer.render(document: blank, source: source.data, fusion: nil, size: size)
        XCTAssertEqual(try pixels(undone), source.pixels)
    }

    func testRewindPinsLensesAndIndependentTweenEndpoints() throws {
        let renderer = try engine(), source = try fixture()
        var log = StrokeLog()
        try log.push(Stroke(tool: .smear, radius: 0.3, strength: 1,
                            stamps: [Stamp(cx: 0.4, cy: 0.5, dx: 0.09, dy: 0.01)]))
        let pin = log.currentRevision
        try log.push(Stroke(tool: .rewind, radius: 0.25, strength: 1,
                            stamps: Array(repeating: Stamp(cx: 0.5, cy: 0.5), count: 5), targetRevision: 0))
        let recallPin = log.currentRevision
        try log.push(Stroke(tool: .rewind, radius: 0.2, strength: 1,
                            stamps: [Stamp(cx: 0.55, cy: 0.5)], targetRevision: recallPin))
        try log.push(Stroke(tool: .pins, radius: 0.1, strength: 1, stamps: [],
                            pinWarp: PinWarp(controls: [MlsControl(su: 0.3, sv: 0.3, tu: 0.4, tv: 0.4),
                                                       MlsControl(su: 0.8, sv: 0.8, tu: 0.8, tv: 0.8)])))
        var document = ProjectDocument(log: log.snapshot(pins: [pin]))
        document.globals.twirl = 0.3
        document.globals.lenses = [Lens(u: 0.3, v: 0.3, radius: 0.2, type: .fisheye, strength: 0.5)]
        let result = try renderer.render(document: document, source: source.data, fusion: nil, size: size)
        let replay = try engine().render(document: document, source: source.data, fusion: nil, size: size)
        XCTAssertEqual(try pixels(result), try pixels(replay))
        let tween = WarpTween(from: 0, to: pin, fraction: 1, globals: GlobalParams())
        let tweened = try renderer.render(document: document, source: source.data, fusion: nil, size: size, tween: tween)
        let pinned = ProjectDocument(log: StrokeLogSnapshot(revisions: document.log.revisions, history: [pin], cursor: 0))
        let exact = try engine().render(document: pinned, source: source.data, fusion: nil, size: size)
        XCTAssertEqual(try pixels(tweened), try pixels(exact))
        // Undo and a new branch do not move the endpoint pinned above.
        log.undo(); log.undo(); log.undo(); log.undo()
        try log.push(Stroke(tool: .grow, radius: 0.25, strength: 1,
                            stamps: [Stamp(cx: 0.6, cy: 0.5)]))
        document.log = log.snapshot(pins: [pin])
        let afterBranch = try renderer.render(document: document, source: source.data, fusion: nil, size: size, tween: tween)
        XCTAssertEqual(try pixels(afterBranch), try pixels(exact))
    }

    func testPinPreviewReplacesThePullWithoutCompoundingIt() throws {
        let renderer = try engine(), source = try fixture()
        var log = StrokeLog()
        try log.push(Stroke(tool: .smear, radius: 0.3, strength: 1,
                            stamps: [Stamp(cx: 0.4, cy: 0.5, dx: 0.06, dy: 0.01)]))
        let base = ProjectDocument(log: log.snapshot())
        let original = try renderer.render(document: base, source: source.data, fusion: nil, size: size)
        var pull = Stroke(tool: .pins, radius: 0.1, strength: 1, stamps: [],
                          pinWarp: PinWarp(controls: [MlsControl(su: 0.3, sv: 0.3, tu: 0.4, tv: 0.4),
                                                     MlsControl(su: 0.8, sv: 0.8, tu: 0.8, tv: 0.8)]))
        _ = try renderer.render(document: base, source: source.data, fusion: nil, size: size, activeStroke: pull)
        pull.pinWarp?.controls[0].tu = 0.55
        let preview = try renderer.render(document: base, source: source.data, fusion: nil, size: size, activeStroke: pull)
        try log.push(pull)
        let exact = try engine().render(document: ProjectDocument(log: log.snapshot()),
                                          source: source.data, fusion: nil, size: size)
        XCTAssertEqual(try pixels(preview), try pixels(exact))
        let cancelled = try renderer.render(document: base, source: source.data, fusion: nil, size: size)
        XCTAssertEqual(try pixels(cancelled), try pixels(original))
    }

    func testPinReplaySanitizesImportedControlsLikeAndroid() throws {
        let source = try fixture()
        let imported = PinWarp(controls: [MlsControl(su: -0.2, sv: 0.2, tu: 0.3, tv: -0.4, weight: 0.01),
                                          MlsControl(su: 0.7, sv: 1.2, tu: 1.4, tv: 0.6, weight: 4)],
                               reach: 4, rubber: 1.7)
        let sanitized = PinWarp(controls: [MlsControl(su: 0, sv: 0.2, tu: 0.3, tv: 0, weight: 0.15),
                                           MlsControl(su: 0.7, sv: 1, tu: 1, tv: 0.6, weight: 1)],
                                reach: 3, rubber: 1)
        func document(pins: PinWarp) throws -> ProjectDocument {
            var log = StrokeLog()
            try log.push(Stroke(tool: .pins, radius: 0.1, strength: 1, pinWarp: pins))
            return ProjectDocument(log: log.snapshot())
        }
        let exact = try engine().render(document: document(pins: sanitized), source: source.data, fusion: nil, size: size)
        let replay = try engine().render(document: document(pins: imported), source: source.data, fusion: nil, size: size)
        XCTAssertTrue(try pixels(replay) == pixels(exact), "Imported pin controls must use Android's clamped solver inputs")
        let preview = try engine().render(document: ProjectDocument(), source: source.data, fusion: nil, size: size,
                                         activeStroke: Stroke(tool: .pins, radius: 0.1, strength: 1, pinWarp: imported))
        XCTAssertTrue(try pixels(preview) == pixels(exact), "Active pulls and committed pulls must sanitize identically")
    }

    func testLoadingSecondEndpointDoesNotEvictTheFirstEndpointInUse() throws {
        let renderer = try engine(), source = try fixture()
        var log = StrokeLog()
        var revisions: [Int64] = []
        for x: Float in [0.3, 0.4, 0.5, 0.6] {
            try log.push(Stroke(tool: .smear, radius: 0.25, strength: 1,
                                stamps: [Stamp(cx: x, cy: 0.5, dx: 0.055, dy: 0.01)]))
            revisions.append(log.currentRevision)
        }
        let document = ProjectDocument(log: log.snapshot())
        _ = try renderer.render(document: document, source: source.data, fusion: nil, size: size,
                                tween: WarpTween(from: revisions[0], to: revisions[1], fraction: 0.5, globals: GlobalParams()))
        _ = try renderer.render(document: document, source: source.data, fusion: nil, size: size,
                                tween: WarpTween(from: revisions[2], to: revisions[2], fraction: 0, globals: GlobalParams()))
        let reordered = WarpTween(from: revisions[0], to: revisions[3], fraction: 0.35, globals: GlobalParams())
        let cached = try renderer.render(document: document, source: source.data, fusion: nil, size: size, tween: reordered)
        let exact = try engine().render(document: document, source: source.data, fusion: nil, size: size, tween: reordered)
        XCTAssertEqual(try pixels(cached), try pixels(exact))
    }

    func testIndependentDocumentsCannotReuseAChangedDetachedRewindTarget() throws {
        let renderer = try engine(), source = try fixture()
        func document(delta: Float) -> ProjectDocument {
            let target = Stroke(tool: .smear, radius: 0.3, strength: 1,
                                stamps: [Stamp(cx: 0.45, cy: 0.5, dx: delta, dy: 0)])
            let rewind = Stroke(tool: .rewind, radius: 0.3, strength: 1,
                                stamps: Array(repeating: Stamp(cx: 0.45, cy: 0.5), count: 10), targetRevision: 1)
            let revisions = [StrokeRevisionRecord(id: 0),
                             StrokeRevisionRecord(id: 1, parent: 0, stroke: target),
                             StrokeRevisionRecord(id: 2),
                             StrokeRevisionRecord(id: 3, parent: 2, stroke: rewind)]
            return ProjectDocument(log: StrokeLogSnapshot(revisions: revisions, history: [0, 2, 3], cursor: 2))
        }
        let original = document(delta: 0.075)
        let replacement = document(delta: -0.04)
        let tween = WarpTween(from: 3, to: 3, fraction: 0, globals: GlobalParams())
        _ = try renderer.render(document: original, source: source.data, fusion: nil, size: size, tween: tween)
        XCTAssertThrowsError(try renderer.render(document: original, source: Data([0]), fusion: nil, size: size, tween: tween))
        let cached = try renderer.render(document: replacement, source: source.data, fusion: nil, size: size, tween: tween)
        let exact = try engine().render(document: replacement, source: source.data, fusion: nil, size: size, tween: tween)
        XCTAssertEqual(try pixels(cached), try pixels(exact))
    }

    func testNestedRewindTargetsHaveBoundedReplayWork() throws {
        let renderer = try engine(), source = try fixture()
        var log = StrokeLog()
        try log.push(Stroke(tool: .smear, radius: 0.25, strength: 1,
                            stamps: [Stamp(cx: 0.45, cy: 0.5, dx: 0.05, dy: 0)]))
        let seed = ProjectDocument(log: log.snapshot())
        let expected = try engine().render(document: seed, source: source.data, fusion: nil, size: size)
        for _ in 0..<12 {
            let target = log.currentRevision
            try log.push(Stroke(tool: .rewind, radius: 0.25, strength: 1,
                                stamps: [Stamp(cx: 0.45, cy: 0.5)], targetRevision: target))
        }
        let document = ProjectDocument(log: log.snapshot())
        let result = try renderer.render(document: document, source: source.data, fusion: nil, size: size)
        XCTAssertEqual(try pixels(result), try pixels(expected))
        XCTAssertLessThanOrEqual(renderer.rewindTargetBuildCount, 12,
                                 "Each immutable target should be built once, rather than recursively rebuilding prefixes")
        XCTAssertLessThanOrEqual(renderer.cachedRewindTargetCount, 4)

        var active = Stroke(tool: .rewind, radius: 0.25, strength: 1,
                            stamps: [Stamp(cx: 0.45, cy: 0.5)], targetRevision: log.currentRevision)
        let preview = try renderer.render(document: document, source: source.data, fusion: nil,
                                           size: size, activeStroke: active)
        XCTAssertLessThanOrEqual(renderer.rewindTargetBuildCount, 1)
        active.stamps.append(Stamp(cx: 0.5, cy: 0.5))
        let extended = try renderer.render(document: document, source: source.data, fusion: nil,
                                            size: size, activeStroke: active)
        XCTAssertEqual(renderer.rewindTargetBuildCount, 0,
                       "Extending a live Rewind stroke must reuse its immutable target")
        try log.push(active)
        let committed = try engine().render(document: ProjectDocument(log: log.snapshot()),
                                              source: source.data, fusion: nil, size: size)
        XCTAssertEqual(try pixels(preview), try pixels(expected))
        XCTAssertEqual(try pixels(extended), try pixels(committed))
        XCTAssertLessThanOrEqual(renderer.cachedRewindTargetCount, 4)
    }

    func testRewindTargetCachePreservesDetachedBranchesAndReorderedPins() throws {
        let renderer = try engine(), source = try fixture()
        var log = StrokeLog()
        var pins: [Int64] = [0]
        for index in 0..<8 {
            try log.reset()
            try log.push(Stroke(tool: .smear, radius: 0.3, strength: 1,
                                stamps: [Stamp(cx: 0.35 + Float(index) * 0.04, cy: 0.5,
                                               dx: index % 2 == 0 ? 0.06 : -0.04, dy: 0.01)]))
            let previousBranch = pins.last!
            try log.push(Stroke(tool: .rewind, radius: 0.2, strength: 0.4,
                                stamps: [Stamp(cx: 0.45, cy: 0.5)], targetRevision: previousBranch))
            pins.append(log.currentRevision)
        }
        let document = ProjectDocument(log: log.snapshot(pins: pins))
        for revision in pins.reversed() {
            let tween = WarpTween(from: revision, to: revision, fraction: 0, globals: GlobalParams())
            let cached = try renderer.render(document: document, source: source.data, fusion: nil,
                                              size: size, tween: tween)
            let replay = try engine().render(document: document, source: source.data, fusion: nil,
                                              size: size, tween: tween)
            XCTAssertEqual(try pixels(cached), try pixels(replay))
            XCTAssertLessThanOrEqual(renderer.cachedRewindTargetCount, 4)
        }
    }

    func testFusionFreezeAndCropHaveTheirDocumentSemantics() throws {
        let renderer = try engine(), source = try fixture(), fusion = try fixture(inverted: true)
        var fuseLog = StrokeLog()
        try fuseLog.push(Stroke(tool: .fuse, radius: 0.2, strength: 1,
                                stamps: Array(repeating: Stamp(cx: 0.5, cy: 0.5), count: 20)))
        let fused = try renderer.render(document: ProjectDocument(log: fuseLog.snapshot()),
                                          source: source.data, fusion: fusion.data, size: size)
        XCTAssertNotEqual(try pixels(fused), source.pixels)
        var freezeLog = StrokeLog()
        try freezeLog.push(Stroke(tool: .freeze, radius: 0.3, strength: 1,
                                  stamps: Array(repeating: Stamp(cx: 0.5, cy: 0.5), count: 30)))
        try freezeLog.push(Stroke(tool: .smear, radius: 0.1, strength: 1,
                                  stamps: [Stamp(cx: 0.5, cy: 0.5, dx: 0.1, dy: 0)]))
        let protected = try renderer.render(document: ProjectDocument(log: freezeLog.snapshot()),
                                              source: source.data, fusion: nil, size: size)
        let protectedPixels = try pixels(protected)
        let center = ((height / 2) * width + width / 2) * 4
        XCTAssertEqual(protectedPixels[center..<(center + 4)], source.pixels[center..<(center + 4)])
        let crop = CropRect(left: 0.25, top: 0.25, right: 0.75, bottom: 0.75)
        let decoded = try WarpEngine.decodedImage(data: source.data, crop: crop, maxDimension: 64)
        XCTAssertEqual(decoded.width, 64)
        XCTAssertEqual(decoded.height, 48)
        let cropped = try renderer.render(document: ProjectDocument(crop: crop), source: source.data,
                                            fusion: nil, size: CGSize(width: 64, height: 48))
        let expectedStart = ((height / 4) * width + width / 4) * 4
        XCTAssertEqual(try pixels(cropped).prefix(4), source.pixels[expectedStart..<(expectedStart + 4)])
    }
}
