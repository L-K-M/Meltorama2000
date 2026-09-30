import AppKit
import SwiftUI
import Combine
import MeltoramaCore

final class EditorSession: ObservableObject {
    weak var document: GooDocument?
    @Published var state = ProjectDocument()
    @Published var source = Data()
    @Published var fusion: Data?
    @Published var image: CGImage?
    @Published var error: String?
    @Published var tool: BrushTool = .smear
    @Published var mode: CanvasMode = .brush
    @Published var radius: Float = 0.12
    @Published var strength: Float = 0.8
    @Published var pinReach: Float = 1
    @Published var pinRubber: Float = 0
    @Published var mirrored = false
    @Published var sectors = 1
    @Published var portalsEnabled = false
    @Published var portalPoints: [CGPoint] = []
    @Published var echoAnchor: CGPoint?
    @Published var holds: [CGPoint] = []
    @Published var selectedLens: Int?
    @Published var selectedKeyframe: Int?
    @Published var live = true
    @Published var playing = false
    @Published var scrub: Double = 0
    @Published var showTimeline = false
    @Published var showInspector = true
    @Published var showExport = false
    @Published var compareOriginal = false
    @Published var zoom: CGFloat = 1
    @Published var rotation: CGFloat = 0
    @Published var pan = CGPoint.zero
    @Published var progress: Double?
    @Published var exportMessage: String?
    @Published var imageSize = CGSize(width: 1, height: 1)
    @Published var rendering = false
    var viewportSize = CGSize(width: 900, height: 700)
    private(set) var viewportBackingScale: CGFloat = 1
    private var viewportNotificationPending = false
    var recoveryURL = recoveryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("meltorama")
    private let renderQueue = DispatchQueue(label: "ch.lkmc.goo.render", qos: .userInteractive)
    private var engine: WarpEngine?
    private var renderGeneration = 0
    private var renderInFlight = false
    private var renderPending = false
    private var recoveryTimer: Timer?
    private var recoveryCeilingTimer: Timer?
    private var recoveryNeeded = false
    private var playbackTimer: Timer?
    private var pumpTimer: Timer?
    private var exportTask: Task<Void, Never>?
    private var copyTask: Task<Void, Never>?
    private var copyGeneration = 0
    private(set) var activeExportID: UUID?
    @Published private(set) var sharingCoordinator: NativeSharingCoordinator?
    private var continuousUndoGroup: (manager: UndoManager, groupsByEvent: Bool, baseLevel: Int)?
    var activeStroke: Stroke?
    private var lastPoint: CGPoint?
    private var strokeStart: CGPoint?
    private var lastSampleTime: TimeInterval = 0
    private var velocity = CGPoint.zero
    private var pumpTick = 0
    private var resampler: StrokeResampler?
    private var echoDelta: CGPoint?
    private var portalShift: CGPoint?
    private var lensDragBefore: ProjectDocument?
    private var cropStart: CGPoint?
    @Published var cropRect: CGRect?
    private var time: Double = 0
    private var lastPlaybackTick: TimeInterval?

    enum CanvasMode: String, CaseIterable { case brush = "Brush", lenses = "Lenses", crop = "Crop", hand = "Hand" }
    static let recoveryDirectory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Meltorama/Recovery", isDirectory: true)
    var hasPhoto: Bool { !source.isEmpty }
    var canExport: Bool { hasPhoto && progress == nil && activeExportID == nil }
    var canShare: Bool { canExport && sharingCoordinator == nil }
    var aspect: Float { Float(imageSize.width / max(1, imageSize.height)) }
    var currentRevision: Int64 { state.log.history.indices.contains(state.log.cursor) ? state.log.history[state.log.cursor] : 0 }
    var hint: String {
        if mode == .crop { return L("Drag a crop rectangle. Apply keeps original photo bytes and starts fresh goo.") }
        if mode == .lenses { return L("Click to place a lens. Drag its center to move. Up to four lenses.") }
        if mode == .hand { return L("Drag to pan. Pinch to zoom; rotate with two fingers.") }
        if tool == .pins { return L("Click to hold a point. Drag another point to pull. Click a hold to remove it.") }
        if tool == .echo { return L("Option-click to set the source, then drag to echo it elsewhere.") }
        if tool == .rewind { return L("Select a captured GOOvie frame, then paint it back into the live photo.") }
        if portalsEnabled && portalPoints.count < 2 { return L("Click two places to link them. Strokes in one ring appear in the other.") }
        return tool.pumped ? LF("Hold to %@. Space-drag pans; [ and ] change brush size.", L(tool.title).lowercased()) : LF("Drag to %@. Space-drag pans; [ and ] change brush size.", L(tool.title).lowercased())
    }

    func replacePackage(_ package: ProjectPackage, name: String, markEdited: Bool = true) {
        endContinuousEdit()
        discardGesture()
        cropRect = nil
        state = package.document
        source = package.sourceData
        fusion = package.fusionData
        do { imageSize = try WarpEngine.imageSize(data: source, crop: state.crop) } catch { self.error = localizedError(error).localizedDescription }
        document?.displayName = name
        document?.undoManager?.removeAllActions()
        if markEdited { document?.updateChangeCount(.changeDone); scheduleRecovery() }
        live = true
        playing = false
        selectedLens = nil
        selectedKeyframe = nil
        holds = []
        portalPoints = []
        echoAnchor = nil
        scrub = 0
        time = 0
        refreshPlaybackClock()
        requestRender()
    }
    func importSource(_ data: Data, name: String) {
        do {
            imageSize = try WarpEngine.imageSize(data: data)
            var log = try StrokeLog(snapshot: StrokeLogSnapshot())
            log.reset()
            var fresh = ProjectDocument()
            fresh.log = log.snapshot(pins: [])
            replacePackage(ProjectPackage(document: fresh, sourceData: data, fusionData: nil), name: name)
        } catch { self.error = localizedError(error).localizedDescription }
    }
    func loadSample(_ name: String) {
        guard let url = ResourceBundle.url(forResource: name, withExtension: "png") else { error = L("The bundled sample could not be found."); return }
        do { importSource(try Data(contentsOf: url), name: name == "goo-guy" ? L("Goo Guy") : L("Candy Blobs")) } catch { self.error = localizedError(error).localizedDescription }
    }
    func importFusion() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = L("Choose the photo to paint through with Fusion.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            _ = try WarpEngine.imageSize(data: data)
            let previous = fusion
            document?.undoManager?.registerUndo(withTarget: self) { target in target.setFusion(previous) }
            fusion = data
            state.fusion = "fusion.img"
            tool = .fuse; mode = .brush
            changed()
        } catch { self.error = localizedError(error).localizedDescription }
    }
    func setFusion(_ data: Data?) {
        let old = fusion
        document?.undoManager?.registerUndo(withTarget: self) { $0.setFusion(old) }
        fusion = data
        state.fusion = data == nil ? nil : "fusion.img"
        changed()
    }
    func edit(_ name: String, _ body: (inout ProjectDocument) -> Void) {
        commitStroke()
        let before = state
        body(&state)
        guard before != state else { return }
        registerUndo(before, name: name)
        live = true; playing = false
        changed()
    }
    func beginContinuousEdit() {
        guard continuousUndoGroup == nil else { return }
        finishStroke()
        guard let manager = document?.undoManager else { return }
        let automatic = manager.groupsByEvent
        manager.groupsByEvent = false
        // A pending automatic event belongs to the previous interaction.
        // Close it before opening a drag that must span several runloop turns.
        if automatic && manager.groupingLevel == 1 { manager.endUndoGrouping() }
        let baseLevel = manager.groupingLevel
        manager.beginUndoGrouping()
        continuousUndoGroup = (manager, automatic, baseLevel)
    }
    func endContinuousEdit() {
        guard let group = continuousUndoGroup else { return }
        continuousUndoGroup = nil
        if group.manager.groupingLevel > group.baseLevel { group.manager.endUndoGrouping() }
        group.manager.groupsByEvent = group.groupsByEvent
    }
    private func registerUndo(_ before: ProjectDocument, name: String) {
        document?.undoManager?.registerUndo(withTarget: self) { $0.restore(before, name: name) }
        document?.undoManager?.setActionName(L(name))
    }
    private func restore(_ snapshot: ProjectDocument, name: String) {
        let before = state
        // Keep pins captured since the edit. A pin's revision must survive an undo branch.
        var restored = snapshot
        var ids = Set(restored.log.revisions.map(\.id))
        for record in state.log.revisions where !ids.contains(record.id) { restored.log.revisions.append(record); ids.insert(record.id) }
        restored.keyframes = state.keyframes
        if ["Capture Frame", "Update Frame", "Delete Frame", "Move Frame", "Change Easing", "Crop Photo"].contains(name) {
            restored.keyframes = snapshot.keyframes
        }
        registerUndo(before, name: name)
        state = restored
        selectedLens = nil
        selectedKeyframe = nil
        live = true; playing = false
        do { imageSize = try WarpEngine.imageSize(data: source, crop: state.crop) } catch { self.error = localizedError(error).localizedDescription }
        changed()
    }
    private func changed() {
        // In-place autosaving does not automatically count mutations of our
        // value model. Undo/redo must move the same count in the opposite way.
        if let document {
            if document.undoManager?.isUndoing == true { document.updateChangeCount(.changeUndone) }
            else if document.undoManager?.isRedoing == true { document.updateChangeCount(.changeRedone) }
            else { document.updateChangeCount(.changeDone) }
        }
        scheduleRecovery()
        refreshPlaybackClock()
        requestRender()
    }
    private func scheduleRecovery() {
        markRecoveryNeeded()
        recoveryTimer?.invalidate()
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in self?.writeRecovery() }
    }
    private func markRecoveryNeeded() {
        recoveryNeeded = true
        guard recoveryCeilingTimer == nil else { return }
        recoveryCeilingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, self.recoveryNeeded else { return }
            self.writeRecovery()
        }
    }
    func writeRecovery() {
        guard hasPhoto else { return }
        do {
            var snapshot = state
            if let stroke = activeStroke, stroke.hasContent {
                var log = try StrokeLog(snapshot: snapshot.log)
                try log.push(stroke)
                snapshot.log = log.snapshot(pins: snapshot.keyframes.map(\.revision))
            }
            try FileManager.default.createDirectory(at: recoveryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try ProjectPackage(document: snapshot, sourceData: source, fusionData: fusion).write(to: recoveryURL)
            recoveryNeeded = false
            recoveryCeilingTimer?.invalidate()
            recoveryCeilingTimer = nil
        }
        catch { self.error = LF("Recovery could not be saved: %@", localizedError(error).localizedDescription) }
    }
    func removeRecovery() {
        recoveryTimer?.invalidate(); recoveryTimer = nil
        recoveryCeilingTimer?.invalidate(); recoveryCeilingTimer = nil
        recoveryNeeded = false
        try? FileManager.default.removeItem(at: recoveryURL)
    }
    func stopTimers() {
        finishStroke(); recoveryTimer?.invalidate(); recoveryCeilingTimer?.invalidate()
        playbackTimer?.invalidate(); pumpTimer?.invalidate(); lastPlaybackTick = nil
        copyGeneration += 1
        copyTask?.cancel(); copyTask = nil
    }

    func requestRender() {
        guard hasPhoto else { return }
        renderGeneration += 1
        if renderInFlight { renderPending = true; return }
        renderInFlight = true
        rendering = image == nil
        let generation = renderGeneration
        var state = self.state
        state.wobble = state.wobble.cappedFor(loopSeconds: previewLoopSeconds)
        let source = self.source, fusion = self.fusion, stroke = activeStroke
        let size = previewSize()
        let showFreeze = mode == .brush && tool == .freeze
        let compare = compareOriginal
        let tween = previewTween()
        let frameTime = time
        renderQueue.async { [weak self] in
            guard let self else { return }
            let result: Result<CGImage, Error> = Result {
                if self.engine == nil { self.engine = try WarpEngine() }
                if compare { return try WarpEngine.decodedImage(data: source, crop: state.crop, maxDimension: Int(max(size.width,size.height))) }
                return try self.engine!.render(document: state, source: source, fusion: fusion, size: size, time: frameTime, tween: tween, activeStroke: stroke, showFreeze: showFreeze)
            }
            DispatchQueue.main.async {
                self.renderInFlight = false
                self.rendering = false
                if generation == self.renderGeneration {
                    switch result { case .success(let image): self.image = image; case .failure(let error): self.error = localizedError(error).localizedDescription }
                }
                if self.renderPending { self.renderPending = false; self.requestRender() }
            }
        }
    }
    private func previewSize() -> CGSize {
        let limit: CGFloat = 1400
        let ratio = min(1, limit / max(imageSize.width,imageSize.height))
        return CGSize(width: max(1,(imageSize.width*ratio).rounded()), height: max(1,(imageSize.height*ratio).rounded()))
    }
    func previewTween() -> WarpTween? {
        guard !live, !state.keyframes.isEmpty else { return nil }
        if state.keyframes.count == 1 {
            let pin = state.keyframes[0]
            let safe = state.wobble.cappedFor(loopSeconds: previewLoopSeconds)
            return WarpTween(from: pin.revision, to: pin.revision, fraction: 0,
                             globals: leversAt(base: pin.globals, wobble: safe, phase: Float(time)))
        }
        let position = max(0,min(Double(state.keyframes.count-1),scrub))
        let segment = min(state.keyframes.count-2,Int(position))
        let a = state.keyframes[segment], b = state.keyframes[segment+1]
        let progress = Float(position-Double(segment))
        let globals = a.globals.lerp(b.globals, t: leverProgress(progress, easing: a.easing))
        let safe = state.wobble.cappedFor(loopSeconds: previewLoopSeconds)
        let phase = playing ? Float(position / Double(state.keyframes.count-1)) : Float(time)
        return WarpTween(from: a.revision, to: b.revision,
                         fraction: tweenProgress(progress, easing: a.easing),
                         globals: leversAt(base: globals, wobble: safe, phase: phase))
    }
    func resetView() { zoom = 1; pan = .zero; rotation = 0 }
    var displayedZoom: CGFloat { CanvasGeometry.displayPixelScale(image: imageSize, viewport: viewportSize, zoom: zoom, backingScale: viewportBackingScale) }
    func updateViewport(size: CGSize, backingScale: CGFloat) {
        guard viewportSize != size || viewportBackingScale != backingScale else { return }
        viewportSize = size
        viewportBackingScale = backingScale
        // AppKit can resize the canvas during a SwiftUI update. Notify the
        // status view on the next turn instead of publishing during layout.
        guard !viewportNotificationPending else { return }
        viewportNotificationPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.viewportNotificationPending = false
            self.objectWillChange.send()
        }
    }
    func actualSize() { zoom = CanvasGeometry.actualSizeZoom(image: imageSize, viewport: viewportSize, backingScale: viewportBackingScale); pan = .zero; rotation = 0 }
    func confirmReset() {
        guard hasPhoto else { return }
        let alert = NSAlert()
        alert.messageText = L("Reset the live photo?")
        alert.informativeText = L("Brush edits, effects, and lenses will return to the original. Captured GOOvie frames stay intact. You can undo this.")
        alert.addButton(withTitle: L("Reset Goo")); alert.addButton(withTitle: L("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        edit("Reset Goo") { state in
            if var log = try? StrokeLog(snapshot: state.log) { log.reset(); state.log = log.snapshot(pins: state.keyframes.map(\.revision)) }
            state.globals = GlobalParams(); state.wobble = GlobalWobble()
        }
    }
    func captureKeyframe() {
        guard hasPhoto, state.keyframes.count < 64 else { return }
        finishStroke()
        showTimeline = true
        let pin = KeyframeRecord(revision: currentRevision, globals: state.globals)
        edit("Capture Frame") { $0.keyframes.append(pin) }
        selectedKeyframe = state.keyframes.count-1
    }
    func updateKeyframe() {
        guard let i = selectedKeyframe, state.keyframes.indices.contains(i) else { return }
        finishStroke()
        let pin = KeyframeRecord(revision: currentRevision, globals: state.globals, easing: state.keyframes[i].easing)
        edit("Update Frame") { $0.keyframes[i] = pin }
    }
    func selectFrame(_ index: Int) { selectedKeyframe = index; scrub = Double(index); live = false; playing = false; requestRender() }
    func deleteFrame() {
        guard let i = selectedKeyframe, state.keyframes.indices.contains(i) else { return }
        edit("Delete Frame") { $0.keyframes.remove(at: i) }
        selectedKeyframe = nil
    }
    func moveFrame(_ delta: Int) {
        guard let i = selectedKeyframe, state.keyframes.indices.contains(i+delta) else { return }
        edit("Move Frame") { let pin = $0.keyframes.remove(at: i); $0.keyframes.insert(pin, at: i+delta) }
        selectedKeyframe = i+delta
    }
    func togglePlayback() {
        guard state.keyframes.count > 1 else { return }
        playing.toggle(); live = false
        refreshPlaybackClock()
        requestRender()
    }
    private var previewLoopSeconds: Float {
        MovieSpec(keyframeCount: max(2, state.keyframes.count)).durationSeconds
    }
    private func refreshPlaybackClock() {
        guard hasPhoto, playing || !state.wobble.isStill else {
            playbackTimer?.invalidate()
            playbackTimer = nil
            lastPlaybackTick = nil
            return
        }
        guard playbackTimer == nil else { return }
        lastPlaybackTick = Date.timeIntervalSinceReferenceDate
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.playing || !self.state.wobble.isStill else { self.refreshPlaybackClock(); return }
            let now = Date.timeIntervalSinceReferenceDate
            let elapsed = max(0, now - (self.lastPlaybackTick ?? now))
            self.lastPlaybackTick = now
            if self.playing {
                self.scrub = Double(GoovieTimeline.advance(Float(self.scrub), dtSeconds: Float(elapsed),
                                                           size: self.state.keyframes.count))
                self.time = self.scrub / Double(max(1, self.state.keyframes.count - 1))
            } else {
                self.time = (self.time + elapsed / Double(self.previewLoopSeconds)).truncatingRemainder(dividingBy: 1)
            }
            self.requestRender()
        }
    }
    @discardableResult func copyImage(to pasteboard: NSPasteboard = .general) -> Task<Void, Never>? {
        document?.commitPendingEditing()
        guard hasPhoto else { return nil }
        finishStroke()
        let snapshot = state, source = self.source, fusion = self.fusion
        copyTask?.cancel()
        copyGeneration += 1
        let generation = copyGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { if copyGeneration == generation { copyTask = nil } }
            let worker = Task.detached(priority: .userInitiated) {
                try ExportService.clipboardTIFF(document: snapshot, source: source, fusion: fusion)
            }
            do {
                let data = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: { worker.cancel() }
                try Task.checkCancellation()
                guard copyGeneration == generation else { return }
                // Rendering and encoding must succeed before replacing what
                // the user already has on their clipboard.
                pasteboard.clearContents()
                guard pasteboard.setData(data, forType: .tiff) else { throw CopyImageFailure.cannotUpdatePasteboard }
            } catch is CancellationError {
                return
            } catch {
                if copyGeneration == generation { self.error = localizedError(error).localizedDescription }
            }
        }
        copyTask = task
        return task
    }
    func export(options: ExportOptions) {
        document?.commitPendingEditing()
        guard canExport else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [options.format.contentType]
        panel.nameFieldStringValue = "\(document?.displayName ?? "Goo").\(options.format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        startOutput(options: options, to: url) { [weak self] result in
            self?.exportMessage = LF("Exported %@", result.lastPathComponent)
            NSWorkspace.shared.activateFileViewerSelecting([result])
        }
    }
    @MainActor @discardableResult
    func share(options: ExportOptions, from window: NSWindow? = nil,
               presentation: NativeSharingCoordinator.Presentation? = nil) -> Task<Void, Never>? {
        document?.commitPendingEditing()
        guard canShare else { return nil }
        guard let window = window ?? document?.windowControllers.first(where: { $0.window?.isVisible == true })?.window else {
            error = NativeSharingFailure.missingWindow.localizedDescription
            return nil
        }
        do {
            let coordinator = try NativeSharingCoordinator(format: options.format, name: document?.displayName ?? "Goo")
            sharingCoordinator = coordinator
            coordinator.onCompletion = { [weak self, weak coordinator] outcome in
                guard let self, let coordinator, self.sharingCoordinator === coordinator else { return }
                self.sharingCoordinator = nil
                switch outcome {
                case .shared: self.exportMessage = LF("Shared %@", coordinator.fileURL.lastPathComponent)
                case .cancelled: self.exportMessage = L("Share cancelled")
                case .failed(let error): self.exportMessage = nil; self.error = localizedError(error).localizedDescription
                }
            }
            let task = startOutput(options: options, to: coordinator.fileURL, cancelledMessage: L("Share cancelled"),
                onReady: { _ in try await coordinator.present(in: window, presentation: presentation) },
                onAbort: { coordinator.cancelBeforeSharing() })
            if task == nil { coordinator.cancelBeforeSharing() }
            return task
        } catch {
            self.error = localizedError(error).localizedDescription
            return nil
        }
    }
    @discardableResult
    private func startOutput(options: ExportOptions, to url: URL,
                             cancelledMessage: String = L("Export cancelled"),
                             onReady: @escaping @MainActor (URL) async throws -> Void,
                             onAbort: @escaping @MainActor () -> Void = {}) -> Task<Void, Never>? {
        finishStroke()
        let snapshot = state, source = self.source, fusion = self.fusion
        guard let exportID = beginExportTracking() else { return nil }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { finishExportTracking(exportID) }
            do {
                let result = try await ExportService.export(document: snapshot, source: source, fusion: fusion, options: options, to: url) { [weak self] value in
                    DispatchQueue.main.async { [weak self] in self?.applyExportProgress(value, exportID: exportID) }
                }
                try await onReady(result)
            } catch is CancellationError {
                onAbort()
                exportMessage = cancelledMessage
            } catch {
                onAbort()
                exportMessage = nil
                self.error = localizedError(error).localizedDescription
            }
        }
        exportTask = task
        return task
    }
    func beginExportTracking() -> UUID? {
        guard canExport else { return nil }
        let id = UUID()
        activeExportID = id
        progress = 0; showExport = false; exportMessage = nil
        return id
    }
    func applyExportProgress(_ value: Double, exportID: UUID) {
        // Completion and a later export can overtake an already queued block.
        // Only the still-active worker may change the current progress state.
        guard activeExportID == exportID, progress != nil else { return }
        progress = value
    }
    func finishExportTracking(_ exportID: UUID) {
        guard activeExportID == exportID else { return }
        activeExportID = nil
        exportTask = nil
        progress = nil
    }
    func cancelExport() { exportTask?.cancel() }

    func beginStroke(_ point: CGPoint, option: Bool = false, displayHeight: CGFloat = 700) {
        guard hasPhoto, progress == nil, !compareOriginal else { return }
        finishStroke()
        strokeStart = point; lastPoint = point; lastSampleTime = Date.timeIntervalSinceReferenceDate; velocity = .zero
        live = true; playing = false
        if mode == .crop { cropStart = point; cropRect = CGRect(origin: point, size: .zero); return }
        if mode == .lenses {
            selectedLens = state.globals.lenses.indices.min(by: { distance(point, lensPoint($0)) < distance(point, lensPoint($1)) })
            if let i = selectedLens, distance(point,lensPoint(i)) < CGFloat(state.globals.lenses[i].radius) { lensDragBefore = state; return }
            guard state.globals.lenses.count < 4 else { selectedLens = nil; return }
            edit("Place Lens") { $0.globals.lenses.append(Lens(u: Float(point.x), v: Float(point.y))) }
            selectedLens = state.globals.lenses.count-1
            lensDragBefore = state
            return
        }
        if tool == .pins { return }
        if portalsEnabled && (option || portalPoints.count < 2) {
            if portalPoints.count == 2 { portalPoints = [] }
            if portalPoints.isEmpty || Portals.separated(au: Float(portalPoints[0].x), av: Float(portalPoints[0].y),
                bu: Float(point.x), bv: Float(point.y), radius: radius, aspect: aspect) { portalPoints.append(point) }
            return
        }
        if tool == .echo {
            if option || echoAnchor == nil { echoAnchor = point; return }
            let anchor = echoAnchor!
            guard EchoOffset.isUseful(startU: Float(point.x), startV: Float(point.y),
                                      anchorU: Float(anchor.x), anchorV: Float(anchor.y)) else { echoAnchor = point; return }
            let delta = EchoOffset.delta(startU: Float(point.x), startV: Float(point.y),
                                         anchorU: Float(anchor.x), anchorV: Float(anchor.y))
            echoDelta = CGPoint(x: CGFloat(delta.0), y: CGFloat(delta.1))
        } else { echoDelta = nil }
        if tool == .fuse && fusion == nil { importFusion(); return }
        let target: Int64?
        if tool == .rewind {
            guard let i = selectedKeyframe, state.keyframes.indices.contains(i) else { showTimeline = true; error = L("Select a captured GOOvie frame to use Rewind."); return }
            target = state.keyframes[i].revision
        } else { target = nil }
        portalShift = nil
        if portalsEnabled && portalPoints.count == 2 {
            let pair = PortalPair(au: Float(portalPoints[0].x), av: Float(portalPoints[0].y),
                                  bu: Float(portalPoints[1].x), bv: Float(portalPoints[1].y))
            if let shift = Portals.shiftAt(u: Float(point.x), v: Float(point.y), radius: radius, aspect: aspect, pair: pair) {
                portalShift = CGPoint(x: CGFloat(shift.0), y: CGFloat(shift.1))
            }
        }
        activeStroke = Stroke(tool: tool, radius: radius, strength: strength*tool.strengthScale, stamps: [], targetRevision: target)
        resampler = StrokeResampler(radius: radius, aspect: aspect,
                                    firstTravel: StrokeResampler.firstTravelFor(imageHeight: Float(max(1, displayHeight))),
                                    maxSpacing: StrokeResampler.maxSpacingFor(imageHeight: Float(max(1, displayHeight))))
        resampler?.begin(u: Float(point.x), v: Float(point.y))
        pumpTick = 0
        if tool.stampsOnDown { pumpTick = 1; emitPump(point) }
        if tool.pumped {
            pumpTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in guard let self, let p = self.lastPoint else { return }; self.pumpTick += 1; self.emitPump(p) }
        }
    }
    func extendStroke(_ point: CGPoint, displayHeight: CGFloat = 700) {
        guard let previous = lastPoint else { return }
        let now = Date.timeIntervalSinceReferenceDate, dt = now-lastSampleTime
        if dt > 0 { velocity = CGPoint(x:(point.x-previous.x)/dt,y:(point.y-previous.y)/dt) }
        lastSampleTime = now; lastPoint = point
        if mode == .crop, let start = cropStart {
            let bounded = CGPoint(x: max(0, min(1, point.x)), y: max(0, min(1, point.y)))
            cropRect = CGRect(x:min(start.x,bounded.x),y:min(start.y,bounded.y),width:abs(bounded.x-start.x),height:abs(bounded.y-start.y)); return
        }
        if mode == .lenses, let i = selectedLens, state.globals.lenses.indices.contains(i), lensDragBefore != nil {
            state.globals.lenses[i].u = Float(max(0,min(1,point.x))); state.globals.lenses[i].v = Float(max(0,min(1,point.y))); markRecoveryNeeded(); requestRender(); return
        }
        if tool == .pins, let start = strokeStart, distance(start,point) >= 0.015 {
            let puck = MlsControl(su: Float(start.x), sv: Float(start.y), tu: Float(point.x), tv: Float(point.y))
            guard let warp = PinPull.warpFor(holds: holds.map { (Float($0.x), Float($0.y)) }, puck: puck,
                                            reach: pinReach, rubber: pinRubber, aspect: aspect) else { return }
            activeStroke = Stroke(tool:.pins,radius:radius,strength:strength,stamps:[],pinWarp:warp)
            markRecoveryNeeded(); requestRender(); return
        }
        guard let stroke = activeStroke, !stroke.tool.pumped else { return }
        for var stamp in resampler?.extend(u: Float(point.x), v: Float(point.y)) ?? [] {
            if let delta = echoDelta { stamp.dx = Float(delta.x); stamp.dy = Float(delta.y) }
            appendStamp(stamp)
        }
        requestRender()
    }
    private func emitPump(_ point: CGPoint) {
        guard let tool = activeStroke?.tool else { return }
        appendStamp(PumpStamps.at(tool: tool, u: Float(point.x), v: Float(point.y), tick: max(1, pumpTick)))
        requestRender()
    }
    private func appendStamp(_ stamp: Stamp) {
        guard let stroke = activeStroke else { return }
        let shift = portalShift.map { (Float($0.x), Float($0.y)) }
        // Portal translation happens before symmetry; rotating the translated
        // twin is different from translating an already rotated stamp.
        for copy in Portals.expand(stamp: stamp, shift: shift) {
            activeStroke?.stamps.append(contentsOf: Symmetry.family(tool: stroke.tool, stamp: copy,
                aspect: aspect, sectors: sectors, mirrored: mirrored))
        }
        markRecoveryNeeded()
    }
    private func discardGesture() {
        pumpTimer?.invalidate(); pumpTimer = nil
        activeStroke = nil
        lastPoint = nil
        strokeStart = nil
        lensDragBefore = nil
        cropStart = nil
        resampler = nil
        portalShift = nil
        echoDelta = nil
        velocity = .zero
        pumpTick = 0
        lastSampleTime = 0
    }
    func finishStroke(commitPendingEditing: Bool = true) {
        if commitPendingEditing { document?.commitPendingEditing() }
        endContinuousEdit()
        commitStroke()
    }
    private func commitStroke() {
        pumpTimer?.invalidate(); pumpTimer = nil
        defer { discardGesture() }
        if let before = lensDragBefore, before != state { registerUndo(before,name:"Move Lens"); changed(); return }
        if tool == .pins && activeStroke == nil, let start = strokeStart, let end = lastPoint, distance(start,end)<0.015 {
            if let index = PinPull.nearestHold(holds: holds.map { (Float($0.x), Float($0.y)) },
                                              u: Float(end.x), v: Float(end.y), aspect: aspect) { holds.remove(at:index) }
            else if holds.count < PinPull.maxHolds { holds.append(end) }
        }
        guard var stroke = activeStroke, !stroke.stamps.isEmpty || stroke.pinWarp != nil else { return }
        if stroke.tool == .whip, let p = lastPoint {
            for point in GooWhip.tail(u: Float(p.x), v: Float(p.y), velU: Float(velocity.x), velV: Float(velocity.y), aspect: aspect) {
                for stamp in resampler?.extend(u: point.0, v: point.1) ?? [] { appendStamp(stamp) }
            }
            stroke = activeStroke ?? stroke
        }
        let before = state
        do {
            var log = try StrokeLog(snapshot: state.log)
            try log.push(stroke)
            state.log = log.snapshot(pins:state.keyframes.map(\.revision))
            registerUndo(before,name:stroke.tool.title)
            activeStroke = nil
            changed()
        } catch { self.error = localizedError(error).localizedDescription }
    }
    private func lensPoint(_ index: Int) -> CGPoint { CGPoint(x:CGFloat(state.globals.lenses[index].u),y:CGFloat(state.globals.lenses[index].v)) }
    private func distance(_ a: CGPoint,_ b: CGPoint)->CGFloat { hypot((a.x-b.x)*CGFloat(aspect),a.y-b.y) }
    func applyCrop() {
        guard let rect = cropRect, rect.width > 0.02, rect.height > 0.02 else { return }
        if state.log.revisions.contains(where: { $0.stroke != nil }) || !state.keyframes.isEmpty {
            let alert = NSAlert(); alert.messageText = L("Crop and start fresh goo?"); alert.informativeText = L("Cropping changes photo coordinates, so brush edits and GOOvie frames will be cleared. Undo restores them. The original photo is preserved."); alert.addButton(withTitle:L("Crop Photo")); alert.addButton(withTitle:L("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            let selection = CropRect(left: Float(rect.minX), top: Float(rect.minY),
                                     right: Float(rect.maxX), bottom: Float(rect.maxY))
            let cropped = try Self.cropping(state, to: selection)
            edit("Crop Photo") { $0 = cropped }
            imageSize = try WarpEngine.imageSize(data:source,crop:state.crop)
        } catch {
            self.error = localizedError(error).localizedDescription
            return
        }
        selectedKeyframe = nil
        selectedLens = nil
        cropRect = nil; mode = .brush; resetView(); requestRender()
    }
    static func cropping(_ document: ProjectDocument, to selection: CropRect) throws -> ProjectDocument {
        guard selection.isValid else { throw ProjectError.invalidCrop }
        var cropped = document
        cropped.crop = (document.crop ?? .full).compose(selection)
        cropped.keyframes = []
        var log = try StrokeLog(snapshot: document.log)
        // A new document-space root gets a fresh ID. Old snapshots may still
        // be held by the native undo manager and must never alias this root.
        log.clearHistory()
        cropped.log = log.snapshot()
        cropped.globals = GlobalParams()
        cropped.wobble = GlobalWobble()
        try cropped.validate()
        return cropped
    }
    func restoreFullPhoto() {
        guard state.crop != nil else { return }
        if state.log.revisions.contains(where: { $0.stroke != nil }) || !state.keyframes.isEmpty || !state.globals.isIdentity {
            let alert = NSAlert()
            alert.messageText = L("Return to the full photo?")
            alert.informativeText = L("The crop, brush edits, effects, and GOOvie frames will be cleared. Undo restores them. The original photo is preserved.")
            alert.addButton(withTitle: L("Return to Full Photo")); alert.addButton(withTitle: L("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            var restored = try Self.cropping(state, to: .full)
            restored.crop = nil
            edit("Crop Photo") { $0 = restored }
            imageSize = try WarpEngine.imageSize(data: source)
            selectedKeyframe = nil
            cropRect = nil; mode = .brush; resetView(); requestRender()
        } catch { self.error = localizedError(error).localizedDescription }
    }
}

extension BrushTool {
    var symbol: String {
        switch self {
        case .smear,.smudge,.nudge,.move: return "hand.draw"
        case .grow: return "arrow.up.left.and.arrow.down.right"
        case .shrink: return "arrow.down.right.and.arrow.up.left"
        case .smooth: return "drop"
        case .ungoo: return "eraser"
        case .fuse: return "square.stack.3d.up"
        case .vortex,.unwind: return "hurricane"
        case .melt: return "drop.fill"
        case .comb: return "line.3.horizontal"
        case .pond: return "water.waves"
        case .fault: return "bolt"
        case .echo: return "square.on.square"
        case .whip: return "wind"
        case .freeze: return "snowflake"
        case .rewind: return "backward.end"
        case .pins: return "pin"
        }
    }
}

extension EditorSession {
    func dealGoo() {
        guard hasPhoto else {return}
        let seed=UInt64.random(in:1...UInt64.max)
        let deal=GooMe.makeDeal(seed:seed,aspect:aspect,from:state.globals)
        edit("Deal Goo") { state in
            if var log=try? StrokeLog(snapshot:state.log) {try? log.pushBatch(deal.strokes);state.log=log.snapshot(pins:state.keyframes.map(\.revision))}
            state.globals=deal.globals
        }
    }
}
