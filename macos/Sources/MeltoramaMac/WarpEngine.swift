import AppKit
import CoreGraphics
import ImageIO
import MeltoramaCore
import OpenGL.GL3

/// A field tween uses independent immutable revisions, including undo branches.
struct WarpTween: Sendable {
    var from: Int64
    var to: Int64
    var fraction: Float
    var globals: GlobalParams
}

enum WarpError: LocalizedError {
    case unavailable, invalidImage, invalidSize, invalidRevision(Int64), renderingFailed
    case shader(String), framebuffer

    var errorDescription: String? {
        switch self {
        case .unavailable: return L("This Mac could not create the photo rendering context.")
        case .invalidImage: return L("The photo could not be decoded. Choose another image.")
        case .invalidSize: return L("The requested image is larger than this Mac can render.")
        case .invalidRevision(let id): return LF("The document references a missing edit (%@).", String(id))
        case .renderingFailed: return L("The photo could not be rendered. Try a smaller export size.")
        case .shader(let message): return LF("The photo renderer could not start: %@", message)
        case .framebuffer: return L("This Mac could not allocate the photo rendering surface.")
        }
    }
}

/// The Android engine's GLSL runs in an isolated desktop OpenGL context.
/// All context access is serialized; the document remains the source of truth.
/// Nothing in this class depends on a window, and preview and export call the
/// same replay/stamp/render path. The GLSL resources preserve the Android math.
final class WarpEngine: @unchecked Sendable {
    private let lock = NSLock()
    private let context: NSOpenGLContext
    private var stampProgram: GLuint = 0
    private var warpProgram: GLuint = 0
    private var vao: GLuint = 0
    private var quad: GLuint = 0
    private var sourceTexture: GLuint = 0
    private var fusionTexture: GLuint = 0
    private var cachedSource: Data?
    private var cachedFusion: Data?
    private var fusionCacheValid = false
    private var cachedCrop: CropRect?
    private var decodedLongSide = 0
    private var sourceWidth = 0
    private var sourceHeight = 0
    private var liveField: FieldPair?
    private var cachedStrokes: [Stroke] = []
    private var knownRevisions: [Int64: StrokeRevisionRecord] = [:]
    private var pinBase: (strokes: [Stroke], field: FieldPair)?
    private var endpoints: [(revision: Int64, strokes: [Stroke], field: FieldPair)] = []
    private var recalling = Set<Int64>()
    private var outputTexture: GLuint = 0
    private var outputFramebuffer: GLuint = 0
    private var outputWidth = 0
    private var outputHeight = 0
    private(set) var maxTextureSize = 4096

    init() throws {
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            UInt32(NSOpenGLPFAAccelerated), UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFAAlphaSize), 8, 0
        ]
        guard let format = NSOpenGLPixelFormat(attributes: attributes),
              let context = NSOpenGLContext(format: format, share: nil) else {
            throw WarpError.unavailable
        }
        self.context = context
        context.makeCurrentContext()
        defer { NSOpenGLContext.clearCurrentContext() }
        var maximum: GLint = 0
        glGetIntegerv(GLenum(GL_MAX_TEXTURE_SIZE), &maximum)
        guard maximum > 0 else { throw WarpError.unavailable }
        maxTextureSize = Int(maximum)
        stampProgram = try Self.program(vertex: "quad_vert", fragment: "stamp_frag")
        warpProgram = try Self.program(vertex: "warp_vert", fragment: "warp_frag")
        glGenVertexArrays(1, &vao)
        glBindVertexArray(vao)
        glGenBuffers(1, &quad)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), quad)
        let vertices: [GLfloat] = [-1, -1, 1, -1, -1, 1, 1, 1]
        vertices.withUnsafeBytes { glBufferData(GLenum(GL_ARRAY_BUFFER), $0.count, $0.baseAddress, GLenum(GL_STATIC_DRAW)) }
        glEnableVertexAttribArray(0)
        glVertexAttribPointer(0, 2, GLenum(GL_FLOAT), GLboolean(GL_FALSE), 0, nil)
        glDisable(GLenum(GL_DEPTH_TEST))
        glDisable(GLenum(GL_BLEND))
    }

    deinit {
        context.makeCurrentContext()
        liveField?.delete()
        pinBase?.field.delete()
        endpoints.forEach { $0.field.delete() }
        glDeleteProgram(stampProgram)
        glDeleteProgram(warpProgram)
        glDeleteVertexArrays(1, &vao)
        glDeleteBuffers(1, &quad)
        for var texture in [sourceTexture, fusionTexture, outputTexture] where texture != 0 {
            glDeleteTextures(1, &texture)
        }
        glDeleteFramebuffers(1, &outputFramebuffer)
        NSOpenGLContext.clearCurrentContext()
    }

    /// Output dimensions are explicit. A requested full-resolution export is
    /// decoded at that resolution up to the hardware texture limit, while the
    /// smooth displacement field retains the shared 1024-texel Android cap.
    func render(document: ProjectDocument, source: Data, fusion: Data?, size: CGSize,
                time: Double = 0, tween: WarpTween? = nil, activeStroke: Stroke? = nil,
                showFreeze: Bool = false) throws -> CGImage {
        lock.lock()
        defer { lock.unlock() }
        context.makeCurrentContext()
        defer { NSOpenGLContext.clearCurrentContext() }
        defer {
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
            // A field must not remain bound while the next replay writes it,
            // including when a decode, replay, or readback fails.
            for unit in 0...3 { bind(0, unit: unit) }
        }
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0,
              size.width <= CGFloat(maxTextureSize), size.height <= CGFloat(maxTextureSize) else {
            throw WarpError.invalidSize
        }
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        let decodeCap = min(maxTextureSize, max(2048, width, height))
        try prepareImages(source: source, fusion: fusion, crop: document.crop, decodeCap: decodeCap)
        guard let live = liveField else { throw WarpError.framebuffer }
        let aspect = Float(sourceWidth) / Float(sourceHeight)
        if let activeStroke, activeStroke.hasContent, !activeStroke.isValid {
            throw WarpError.renderingFailed
        }
        let committed = try document.log.materialize()
        // IDs are immutable within one document, but another project can use
        // the same photo and IDs for different edits. Direct stroke equality
        // cannot detect a Rewind whose detached target changed underneath it.
        if document.log.revisions.contains(where: { record in
            knownRevisions[record.id].map { $0 != record } ?? false
        }) {
            live.clear()
            cachedStrokes.removeAll()
            pinBase?.field.delete()
            pinBase = nil
            endpoints.forEach { $0.field.delete() }
            endpoints.removeAll()
            knownRevisions.removeAll()
        }
        for record in document.log.revisions { knownRevisions[record.id] = record }
        let strokes = committed + (activeStroke.flatMap { $0.hasContent ? [$0] : nil } ?? [])
        if let activeStroke, activeStroke.pinWarp != nil {
            // A moving Taffy Pin changes a whole analytic pass rather than
            // appending stamps. Preserve its pre-gesture field so dragging a
            // pin never replays an increasingly long document on every frame.
            if pinBase?.strokes != committed {
                pinBase?.field.delete()
                pinBase = nil
                try updateLive(committed, field: live, document: document, aspect: aspect)
                let base = try FieldPair(width: live.width, height: live.height)
                base.restore(from: live)
                pinBase = (committed, base)
            }
            if let pinBase { live.restore(from: pinBase.field) }
            try replay(activeStroke, into: live, document: document, aspect: aspect)
            cachedStrokes = strokes
        } else {
            if let pinBase {
                if committed == pinBase.strokes {
                    live.restore(from: pinBase.field)
                    cachedStrokes = committed
                }
                pinBase.field.delete()
                self.pinBase = nil
            }
            try updateLive(strokes, field: live, document: document, aspect: aspect)
        }
        let a: FieldPair
        let b: FieldPair
        let globals: GlobalParams
        let fraction: Float
        if let tween {
            a = try endpoint(tween.from, document: document, aspect: aspect)
            b = try endpoint(tween.to, document: document, aspect: aspect)
            globals = tween.globals
            fraction = min(1.35, max(0, tween.fraction))
        } else {
            a = live
            b = live
            // The preview clock is supplied by the controller. Exports pass
            // explicit tween globals, so rendering never consults wall time.
            globals = leversAt(base: document.globals, wobble: document.wobble, phase: Float(time))
            fraction = 0
        }
        try prepareOutput(width: width, height: height)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), outputFramebuffer)
        glViewport(0, 0, GLsizei(width), GLsizei(height))
        glDisable(GLenum(GL_SCISSOR_TEST))
        glBindVertexArray(vao)
        glUseProgram(warpProgram)
        uniform4(warpProgram, "u_rectPx", 0, Float(height), Float(width), -Float(height))
        uniform2(warpProgram, "u_viewport", Float(width), Float(height))
        uniform4(warpProgram, "u_view", 1, 0, 0, 0)
        uniform1i(warpProgram, "u_image", 0)
        uniform1i(warpProgram, "u_field", 1)
        uniform1i(warpProgram, "u_fieldB", 2)
        uniform1i(warpProgram, "u_imageB", 3)
        uniform1(warpProgram, "u_tween", fraction)
        uniform1(warpProgram, "u_hasB", fusionTexture == 0 ? 0 : 1)
        uniform1(warpProgram, "u_gAspect", aspect)
        let values = globals.values
        values.withUnsafeBufferPointer { glUniform1fv(location(warpProgram, "u_g"), 6, $0.baseAddress) }
        let lenses = Array(globals.lenses.filter { $0.strength != 0 && $0.radius > 0 }.prefix(4))
        uniform1i(warpProgram, "u_lensCount", GLint(lenses.count))
        if !lenses.isEmpty {
            let packed = lenses.flatMap { [$0.u, $0.v, $0.radius, $0.strength] }
            let types = lenses.map { GLint($0.type.shaderID) }
            packed.withUnsafeBufferPointer { glUniform4fv(location(warpProgram, "u_lens"), GLsizei(lenses.count), $0.baseAddress) }
            types.withUnsafeBufferPointer { glUniform1iv(location(warpProgram, "u_lensType"), GLsizei(lenses.count), $0.baseAddress) }
        }
        uniform1(warpProgram, "u_showFreeze", showFreeze ? 1 : 0)
        bind(sourceTexture, unit: 0)
        bind(a.readTexture, unit: 1)
        bind(b.readTexture, unit: 2)
        bind(fusionTexture == 0 ? sourceTexture : fusionTexture, unit: 3)
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        var pixels = Data(count: width * height * 4)
        glPixelStorei(GLenum(GL_PACK_ALIGNMENT), 1)
        pixels.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            glReadPixels(0, 0, GLsizei(width), GLsizei(height), GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), bytes.baseAddress)
        }
        guard glGetError() == GLenum(GL_NO_ERROR) else { throw WarpError.renderingFailed }
        guard let provider = CGDataProvider(data: pixels as CFData),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let result = CGImage(width: width, height: height, bitsPerComponent: 8,
                                   bitsPerPixel: 32, bytesPerRow: width * 4,
                                   space: colorSpace,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true,
                                   intent: .defaultIntent) else { throw WarpError.invalidImage }
        return result
    }

    static func imageSize(data: Data, crop: CropRect? = nil) throws -> CGSize {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let rawWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let rawHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber else { throw WarpError.invalidImage }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        let width = rotated ? rawHeight.intValue : rawWidth.intValue
        let height = rotated ? rawWidth.intValue : rawHeight.intValue
        guard width > 0, height > 0 else { throw WarpError.invalidImage }
        guard crop?.isValid ?? true else { throw WarpError.invalidSize }
        if let crop, !crop.isFullFrame {
            let rect = try crop.pixelRect(width: width, height: height)
            return CGSize(width: rect.width, height: rect.height)
        }
        return CGSize(width: width, height: height)
    }

    /// ImageIO performs EXIF orientation before crop. Crop coordinates belong
    /// to the oriented original, and Fusion is center-cover-cropped afterward.
    static func decodedImage(data: Data, crop: CropRect? = nil, maxDimension: Int = 4096,
                             targetAspect: Float? = nil) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw WarpError.invalidImage }
        guard maxDimension > 0, crop?.isValid ?? true else { throw WarpError.invalidSize }
        // Thumbnailing happens before cropping, so compensate for the removed
        // area. Otherwise a full-resolution cropped export silently samples a
        // smaller thumbnail and scales it back up to the requested size.
        let original = try imageSize(data: data)
        let cropped = try imageSize(data: data, crop: crop)
        let retainedLongSide = max(cropped.width, cropped.height) / max(original.width, original.height)
        let decodeLimit = min(max(original.width, original.height),
                              ceil(CGFloat(maxDimension) / retainedLongSide))
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(decodeLimit),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard var image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw WarpError.invalidImage
        }
        if let crop, !crop.isFullFrame {
            let pixels = try crop.pixelRect(width: image.width, height: image.height)
            let rect = CGRect(x: pixels.x, y: pixels.y, width: pixels.width, height: pixels.height)
            guard let cropped = image.cropping(to: rect) else { throw WarpError.invalidImage }
            image = cropped
        }
        if let aspect = targetAspect, aspect > 0 {
            let width = image.width
            let height = image.height
            let sourceAspect = Float(width) / Float(height)
            let rect: CGRect
            if sourceAspect > aspect {
                let cropWidth = max(1, min(width, Int(Float(height) * aspect)))
                rect = CGRect(x: (width - cropWidth) / 2, y: 0, width: cropWidth, height: height)
            } else {
                let cropHeight = max(1, min(height, Int(Float(width) / aspect)))
                rect = CGRect(x: 0, y: (height - cropHeight) / 2, width: width, height: cropHeight)
            }
            guard let cropped = image.cropping(to: rect) else { throw WarpError.invalidImage }
            image = cropped
        }
        return image
    }

    private func prepareImages(source: Data, fusion: Data?, crop: CropRect?, decodeCap: Int) throws {
        let changedDocumentImage = cachedSource != source || cachedCrop != crop
        let changedSource = changedDocumentImage || decodedLongSide < decodeCap
        if changedSource {
            let image = try Self.decodedImage(data: source, crop: crop, maxDimension: decodeCap)
            let newTexture = try upload(image)
            // The old GPU fields still belong to this table until replacement
            // succeeds. A failed decode must preserve both image and identity.
            if changedDocumentImage { knownRevisions.removeAll() }
            if sourceTexture != 0 { glDeleteTextures(1, &sourceTexture) }
            sourceTexture = newTexture
            sourceWidth = image.width
            sourceHeight = image.height
            cachedSource = source
            cachedCrop = crop
            decodedLongSide = decodeCap
            let scale = min(1, 1024.0 / Double(max(image.width, image.height)))
            let fieldWidth = max(2, Int((Double(image.width) * scale).rounded()))
            let fieldHeight = max(2, Int((Double(image.height) * scale).rounded()))
            // Decode resolution can grow for export without changing the
            // document field geometry. Recreate only if the grid did change.
            if liveField?.width != fieldWidth || liveField?.height != fieldHeight {
                liveField?.delete()
                pinBase?.field.delete()
                pinBase = nil
                liveField = try FieldPair(width: fieldWidth, height: fieldHeight)
                endpoints.forEach { $0.field.delete() }
                endpoints.removeAll()
                cachedStrokes.removeAll()
            } else if changedDocumentImage {
                liveField?.clear()
                pinBase?.field.delete()
                pinBase = nil
                cachedStrokes.removeAll()
                endpoints.forEach { $0.field.delete() }
                endpoints.removeAll()
            }
        }
        // A successful source change also changes B's cover crop or decode
        // resolution. If B fails to load, retry must rebuild that geometry.
        if changedSource { fusionCacheValid = false }
        if !fusionCacheValid || cachedFusion != fusion {
            var replacement: GLuint = 0
            if let fusion {
                let image = try Self.decodedImage(data: fusion, maxDimension: decodeCap,
                                                  targetAspect: Float(sourceWidth) / Float(sourceHeight))
                replacement = try upload(image)
            }
            // Decode and upload before swapping, so a bad replacement cannot
            // discard the previously valid texture while its cache key survives.
            if fusionTexture != 0 { glDeleteTextures(1, &fusionTexture) }
            fusionTexture = replacement
            cachedFusion = fusion
            fusionCacheValid = true
        }
    }

    private func updateLive(_ strokes: [Stroke], field: FieldPair, document: ProjectDocument,
                            aspect: Float) throws {
        if strokes == cachedStrokes { return }
        var replayFrom = 0
        // During a drag the final stroke grows. Keep the already stamped
        // prefix and apply only new stamps, then record the new immutable copy.
        if strokes.count >= cachedStrokes.count,
           Array(strokes.prefix(cachedStrokes.count)) == cachedStrokes {
            replayFrom = cachedStrokes.count
        } else if strokes.count == cachedStrokes.count,
                  let previous = cachedStrokes.last, let current = strokes.last,
                  Array(strokes.dropLast()) == Array(cachedStrokes.dropLast()),
                  previous.tool == current.tool, previous.radius == current.radius,
                  previous.strength == current.strength, previous.targetRevision == current.targetRevision,
                  previous.pinWarp == nil, current.pinWarp == nil,
                  current.stamps.count >= previous.stamps.count,
                  Array(current.stamps.prefix(previous.stamps.count)) == previous.stamps {
            try stamp(current, stamps: Array(current.stamps.dropFirst(previous.stamps.count)),
                      into: field, document: document, aspect: aspect)
            cachedStrokes = strokes
            return
        } else {
            field.clear()
        }
        for stroke in strokes.dropFirst(replayFrom) {
            try replay(stroke, into: field, document: document, aspect: aspect)
        }
        cachedStrokes = strokes
    }

    private func endpoint(_ revision: Int64, document: ProjectDocument, aspect: Float) throws -> FieldPair {
        let strokes = try document.log.materialize(revision: revision)
        if let index = endpoints.firstIndex(where: { $0.revision == revision && $0.strokes == strokes }) {
            // A is held by render while B is materialized. Touching A makes
            // it most recent, so loading B cannot evict the field in use.
            let found = endpoints.remove(at: index)
            endpoints.append(found)
            return found.field
        }
        guard let live = liveField else { throw WarpError.framebuffer }
        let field = try FieldPair(width: live.width, height: live.height)
        do {
            for stroke in strokes {
                try replay(stroke, into: field, document: document, aspect: aspect)
            }
        } catch {
            field.delete()
            throw error
        }
        // Three slots retain the shared endpoint of neighboring segments.
        if endpoints.count >= 3 { endpoints.removeFirst().field.delete() }
        endpoints.append((revision, strokes, field))
        return field
    }

    private func replay(_ stroke: Stroke, into field: FieldPair, document: ProjectDocument,
                        aspect: Float) throws {
        if let pins = stroke.pinWarp {
            guard !pins.controls.isEmpty else { return }
            // Mirror Android PinWarp.sanitized at replay. Valid documents can
            // contain finite controls outside these solver bounds, and dragging
            // a pin beyond the photo must use the same clamped inputs as export.
            func bounded(_ value: Float, fallback: Float, lower: Float, upper: Float) -> Float {
                min(upper, max(lower, value.isFinite ? value : fallback))
            }
            glUseProgram(stampProgram)
            glBindVertexArray(vao)
            uniform1i(stampProgram, "u_mode", 12)
            uniform1(stampProgram, "u_aspect", aspect)
            uniform1i(stampProgram, "u_field", 0)
            uniform1i(stampProgram, "u_target", 1)
            bind(sourceTexture, unit: 1)
            let controls = pins.controls.prefix(PinWarp.maxControls).map { control in
                MlsControl(su: bounded(control.su, fallback: 0.5, lower: 0, upper: 1),
                           sv: bounded(control.sv, fallback: 0.5, lower: 0, upper: 1),
                           tu: bounded(control.tu, fallback: 0.5, lower: 0, upper: 1),
                           tv: bounded(control.tv, fallback: 0.5, lower: 0, upper: 1),
                           weight: bounded(control.weight, fallback: 1, lower: 0.15, upper: 1))
            }
            let values = controls.flatMap { [$0.su, $0.sv, $0.tu, $0.tv] }
            let weights = controls.map { $0.weight }
            values.withUnsafeBufferPointer { glUniform4fv(location(stampProgram, "u_pin"), GLsizei(controls.count), $0.baseAddress) }
            weights.withUnsafeBufferPointer { glUniform1fv(location(stampProgram, "u_pinWeight"), GLsizei(controls.count), $0.baseAddress) }
            uniform1i(stampProgram, "u_pinCount", GLint(controls.count))
            uniform1(stampProgram, "u_pinReach", bounded(pins.reach, fallback: 1, lower: 0.5, upper: 3))
            uniform1(stampProgram, "u_pinRubber", bounded(pins.rubber, fallback: 0, lower: 0, upper: 1))
            field.pass(rect: field.fullRect) { texture in
                bind(texture, unit: 0)
                glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
            }
            bind(0, unit: 0)
            bind(0, unit: 1)
            return
        }
        try stamp(stroke, stamps: stroke.stamps, into: field, document: document, aspect: aspect)
    }

    private func stamp(_ stroke: Stroke, stamps: [Stamp], into field: FieldPair,
                       document: ProjectDocument, aspect: Float) throws {
        guard !stamps.isEmpty, stroke.radius > 0, stroke.radius.isFinite else { return }
        // Materialize BEFORE setting uniforms. Recursive Rewind replay sets
        // every uniform, and setting them first would leave the outer stroke
        // using the final inner stroke's brush parameters.
        var recall: FieldPair?
        if let revision = stroke.targetRevision {
            guard recalling.insert(revision).inserted else { throw WarpError.invalidRevision(revision) }
            defer { recalling.remove(revision) }
            let target = try FieldPair(width: field.width, height: field.height)
            do {
                for prior in try document.log.materialize(revision: revision) {
                    try replay(prior, into: target, document: document, aspect: aspect)
                }
            } catch {
                target.delete()
                throw error
            }
            recall = target
        }
        defer { recall?.delete() }
        glUseProgram(stampProgram)
        glBindVertexArray(vao)
        uniform1(stampProgram, "u_radius", stroke.radius)
        uniform1(stampProgram, "u_strength", stroke.strength)
        uniform1(stampProgram, "u_aspect", aspect)
        uniform1i(stampProgram, "u_mode", GLint(stroke.tool.mode.rawValue))
        uniform1i(stampProgram, "u_profile", GLint(stroke.tool.profile.rawValue))
        uniform1i(stampProgram, "u_guarded", [.erase, .guardMask].contains(stroke.tool.mode) ? 0 : 1)
        uniform2(stampProgram, "u_fieldTexel", 1 / Float(field.width), 1 / Float(field.height))
        uniform1i(stampProgram, "u_field", 0)
        uniform1i(stampProgram, "u_target", 1)
        // Even an untaken sampler branch needs a complete texture on Apple's
        // GL driver. An immutable source texture is a safe placeholder; the
        // changing field itself would introduce framebuffer feedback.
        bind(recall?.readTexture ?? sourceTexture, unit: 1)
        for point in stamps {
            let rect = StampRect(point: point, radius: stroke.radius, aspect: aspect,
                                 width: field.width, height: field.height,
                                 drip: stroke.tool.profile == .drip)
            field.pass(rect: rect) { texture in
                bind(texture, unit: 0)
                uniform2(stampProgram, "u_center", point.cx, point.cy)
                uniform2(stampProgram, "u_delta", point.dx, point.dy)
                glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
            }
        }
        bind(0, unit: 1)
        bind(0, unit: 0)
    }

    private func prepareOutput(width: Int, height: Int) throws {
        if outputWidth == width && outputHeight == height { return }
        if outputTexture != 0 { glDeleteTextures(1, &outputTexture) }
        if outputFramebuffer != 0 { glDeleteFramebuffers(1, &outputFramebuffer) }
        outputTexture = Self.texture(width: width, height: height, internalFormat: GL_RGBA8, type: GL_UNSIGNED_BYTE)
        glGenFramebuffers(1, &outputFramebuffer)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), outputFramebuffer)
        glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0), GLenum(GL_TEXTURE_2D), outputTexture, 0)
        guard glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) == GLenum(GL_FRAMEBUFFER_COMPLETE) else { throw WarpError.framebuffer }
        outputWidth = width
        outputHeight = height
    }

    private func upload(_ image: CGImage) throws -> GLuint {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw WarpError.invalidImage }
        let succeeded = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let bitmap = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                         bitsPerComponent: 8, bytesPerRow: image.width * 4, space: colorSpace,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // CGImage's provider rows and GL texture rows both start with
            // image UV v=0. CGContext draws a CGImage into that row order
            // already; an AppKit-style y flip would invert the photo.
            bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard succeeded else { throw WarpError.invalidImage }
        let texture = Self.texture(width: image.width, height: image.height,
                                   internalFormat: GL_RGBA8, type: GL_UNSIGNED_BYTE)
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        glPixelStorei(GLenum(GL_UNPACK_ALIGNMENT), 1)
        pixels.withUnsafeBytes {
            glTexSubImage2D(GLenum(GL_TEXTURE_2D), 0, 0, 0, GLsizei(image.width), GLsizei(image.height),
                            GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), $0.baseAddress)
        }
        guard glGetError() == GLenum(GL_NO_ERROR) else {
            var rejectedTexture = texture
            glDeleteTextures(1, &rejectedTexture)
            throw WarpError.renderingFailed
        }
        return texture
    }

    fileprivate static func texture(width: Int, height: Int, internalFormat: Int32, type: Int32) -> GLuint {
        var texture: GLuint = 0
        glGenTextures(1, &texture)
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, internalFormat, GLsizei(width), GLsizei(height), 0,
                     GLenum(GL_RGBA), GLenum(type), nil)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER), GL_LINEAR)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
        return texture
    }

    private static func shaderSource(_ name: String) throws -> String {
        // SwiftPM stores copied resources beside its generated resource bundle;
        // the packaging script places that bundle inside the installed .app.
        guard let url = ResourceBundle.url(forResource: name, withExtension: "glsl", subdirectory: "Shaders")
                ?? ResourceBundle.url(forResource: name, withExtension: "glsl") else {
            throw WarpError.shader("Missing bundled shader \(name).")
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private static func compile(_ source: String, type: GLenum) throws -> GLuint {
        let shader = glCreateShader(type)
        source.withCString { pointer in
            var pointer: UnsafePointer<GLchar>? = pointer
            glShaderSource(shader, 1, &pointer, nil)
        }
        glCompileShader(shader)
        var status: GLint = 0
        glGetShaderiv(shader, GLenum(GL_COMPILE_STATUS), &status)
        guard status != 0 else {
            var bytes = [GLchar](repeating: 0, count: 8192)
            var length: GLsizei = 0
            glGetShaderInfoLog(shader, GLsizei(bytes.count), &length, &bytes)
            glDeleteShader(shader)
            throw WarpError.shader(String(cString: bytes))
        }
        return shader
    }

    private static func program(vertex: String, fragment: String) throws -> GLuint {
        let vs = try compile(shaderSource(vertex), type: GLenum(GL_VERTEX_SHADER))
        defer { glDeleteShader(vs) }
        let fs = try compile(shaderSource(fragment), type: GLenum(GL_FRAGMENT_SHADER))
        defer { glDeleteShader(fs) }
        let program = glCreateProgram()
        glAttachShader(program, vs)
        glAttachShader(program, fs)
        "a_pos".withCString { glBindAttribLocation(program, 0, $0) }
        glLinkProgram(program)
        var status: GLint = 0
        glGetProgramiv(program, GLenum(GL_LINK_STATUS), &status)
        guard status != 0 else {
            var bytes = [GLchar](repeating: 0, count: 8192)
            var length: GLsizei = 0
            glGetProgramInfoLog(program, GLsizei(bytes.count), &length, &bytes)
            glDeleteProgram(program)
            throw WarpError.shader(String(cString: bytes))
        }
        return program
    }

    private func bind(_ texture: GLuint, unit: Int) {
        glActiveTexture(GLenum(GL_TEXTURE0) + GLenum(unit))
        glBindTexture(GLenum(GL_TEXTURE_2D), texture)
    }

    private func location(_ program: GLuint, _ name: String) -> GLint {
        name.withCString { glGetUniformLocation(program, $0) }
    }

    private func uniform1(_ program: GLuint, _ name: String, _ x: Float) { glUniform1f(location(program, name), x) }
    private func uniform1i(_ program: GLuint, _ name: String, _ x: GLint) { glUniform1i(location(program, name), x) }
    private func uniform2(_ program: GLuint, _ name: String, _ x: Float, _ y: Float) { glUniform2f(location(program, name), x, y) }
    private func uniform4(_ program: GLuint, _ name: String, _ x: Float, _ y: Float, _ z: Float, _ w: Float) {
        glUniform4f(location(program, name), x, y, z, w)
    }
}

private struct StampRect {
    var x0: Int
    var y0: Int
    var x1: Int
    var y1: Int
    var isEmpty: Bool { x1 <= x0 || y1 <= y0 }
    func contains(_ other: StampRect) -> Bool {
        other.isEmpty || (x0 <= other.x0 && y0 <= other.y0 && x1 >= other.x1 && y1 >= other.y1)
    }

    init(x0: Int, y0: Int, x1: Int, y1: Int) { self.x0 = x0; self.y0 = y0; self.x1 = x1; self.y1 = y1 }

    init(point: Stamp, radius: Float, aspect: Float, width: Int, height: Int, drip: Bool) {
        func edge(_ coordinate: Float, _ dimension: Int, down: Bool) -> Int {
            let safe = min(1e9, max(-1e9, coordinate * Float(dimension)))
            let value = down ? floor(safe) - 2 : ceil(safe) + 2
            return min(dimension, max(0, Int(value)))
        }
        guard point.cx.isFinite, point.cy.isFinite else {
            self.init(x0: 0, y0: 0, x1: 0, y1: 0)
            return
        }
        self.init(x0: edge(point.cx - radius / aspect, width, down: true),
                  y0: edge(point.cy - radius, height, down: true),
                  x1: edge(point.cx + radius / aspect, width, down: false),
                  y1: edge(point.cy + radius / (drip ? 0.45 : 1), height, down: false))
    }
}

/// Ping-pong scissored field passes retain the Android stale-rect invariant.
/// Only the preceding changed region must be repaired before the next stamp.
private final class FieldPair {
    let width: Int
    let height: Int
    private var textures: [GLuint] = [0, 0]
    private var framebuffers: [GLuint] = [0, 0]
    private var readIndex = 0
    private var stale = StampRect(x0: 0, y0: 0, x1: 0, y1: 0)
    var readTexture: GLuint { textures[readIndex] }
    var fullRect: StampRect { StampRect(x0: 0, y0: 0, x1: width, y1: height) }

    init(width: Int, height: Int) throws {
        self.width = width
        self.height = height
        glGenFramebuffers(2, &framebuffers)
        for index in 0..<2 {
            textures[index] = WarpEngine.texture(width: width, height: height,
                                                  internalFormat: GL_RGBA16F, type: GL_HALF_FLOAT)
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffers[index])
            glFramebufferTexture2D(GLenum(GL_FRAMEBUFFER), GLenum(GL_COLOR_ATTACHMENT0),
                                   GLenum(GL_TEXTURE_2D), textures[index], 0)
            guard glCheckFramebufferStatus(GLenum(GL_FRAMEBUFFER)) == GLenum(GL_FRAMEBUFFER_COMPLETE) else {
                delete()
                throw WarpError.framebuffer
            }
        }
        clear()
    }

    func clear() {
        glDisable(GLenum(GL_SCISSOR_TEST))
        for framebuffer in framebuffers {
            glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffer)
            glClearColor(0, 0, 0, 0)
            glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        }
        stale = StampRect(x0: 0, y0: 0, x1: 0, y1: 0)
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }

    func restore(from other: FieldPair) {
        precondition(width == other.width && height == other.height)
        glDisable(GLenum(GL_SCISSOR_TEST))
        glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), other.framebuffers[other.readIndex])
        glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), framebuffers[readIndex])
        glBlitFramebuffer(0, 0, GLint(width), GLint(height), 0, 0, GLint(width), GLint(height),
                          GLbitfield(GL_COLOR_BUFFER_BIT), GLenum(GL_NEAREST))
        stale = fullRect
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }

    func pass(rect: StampRect, draw: (GLuint) -> Void) {
        guard !rect.isEmpty else { return }
        glDisable(GLenum(GL_SCISSOR_TEST))
        if !stale.isEmpty && !rect.contains(stale) {
            glBindFramebuffer(GLenum(GL_READ_FRAMEBUFFER), framebuffers[readIndex])
            glBindFramebuffer(GLenum(GL_DRAW_FRAMEBUFFER), framebuffers[1 - readIndex])
            glBlitFramebuffer(GLint(stale.x0), GLint(stale.y0), GLint(stale.x1), GLint(stale.y1),
                              GLint(stale.x0), GLint(stale.y0), GLint(stale.x1), GLint(stale.y1),
                              GLbitfield(GL_COLOR_BUFFER_BIT), GLenum(GL_NEAREST))
        }
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), framebuffers[1 - readIndex])
        glViewport(0, 0, GLsizei(width), GLsizei(height))
        glEnable(GLenum(GL_SCISSOR_TEST))
        glScissor(GLint(rect.x0), GLint(rect.y0), GLsizei(rect.x1 - rect.x0), GLsizei(rect.y1 - rect.y0))
        draw(readTexture)
        glDisable(GLenum(GL_SCISSOR_TEST))
        readIndex = 1 - readIndex
        stale = rect
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), 0)
    }

    func delete() {
        glDeleteTextures(2, &textures)
        glDeleteFramebuffers(2, &framebuffers)
        textures = [0, 0]
        framebuffers = [0, 0]
    }
}
