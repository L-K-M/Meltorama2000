import CryptoKit
import MeltoramaCore
import SwiftUI

struct FrameThumbnail: View {
    @ObservedObject var session: EditorSession
    let index: Int
    @State private var image: CGImage?

    private var request: FrameThumbnailRequest? {
        guard session.hasPhoto, session.state.keyframes.indices.contains(index) else { return nil }
        return FrameThumbnailRequest(document: session.state, source: session.source,
                                     fusion: session.fusion, pin: session.state.keyframes[index])
    }

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            if let image {
                Image(decorative: image, scale: 2).resizable().scaledToFit()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }
        .frame(width: 80, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityHidden(true)
        .task(id: request) {
            guard let request else { image = nil; return }
            let result = await FrameThumbnailRenderer.shared.image(for: request)
            guard !Task.isCancelled else { return }
            image = result
        }
    }
}

struct FrameThumbnailRequest: Equatable, Sendable {
    let document: ProjectDocument
    let source: Data
    let fusion: Data?
    let pin: KeyframeRecord
}

/// All frame cards share one background renderer, instead of allocating a GL
/// context per card. Cache identity includes source bytes and the full reachable
/// revision DAG, so a detached Rewind target cannot masquerade as another pin.
final class FrameThumbnailRenderer: @unchecked Sendable {
    static let shared = FrameThumbnailRenderer()
    private let queue = DispatchQueue(label: "ch.lkmc.goo.frame-thumbnails", qos: .utility)
    private var renderer: WarpEngine?
    private var previousSource: (Data, Data)?
    private var previousFusion: (Data, Data)?
    private let cache = NSCache<NSString, ThumbnailImage>()

    private init() {
        cache.countLimit = 256
        cache.totalCostLimit = 8 * 1024 * 1024
    }

    func image(for request: FrameThumbnailRequest) async -> CGImage? {
        let cancellation = ThumbnailCancellation()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async {
                    guard !cancellation.isCancelled else {
                        continuation.resume(returning: nil)
                        return
                    }
                    do {
                        let document = try Self.pinnedDocument(for: request)
                        let key = try self.cacheKey(document: document, request: request)
                        if let cached = self.cache.object(forKey: key) {
                            continuation.resume(returning: cached.image)
                            return
                        }
                        guard !cancellation.isCancelled else {
                            continuation.resume(returning: nil)
                            return
                        }
                        if self.renderer == nil { self.renderer = try WarpEngine() }
                        let original = try WarpEngine.imageSize(data: request.source, crop: document.crop)
                        let scale = min(1, 160 / original.width, 112 / original.height)
                        let size = CGSize(width: max(1, (original.width * scale).rounded()),
                                          height: max(1, (original.height * scale).rounded()))
                        let image = try self.renderer!.render(document: document, source: request.source,
                                                              fusion: request.fusion, size: size)
                        self.cache.setObject(ThumbnailImage(image), forKey: key,
                                             cost: image.width * image.height * 4)
                        continuation.resume(returning: image)
                    } catch {
                        // A thumbnail is a disposable presentation cache. The
                        // main canvas reports document/render errors to the user.
                        continuation.resume(returning: nil)
                    }
                }
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    static func pinnedDocument(for request: FrameThumbnailRequest) throws -> ProjectDocument {
        try request.document.validate()
        let records = Dictionary(uniqueKeysWithValues: request.document.log.revisions.map { ($0.id, $0) })
        var pending = [request.pin.revision]
        var reachable = Set<Int64>()
        while let id = pending.popLast() {
            guard reachable.insert(id).inserted else { continue }
            guard let record = records[id] else { throw ProjectError.invalidRevision(id) }
            if let parent = record.parent { pending.append(parent) }
            if let target = record.stroke?.targetRevision { pending.append(target) }
        }
        let revisions = request.document.log.revisions.filter { reachable.contains($0.id) }
        let log = StrokeLogSnapshot(revisions: revisions, history: [request.pin.revision], cursor: 0)
        // The thumbnail shows the punched pose at phase zero. Current live
        // edits, easing, and wobble do not change that immutable pose.
        return ProjectDocument(source: "source.img", fusion: request.fusion == nil ? nil : "fusion.img",
                               crop: request.document.crop, globals: request.pin.globals, log: log)
    }

    private func cacheKey(document: ProjectDocument, request: FrameThumbnailRequest) throws -> NSString {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var hash = SHA256()
        hash.update(data: try encoder.encode(document))
        if previousSource?.0 != request.source {
            previousSource = (request.source, Data(SHA256.hash(data: request.source)))
        }
        hash.update(data: previousSource!.1)
        if let fusion = request.fusion {
            if previousFusion?.0 != fusion { previousFusion = (fusion, Data(SHA256.hash(data: fusion))) }
            hash.update(data: previousFusion!.1)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() as NSString
    }
}

private final class ThumbnailImage: NSObject {
    let image: CGImage
    init(_ image: CGImage) { self.image = image }
}

private final class ThumbnailCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
