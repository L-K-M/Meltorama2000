import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MeltoramaCore

@main
enum MeltoramaApplication {
    static func main() {
        if CommandLine.arguments.contains("--smoke-test") {
            SmokeTest.run()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation, NSMenuDelegate {
    private var documentController: GooDocumentController!
    private var settingsWindow: NSWindow?
    private var settingsWindowTheme: WindowThemeController?
    private var recentMenu: NSMenu?
    var session: EditorSession? { ((NSApp.keyWindow?.windowController?.document ?? NSApp.mainWindow?.windowController?.document) as? GooDocument)?.session }

    func applicationWillFinishLaunching(_ notification: Notification) {
        documentController = GooDocumentController()
        precondition(NSDocumentController.shared === documentController)
        documentController.autosavingDelay = 5
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppearancePreference.applySaved()
        installMenus()
        recoverDrafts()
        if documentController.documents.isEmpty { newDocument(nil) }
        if CommandLine.arguments.contains("--sample") { session?.loadSample("goo-guy") }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func application(_ application: NSApplication, open urls: [URL]) { urls.forEach(openURL) }

    @objc func newDocument(_ sender: Any?) {
        do { _ = try documentController.openUntitledDocumentAndDisplay(true) }
        catch { NSApp.presentError(localizedError(error)) }
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, UTType("ch.lkmc.goo.project")!]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.message = L("Open a photo or a Meltorama project.")
        if panel.runModal() == .OK { panel.urls.forEach(openURL) }
    }

    private func openURL(_ url: URL) {
        do {
            if url.pathExtension == "meltorama" || FileManager.default.fileExists(atPath: url.appendingPathComponent("project.json").path) {
                if url.pathExtension == "meltorama" {
                    documentController.openDocument(withContentsOf: url, display: true) { _, _, error in
                        if let error { NSApp.presentError(localizedError(error)) }
                    }
                } else {
                    let package = try ProjectPackage.read(url: url)
                    newDocument(nil)
                    session?.replacePackage(package, name: L("Imported Android Project"))
                }
            } else {
                let data = try Data(contentsOf: url)
                _ = try WarpEngine.imageSize(data: data)
                newDocument(nil)
                session?.importSource(data, name: url.deletingPathExtension().lastPathComponent)
            }
        } catch { NSApp.presentError(localizedError(error)) }
    }

    @objc func openRecent(_ sender: NSMenuItem) { if let url = sender.representedObject as? URL { openURL(url) } }
    @objc func undo(_ sender: Any?) {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { editor.undoManager?.undo(); return }
        session?.finishStroke()
        session?.document?.undoManager?.undo()
    }
    @objc func redo(_ sender: Any?) {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { editor.undoManager?.redo(); return }
        session?.finishStroke()
        session?.document?.undoManager?.redo()
    }
    @objc func exportDocument(_ sender: Any?) { session?.document?.commitPendingEditing(); if session?.canExport == true { session?.showExport = true } }
    @objc func fit(_ sender: Any?) { session?.resetView() }
    @objc func actualSize(_ sender: Any?) { session?.actualSize() }
    @objc func zoomIn(_ sender: Any?) { session?.scaleZoom(by: 1.25) }
    @objc func zoomOut(_ sender: Any?) { session?.scaleZoom(by: 0.8) }
    @objc func toggleInspector(_ sender: Any?) { session?.showInspector.toggle() }
    @objc func toggleTimeline(_ sender: Any?) { session?.showTimeline.toggle() }
    @objc func capture(_ sender: Any?) { session?.captureKeyframe() }
    @objc func togglePlay(_ sender: Any?) { session?.togglePlayback() }
    @objc func resetGoo(_ sender: Any?) { session?.confirmReset() }
    @objc func importFusion(_ sender: Any?) { session?.importFusion() }
    @objc func copyImage(_ sender: Any?) { session?.copyImage() }
    @objc func fullScreen(_ sender: Any?) { NSApp.mainWindow?.toggleFullScreen(sender) }
    @objc func showHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = L("Goo Your Photos")
        alert.informativeText = L("Drag with Smear or Move. Hold Grow, Shrink, Vortex, or UnGoo to pump. Use [ and ] for brush size. Hold Space to pan; pinch to zoom and rotate with two fingers. Option-click sets an Echo source or a Portal.\n\nLenses stay editable: click to place, drag to move. Taffy Pins: click to hold a point, drag elsewhere to pull.\n\nCapture a GOOvie frame, edit the live photo, then capture another. Select a frame to preview; Update replaces its pin. File > Save keeps the editable project; Export writes a picture or movie.")
        alert.runModal()
    }
    @objc func about(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Meltorama 2000", .credits: NSAttributedString(string: L("Goo Your Photos\nAn offline native photo playground.\n\nPublic domain under the Unlicense.\nSample artwork and warp shaders belong to this project.\nNo third-party runtime dependencies.\nEditing happens on your Mac."))])
    }
    @MainActor @objc func settings(_ sender: Any?) {
        if settingsWindow == nil {
            let hostingView = NSHostingView(rootView: SettingsView())
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: hostingView.fittingSize), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = L("Settings")
            window.contentView = hostingView
            window.center()
            settingsWindow = window
            settingsWindowTheme = WindowThemeController(window: window)
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func recoverDrafts() {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: EditorSession.recoveryDirectory, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.pathExtension == "meltorama" {
            do {
                let package = try ProjectPackage.read(url: url)
                newDocument(nil)
                session?.recoveryURL = url
                session?.replacePackage(package, name: L("Recovered Photo"))
            } catch { NSApp.presentError(localizedError(error)) }
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo):
            let manager = currentUndoManager
            menuItem.title = manager?.undoMenuItemTitle ?? L("Undo")
            return manager?.canUndo ?? false
        case #selector(redo):
            let manager = currentUndoManager
            menuItem.title = manager?.redoMenuItemTitle ?? L("Redo")
            return manager?.canRedo ?? false
        case #selector(togglePlay): return (session?.state.keyframes.count ?? 0) > 1
        case #selector(fullScreen):
            menuItem.title = L(NSApp.mainWindow?.styleMask.contains(.fullScreen) == true ? "Exit Full Screen" : "Enter Full Screen")
            return NSApp.mainWindow?.windowController is EditorWindowController
        case #selector(exportDocument): return session?.canExport ?? false
        case #selector(importFusion), #selector(copyImage), #selector(resetGoo), #selector(capture), #selector(fit), #selector(actualSize), #selector(zoomIn), #selector(zoomOut): return session?.hasPhoto ?? false
        default: return true
        }
    }

    private var currentUndoManager: UndoManager? {
        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView { return editor.undoManager }
        return session?.document?.undoManager
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            item.representedObject = url
            item.target = self
            menu.addItem(item)
        }
    }

    private func installMenus() {
        let main = NSMenu()
        @discardableResult func menu(_ title: String, items: [(String, Selector?, String, NSEvent.ModifierFlags)]) -> NSMenu {
            let item = NSMenuItem(title: L(title), action: nil, keyEquivalent: "")
            let submenu = NSMenu(title: L(title))
            main.addItem(item)
            item.submenu = submenu
            for (name, action, key, flags) in items {
                if name == "-" { submenu.addItem(.separator()); continue }
                let child = NSMenuItem(title: L(name), action: action, keyEquivalent: key)
                child.keyEquivalentModifierMask = flags
                if ![#selector(NSText.cut(_:)), #selector(NSText.copy(_:)), #selector(NSText.paste(_:)), #selector(NSText.selectAll(_:))].contains(action) && action != #selector(NSDocument.save(_:)) && action != #selector(NSDocument.revertToSaved(_:)) && action != #selector(NSWindow.performClose(_:)) && action != #selector(NSWindow.performMiniaturize(_:)) && action != #selector(NSWindow.performZoom(_:)) { child.target = self }
                submenu.addItem(child)
            }
            return submenu
        }
        let appMenu = menu("Meltorama", items: [
            ("About Meltorama 2000", #selector(about), "", []), ("Settings…", #selector(settings), ",", .command),
            ("-", nil, "", []), ("Hide Meltorama", #selector(NSApplication.hide(_:)), "h", .command),
            ("-", nil, "", []), ("Quit Meltorama", #selector(NSApplication.terminate(_:)), "q", .command)])
        appMenu.items.last?.target = NSApp
        appMenu.items.first(where: { $0.title == L("Hide Meltorama") })?.target = NSApp
        let file = menu("File", items: [
            ("New", #selector(newDocument), "n", .command), ("Open…", #selector(openDocument), "o", .command),
            ("-", nil, "", []), ("Close", #selector(NSWindow.performClose(_:)), "w", .command),
            ("Save…", #selector(NSDocument.save(_:)), "s", .command),
            ("Save As…", #selector(NSDocument.saveAs(_:)), "s", [.command, .option, .shift]),
            ("Revert to Saved…", #selector(NSDocument.revertToSaved(_:)), "", []),
            ("-", nil, "", []), ("Add Fusion Photo…", #selector(importFusion), "o", [.command, .shift]),
            ("Export…", #selector(exportDocument), "e", [.command, .shift])])
        file.items.first(where: { $0.title == L("Save As…") })?.target = nil
        let recent = NSMenuItem(title: L("Open Recent"), action: nil, keyEquivalent: "")
        let recentMenu = NSMenu(title: L("Open Recent"))
        self.recentMenu = recentMenu
        recentMenu.delegate = self
        menuNeedsUpdate(recentMenu)
        recent.submenu = recentMenu
        file.insertItem(recent, at: 2)
        menu("Edit", items: [("Undo", #selector(undo), "z", .command), ("Redo", #selector(redo), "z", [.command,.shift]),
            ("-", nil, "", []), ("Cut", #selector(NSText.cut(_:)), "x", .command), ("Copy", #selector(NSText.copy(_:)), "c", .command), ("Paste", #selector(NSText.paste(_:)), "v", .command), ("Select All", #selector(NSText.selectAll(_:)), "a", .command), ("-", nil, "", []), ("Copy Image", #selector(copyImage), "c", [.command,.shift]),
            ("Reset Goo…", #selector(resetGoo), "", [])])
        menu("View", items: [("Zoom In", #selector(zoomIn), "+", .command), ("Zoom Out", #selector(zoomOut), "-", .command),
            ("Fit in Window", #selector(fit), "0", .command), ("Actual Size", #selector(actualSize), "1", .command),
            ("-", nil, "", []), ("Show/Hide Inspector", #selector(toggleInspector), "i", [.command,.option]),
            ("Show/Hide GOOvie Timeline", #selector(toggleTimeline), "t", [.command,.option])])
        menu("Animation", items: [("Capture Frame", #selector(capture), "k", .command), ("Play/Pause", #selector(togglePlay), "p", [.command,.option])])
        let windowMenu = menu("Window", items: [("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m", .command), ("Zoom", #selector(NSWindow.performZoom(_:)), "", []), ("Enter Full Screen", #selector(fullScreen), "f", [.command, .control])])
        NSApp.windowsMenu = windowMenu
        let help = menu("Help", items: [("Meltorama Help", #selector(showHelp), "?", .command)])
        NSApp.helpMenu = help
        NSApp.mainMenu = main
    }
}

final class GooDocumentController: NSDocumentController {
    override var defaultType: String? { "ch.lkmc.goo.project" }
    override func documentClass(forType typeName: String) -> AnyClass? { GooDocument.self }
}

@objc(GooDocument)
final class GooDocument: NSDocument {
    let session = EditorSession()
    override init() { super.init(); session.document = self; hasUndoManager = true; undoManager = UndoManager() }
    override class var autosavesInPlace: Bool { true }
    override class var autosavesDrafts: Bool { true }
    override func willPresentError(_ error: Error) -> Error { localizedError(error) }
    func commitPendingEditing() {
        for controller in windowControllers {
            if let window = controller.window { commitPendingNumericEditing(in: window) }
        }
    }
    func discardPendingEditing() {
        for controller in windowControllers {
            if let window = controller.window { discardPendingNumericEditing(in: window) }
        }
    }
    override func save(_ sender: Any?) { commitPendingEditing(); super.save(sender) }
    override func saveAs(_ sender: Any?) { commitPendingEditing(); super.saveAs(sender) }
    override func makeWindowControllers() {
        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 1240, height: 820), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.session = session
        window.title = displayName
        window.minSize = NSSize(width: 870, height: 580)
        window.tabbingMode = .preferred
        window.setFrameAutosaveName("MeltoramaEditor")
        installWindowContentHost(NSHostingView(rootView: EditorView(session: session)), in: window)
        let controller = EditorWindowController(window: window, session: session)
        addWindowController(controller)
        window.center()
    }
    override func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        let package = try ProjectPackage(fileWrapper: fileWrapper)
        _ = try WarpEngine.imageSize(data: package.sourceData, crop: package.document.crop)
        // Complete the same bounded ImageIO decode used by preview before
        // discarding live drafts, gestures, undo, or recovery on a read/revert.
        _ = try WarpEngine.decodedImage(data: package.sourceData, crop: package.document.crop, maxDimension: 1400)
        if let fusion = package.fusionData { _ = try WarpEngine.decodedImage(data: fusion, maxDimension: 1400) }
        discardPendingEditing()
        session.replacePackage(package, name: displayName, markEdited: false)
        session.removeRecovery()
    }

    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        session.finishStroke(commitPendingEditing: false)
        guard !session.source.isEmpty else { throw NSError(domain: "Meltorama", code: 1, userInfo: [NSLocalizedDescriptionKey: L("Open a photo before saving a project.")]) }
        var state = session.state
        state.updatedAtMillis = Int64(Date().timeIntervalSince1970 * 1000)
        state.source = "source.img"
        state.fusion = session.fusion == nil ? nil : "fusion.img"
        try state.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var files = ["project.json": FileWrapper(regularFileWithContents: try encoder.encode(state)), "source.img": FileWrapper(regularFileWithContents: session.source)]
        if let fusion = session.fusion { files["fusion.img"] = FileWrapper(regularFileWithContents: fusion) }
        return FileWrapper(directoryWithFileWrappers: files)
    }
    override func write(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, originalContentsURL absoluteOriginalContentsURL: URL?) throws {
        if saveOperation == .saveOperation || saveOperation == .saveAsOperation { commitPendingEditing() }
        try super.write(to: url, ofType: typeName, for: saveOperation, originalContentsURL: absoluteOriginalContentsURL)
        if saveOperation == .saveOperation || saveOperation == .saveAsOperation || saveOperation == .autosaveInPlaceOperation { session.removeRecovery() }
    }
    override func canClose(withDelegate delegate: Any, shouldClose shouldCloseSelector: Selector?, contextInfo: UnsafeMutableRawPointer?) {
        // Pending gestures are not in the document log yet. Commit before
        // AppKit decides whether closing needs an autosave or a save prompt.
        commitPendingEditing()
        session.finishStroke()
        super.canClose(withDelegate: delegate, shouldClose: shouldCloseSelector, contextInfo: contextInfo)
    }
    override func close() {
        session.stopTimers()
        session.removeRecovery()
        super.close()
    }
}

final class EditorWindow: NSWindow {
    weak var session: EditorSession?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard event.charactersIgnoringModifiers?.lowercased() == "z",
              modifiers == .command || modifiers == [.command, .shift],
              !(firstResponder is NSTextView), let session else {
            return super.performKeyEquivalent(with: event)
        }
        // SwiftUI can consume standard undo keys without finding the native
        // document manager. Route canvas commands before entering that tree;
        // field editors retain AppKit's text undo through the branch above.
        session.finishStroke()
        if modifiers.contains(.shift) { session.document?.undoManager?.redo() }
        else { session.document?.undoManager?.undo() }
        return true
    }
}

final class EditorWindowController: NSWindowController, NSToolbarDelegate, NSUserInterfaceValidations {
    let session: EditorSession
    private var windowTheme: WindowThemeController?
    init(window: NSWindow, session: EditorSession) {
        self.session = session
        super.init(window: window)
        let toolbar = NSToolbar(identifier: "EditorToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = true
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        windowTheme = WindowThemeController(window: window)
    }
    required init?(coder: NSCoder) { fatalError("Not supported") }
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo): return session.document?.undoManager?.canUndo ?? false
        case #selector(redo): return session.document?.undoManager?.canRedo ?? false
        case #selector(exportPhoto): return session.canExport
        case #selector(fit), #selector(compare): return session.hasPhoto
        default: return true
        }
    }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { ["undo", "redo", "NSToolbarFlexibleSpaceItem", "fit", "compare", "timeline", "inspector", "export"].map { NSToolbarItem.Identifier($0) } }
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { toolbarDefaultItemIdentifiers(toolbar) }
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let configurations: [String:(String,String,Selector)] = ["undo":("Undo","arrow.uturn.backward",#selector(undo)), "redo":("Redo","arrow.uturn.forward",#selector(redo)), "fit":("Fit","arrow.up.left.and.arrow.down.right",#selector(fit)), "compare":("Original","square.on.square",#selector(compare)), "timeline":("GOOvie","film",#selector(timeline)), "inspector":("Inspector","sidebar.right",#selector(inspector)), "export":("Export","square.and.arrow.up",#selector(exportPhoto))]
        guard let (title,symbol,action) = configurations[id.rawValue] else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = L(title)
        item.paletteLabel = L(title)
        item.toolTip = title == "Original" ? L("Toggle original photo for comparison") : L(title)
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: L(title))
        item.target = self
        item.action = action
        return item
    }
    @objc func undo() { session.finishStroke(); session.document?.undoManager?.undo() }
    @objc func redo() { session.finishStroke(); session.document?.undoManager?.redo() }
    @objc func fit() { session.resetView() }
    @objc func compare() { session.compareOriginal.toggle(); session.requestRender() }
    @objc func timeline() { session.showTimeline.toggle() }
    @objc func inspector() { session.showInspector.toggle() }
    @objc func exportPhoto() { session.document?.commitPendingEditing(); if session.canExport { session.showExport = true } }
}
