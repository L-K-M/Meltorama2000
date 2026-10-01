import AppKit

enum NativeSharingFailure: LocalizedError {
    case missingWindow
    case unavailablePicker

    var errorDescription: String? {
        switch self {
        case .missingWindow: return L("Open a document window before sharing.")
        case .unavailablePicker: return L("The sharing picker could not be opened.")
        }
    }
}

/// A file URL remains readable until the chosen system service reports its
/// result. Closing the source window after choosing a service cannot end that
/// ownership, because service delegates and picker delegates are weak.
@MainActor final class NativeSharingCoordinator: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    enum Stage { case prepared, waiting, picking, sharing, finished }
    enum Outcome { case shared, cancelled, failed(Error) }
    typealias Presentation = (NSSharingServicePicker, NSRect, NSView) -> Void

    let directory: URL
    let fileURL: URL
    private(set) var stage: Stage = .prepared
    var onCompletion: ((Outcome) -> Void)?
    private var picker: NSSharingServicePicker?
    private var service: NSSharingService?
    private weak var sourceWindow: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private var lifetime: NativeSharingCoordinator?

    init(format: ExportFormat, name: String, temporaryRoot: URL = FileManager.default.temporaryDirectory) throws {
        directory = temporaryRoot.appendingPathComponent("Meltorama-Share-\(UUID().uuidString)", isDirectory: true)
        let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
        let filename = stem.isEmpty || stem == "." || stem == ".." ? "Meltorama" : stem
        fileURL = directory.appendingPathComponent(filename).appendingPathExtension(format.fileExtension)
        super.init()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
    }

    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        try? FileManager.default.removeItem(at: directory)
    }

    /// Presentation injection lets lifecycle tests exercise real delegates
    /// without opening a service or sending anything outside the Mac.
    func present(in window: NSWindow, presentation: Presentation? = nil) async throws {
        var presented = false
        defer { if !presented { cancelBeforeSharing() } }
        guard stage == .prepared, FileManager.default.fileExists(atPath: fileURL.path),
              window.contentView != nil else { throw NativeSharingFailure.unavailablePicker }
        sourceWindow = window
        stage = .waiting
        lifetime = self
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
            object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.cancelBeforeSharing() }
            }
        // SwiftUI dismisses the export sheet asynchronously. Anchor only after
        // it leaves, rather than presenting a picker under the departing sheet.
        while window.attachedSheet != nil {
            try Task.checkCancellation()
            guard window.isVisible, stage == .waiting else { throw CancellationError() }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try Task.checkCancellation()
        guard window.isVisible, stage == .waiting, let view = window.contentView else {
            throw CancellationError()
        }
        let picker = NSSharingServicePicker(items: [fileURL])
        self.picker = picker
        picker.delegate = self
        stage = .picking
        let anchor = Self.pickerAnchor(bounds: view.bounds, isFlipped: view.isFlipped)
        if let presentation { presentation(picker, anchor.rect, view) }
        else { picker.show(relativeTo: anchor.rect, of: view, preferredEdge: anchor.edge) }
        presented = true
    }

    static func pickerAnchor(bounds: NSRect, isFlipped: Bool) -> (rect: NSRect, edge: NSRectEdge) {
        let y = isFlipped ? min(bounds.maxY - 24, bounds.minY + 30) : max(bounds.minY, bounds.maxY - 30)
        return (NSRect(x: max(bounds.minX, bounds.maxX - 44), y: y, width: 24, height: 24),
                isFlipped ? .maxY : .minY)
    }

    func cancelBeforeSharing() {
        guard stage != .sharing, stage != .finished else { return }
        picker?.close()
        finish(.cancelled)
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker,
                              delegateFor sharingService: NSSharingService) -> NSSharingServiceDelegate? {
        guard stage != .finished else { return nil }
        service = sharingService
        stage = .sharing
        return self
    }

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        guard stage != .finished else { return }
        if let service {
            self.service = service
            stage = .sharing
        } else if stage != .sharing {
            finish(.cancelled)
        }
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        guard stage == .sharing, service === sharingService else { return }
        finish(.shared)
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        guard stage == .sharing, service === sharingService else { return }
        let native = error as NSError
        if error is CancellationError || (native.domain == NSCocoaErrorDomain && native.code == NSUserCancelledError) {
            finish(.cancelled)
        } else {
            finish(.failed(error))
        }
    }

    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        sharingContentScope.pointee = .full
        return sourceWindow
    }

    private func finish(_ outcome: Outcome) {
        guard stage != .finished else { return }
        stage = .finished
        picker?.delegate = nil
        picker = nil
        service = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        try? FileManager.default.removeItem(at: directory)
        let completion = onCompletion
        onCompletion = nil
        completion?(outcome)
        lifetime = nil
    }
}
