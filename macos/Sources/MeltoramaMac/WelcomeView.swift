import AppKit
import MeltoramaCore
import SwiftUI

struct WelcomeView: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 88, height: 88)
                            .shadow(color: .black.opacity(0.22), radius: 7, y: 5)
                            .accessibilityHidden(true)
                        GooWordmark()
                        Text(L("Goo Your Photos"))
                            .font(.system(.title3, design: .rounded).weight(.medium))
                    }
                    Text(L("Smear, stretch, fuse, and animate.\nA little photo mischief, entirely on your Mac."))
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button { (NSApp.delegate as? AppDelegate)?.openDocument(nil) } label: {
                        Label(L("Open a Photo…"), systemImage: "photo.badge.plus")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(GooActionButtonStyle(tint: .berry))
                    .keyboardShortcut("o")

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Divider()
                            Text(L("Or try a sample")).font(.caption).foregroundStyle(.secondary).fixedSize()
                            Divider()
                        }
                        HStack(spacing: 14) {
                            sample("goo-guy", "Goo Guy", tint: .aqua)
                            sample("candy-blobs", "Candy Blobs", tint: .berry)
                        }
                    }
                    .frame(maxWidth: 286)

                    Text(L("Drop a photo or project into this window."))
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 30)
                .frame(maxWidth: 450)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .background(GooPanelSurface(cornerRadius: 0, inset: true))
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let item = providers.first else { return false }
            item.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    DispatchQueue.main.async { openDrop(url) }
                }
            }
            return true
        }
    }

    private func sample(_ name: String, _ title: String, tint: GooTint) -> some View {
        Button { session.loadSample(name) } label: {
            VStack(spacing: 9) {
                if let url = ResourceBundle.url(forResource: name, withExtension: "png"),
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 110, height: 86)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.black.opacity(0.4), lineWidth: 1))
                        .accessibilityHidden(true)
                }
                HStack(spacing: 5) {
                    Circle().fill(tint.color).frame(width: 4, height: 4).accessibilityHidden(true)
                    Text(L(title)).font(.callout.weight(.medium)).lineLimit(1)
                }
            }
            .padding(9)
            .frame(width: 130)
            .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(GooSampleButtonStyle(tint: tint))
        .accessibilityLabel(LF("Open %@ sample", L(title)))
    }

    private func openDrop(_ url: URL) {
        do {
            if url.pathExtension == "meltorama" {
                session.replacePackage(try ProjectPackage.read(url: url), name: url.deletingPathExtension().lastPathComponent)
            } else {
                session.importSource(try Data(contentsOf: url), name: url.deletingPathExtension().lastPathComponent)
            }
        } catch {
            session.error = localizedError(error).localizedDescription
        }
    }
}

private struct GooSampleButtonStyle: ButtonStyle {
    let tint: GooTint
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .background(GooPanelSurface(cornerRadius: 9, inset: configuration.isPressed))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(tint.color.opacity(contrast == .increased ? 0.8 : 0.32), lineWidth: 1)
                .allowsHitTesting(false))
            .overlay(RoundedRectangle(cornerRadius: 11)
                .strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 3)
                .padding(-2)
                .allowsHitTesting(false))
            .shadow(color: .black.opacity(0.16), radius: configuration.isPressed ? 1 : 4,
                    y: configuration.isPressed ? 1 : 3)
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .opacity(enabled ? 1 : 0.45)
    }
}
