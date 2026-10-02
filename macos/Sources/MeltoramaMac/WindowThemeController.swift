import AppKit

/// Installs a retained host below the native titlebar and toolbar once per window.
@MainActor
func installWindowContentHost(_ host: NSView, in window: NSWindow) {
    let container = NSView(frame: window.contentView?.frame ?? .zero)
    window.contentView = container
    host.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(host)
    guard let guide = window.contentLayoutGuide else {
        preconditionFailure("A titled editor window requires its native content layout guide")
    }
    // Full-size content extends behind native chrome. Its documented layout
    // guide keeps the editor below that chrome even when the titlebar becomes
    // transparent, and follows toolbar, tab-bar, and window-size changes.
    NSLayoutConstraint.activate([.leading, .trailing, .top, .bottom].map { attribute in
        NSLayoutConstraint(item: host, attribute: attribute, relatedBy: .equal,
                           toItem: guide, attribute: attribute, multiplier: 1, constant: 0)
    })
}

/// Owns native chrome updates without replacing the content host or touching editing.
@MainActor
final class WindowThemeController {
    private weak var window: NSWindow?
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private var preferenceObserver: NSObjectProtocol?
    private var appearanceObserver: NSKeyValueObservation?
    private var appliedPreference: ThemePreference?

    init(window: NSWindow, defaults: UserDefaults = .standard,
         notificationCenter: NotificationCenter = .default) {
        self.window = window
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        // Automatic chrome omits this boundary with a transparent titlebar.
        // Let AppKit draw its appearance-aware line across the entire window.
        window.titlebarSeparatorStyle = .line

        preferenceObserver = notificationCenter.addObserver(
            forName: UserDefaults.didChangeNotification, object: defaults, queue: .main
        ) { [weak self] _ in
            // NotificationCenter delivers this observer on the main queue even
            // when a preferences write originated off the application thread.
            MainActor.assumeIsolated { self?.applySavedTheme() }
        }
        appearanceObserver = window.observe(\.effectiveAppearance) { [weak self] _, _ in
            // AppKit changes a window's appearance on its application thread.
            MainActor.assumeIsolated { self?.refreshBackground() }
        }
        applySavedTheme()
    }

    deinit {
        if let preferenceObserver { notificationCenter.removeObserver(preferenceObserver) }
        appearanceObserver?.invalidate()
    }

    private func applySavedTheme() {
        guard let window else { return }
        let preference = ThemePreference.resolve(defaults.string(forKey: ThemePreference.storageKey))
        guard preference != appliedPreference else { return }
        appliedPreference = preference
        // A transparent titlebar exposes the window's background behind the
        // existing native title and toolbar. Keep their layout and safe area.
        window.titlebarAppearsTransparent = preference != .classic
        refreshBackground()
    }

    private func refreshBackground() {
        guard let window, let appliedPreference else { return }
        window.backgroundColor = MacTheme(preference: appliedPreference).chromeBackgroundColor
        window.contentView?.needsDisplay = true
    }
}
