import AppKit
import SwiftUI
import XCTest
@testable import MeltoramaMac

final class WindowThemeTests: XCTestCase {
    private let suite = "MeltoramaWindowThemeTests-\(UUID().uuidString)"

    override func tearDownWithError() throws {
        UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
        try super.tearDownWithError()
    }

    @MainActor private func window() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Saved Photo"
        window.toolbar = NSToolbar(identifier: "ThemeTestToolbar")
        window.toolbarStyle = .unified
        return window
    }

    private func defaults() throws -> UserDefaults {
        try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    @MainActor func testThemeChangesPreserveNativeWindowLayoutAndContentIdentity() throws {
        let window = window()
        defer { window.close() }
        let defaults = try defaults()
        let center = NotificationCenter()
        let host = NSView(frame: window.contentView!.bounds)
        window.contentView = host
        let frame = window.frame
        let style = window.styleMask
        let toolbar = window.toolbar
        defaults.set(ThemePreference.candy.rawValue, forKey: ThemePreference.storageKey)
        let controller = WindowThemeController(window: window, defaults: defaults, notificationCenter: center)

        XCTAssertTrue(window.titlebarAppearsTransparent)
        try assertBackground(window, theme: .candy)
        defaults.set(ThemePreference.ocean.rawValue, forKey: ThemePreference.storageKey)
        center.post(name: UserDefaults.didChangeNotification, object: defaults)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        try assertBackground(window, theme: .ocean)
        XCTAssertEqual(window.title, "Saved Photo")
        XCTAssertEqual(window.frame, frame)
        XCTAssertEqual(window.styleMask, style)
        XCTAssertEqual(window.toolbarStyle, .unified)
        XCTAssertTrue(window.toolbar === toolbar)
        XCTAssertTrue(window.contentView === host)
        withExtendedLifetime(controller) {}
    }

    @MainActor func testContentStaysBelowTheNativeTitlebarWhenThemingAndResizing() throws {
        let window = window()
        defer { window.close() }
        let defaults = try defaults()
        let center = NotificationCenter()
        let host = NSHostingView(rootView: Text("Editor").frame(maxWidth: .infinity, maxHeight: .infinity))
        installWindowContentHost(host, in: window)
        defaults.set(ThemePreference.candy.rawValue, forKey: ThemePreference.storageKey)
        let controller = WindowThemeController(window: window, defaults: defaults, notificationCenter: center)

        for preference in [ThemePreference.candy, .classic, .ocean] {
            defaults.set(preference.rawValue, forKey: ThemePreference.storageKey)
            center.post(name: UserDefaults.didChangeNotification, object: defaults)
            for size in [NSSize(width: 900, height: 650), NSSize(width: 700, height: 500)] {
                window.setContentSize(size)
                window.contentView?.layoutSubtreeIfNeeded()
                let hostFrame = host.convert(host.bounds, to: nil)
                let contentFrame = window.contentLayoutRect
                XCTAssertGreaterThan(window.frame.height, contentFrame.height,
                                     "The standard titlebar and toolbar must retain their own area")
                XCTAssertEqual(hostFrame.minX, contentFrame.minX, accuracy: 0.5)
                XCTAssertEqual(hostFrame.maxX, contentFrame.maxX, accuracy: 0.5)
                XCTAssertEqual(hostFrame.minY, contentFrame.minY, accuracy: 0.5)
                XCTAssertEqual(hostFrame.maxY, contentFrame.maxY, accuracy: 0.5,
                               "Editor content must not cover the native titlebar")
            }
        }
        withExtendedLifetime(controller) {}
    }

    @MainActor func testClassicRestoresNativeTitlebarForUnknownAndClassicPreferences() throws {
        let window = window()
        defer { window.close() }
        let defaults = try defaults()
        let center = NotificationCenter()
        defaults.set(ThemePreference.grape.rawValue, forKey: ThemePreference.storageKey)
        let controller = WindowThemeController(window: window, defaults: defaults, notificationCenter: center)
        XCTAssertTrue(window.titlebarAppearsTransparent)

        for storedValue in ["unknown-future-theme", ThemePreference.classic.rawValue] {
            defaults.set(storedValue, forKey: ThemePreference.storageKey)
            center.post(name: UserDefaults.didChangeNotification, object: defaults)
            XCTAssertFalse(window.titlebarAppearsTransparent)
            for name in [NSAppearance.Name.aqua, .darkAqua] {
                let appearance = try XCTUnwrap(NSAppearance(named: name))
                XCTAssertEqual(try resolve(window.backgroundColor, in: appearance),
                               try resolve(.windowBackgroundColor, in: appearance))
            }
            XCTAssertEqual(defaults.string(forKey: ThemePreference.storageKey), storedValue)
        }
        withExtendedLifetime(controller) {}
    }

    @MainActor func testAppearanceAndClosedCachedWindowKeepTheSelectedTheme() throws {
        let window = window()
        let defaults = try defaults()
        let center = NotificationCenter()
        defaults.set(ThemePreference.mint.rawValue, forKey: ThemePreference.storageKey)
        let controller = WindowThemeController(window: window, defaults: defaults, notificationCenter: center)
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = try XCTUnwrap(NSAppearance(named: name))
            try assertBackground(window, theme: .mint)
        }
        window.close()
        defaults.set(ThemePreference.sunshine.rawValue, forKey: ThemePreference.storageKey)
        center.post(name: UserDefaults.didChangeNotification, object: defaults)
        try assertBackground(window, theme: .sunshine)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        withExtendedLifetime(controller) {}
    }

    @MainActor func testRealDefaultsWritesUpdateAnExistingWindowWithoutSyntheticNotifications() async throws {
        let window = window()
        defer { window.close() }
        let defaults = try defaults()
        defaults.set(ThemePreference.candy.rawValue, forKey: ThemePreference.storageKey)
        let controller = WindowThemeController(window: window, defaults: defaults)
        try assertBackground(window, theme: .candy)

        defaults.set(ThemePreference.ocean.rawValue, forKey: ThemePreference.storageKey)
        let expected = try resolve(MacTheme(preference: .ocean).chromeBackgroundColor,
                                   in: window.effectiveAppearance)
        // Yield the application thread so Foundation can deliver its actual
        // defaults notification. Do not manufacture a matching notification.
        for _ in 0..<100 {
            if try resolve(window.backgroundColor, in: window.effectiveAppearance) == expected { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try assertBackground(window, theme: .ocean)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        withExtendedLifetime(controller) {}
    }

    @MainActor func testThemeNotificationsPreserveTextDraftFocusAndUndo() throws {
        let window = window()
        defer { window.close() }
        let field = NSTextField(frame: NSRect(x: 20, y: 20, width: 150, height: 24))
        field.stringValue = "80"
        window.contentView?.addSubview(field)
        field.selectText(nil)
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.selectAll(nil)
        editor.insertText("45", replacementRange: editor.selectedRange())
        let undo = try XCTUnwrap(editor.undoManager)
        XCTAssertTrue(undo.canUndo)
        let defaults = try defaults()
        let center = NotificationCenter()
        let controller = WindowThemeController(window: window, defaults: defaults, notificationCenter: center)
        defaults.set(ThemePreference.cherry.rawValue, forKey: ThemePreference.storageKey)
        center.post(name: UserDefaults.didChangeNotification, object: defaults)

        XCTAssertEqual(editor.string, "45")
        XCTAssertTrue(window.firstResponder === editor)
        XCTAssertTrue(field.currentEditor() === editor)
        XCTAssertTrue(editor.undoManager === undo)
        undo.undo()
        XCTAssertEqual(editor.string, "80")
        withExtendedLifetime(controller) {}
    }

    @MainActor func testObserverLifetimeEndsWithItsOwner() throws {
        let window = window()
        defer { window.close() }
        let defaults = try defaults()
        let center = NotificationCenter()
        defaults.set(ThemePreference.candy.rawValue, forKey: ThemePreference.storageKey)
        var controller: WindowThemeController? = WindowThemeController(window: window, defaults: defaults, notificationCenter: center)
        weak var released = controller
        XCTAssertNotNil(released)
        controller = nil
        XCTAssertNil(released)

        defaults.set(ThemePreference.ocean.rawValue, forKey: ThemePreference.storageKey)
        center.post(name: UserDefaults.didChangeNotification, object: defaults)
        try assertBackground(window, theme: .candy)

        controller = WindowThemeController(window: window, defaults: defaults, notificationCenter: center)
        released = controller
        XCTAssertNotNil(released)
        try assertBackground(window, theme: .ocean)
    }

    @MainActor private func assertBackground(_ window: NSWindow, theme: ThemePreference,
                                            file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertEqual(try resolve(window.backgroundColor, in: window.effectiveAppearance),
                       try resolve(MacTheme(preference: theme).chromeBackgroundColor, in: window.effectiveAppearance),
                       file: file, line: line)
    }

    private func resolve(_ color: NSColor, in appearance: NSAppearance) throws -> NSColor {
        var resolved: NSColor?
        appearance.performAsCurrentDrawingAppearance { resolved = color.usingColorSpace(.sRGB) }
        return try XCTUnwrap(resolved)
    }
}
