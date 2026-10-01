import AppKit
import MeltoramaCore
import SwiftUI

struct WelcomeView: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        Image(nsImage: NSApplication.shared.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 76, height: 76)
                            .accessibilityHidden(true)
                        Text(L("Goo Your Photos")).font(.largeTitle.weight(.medium))
                    }
                    Text(L("Smear, stretch, fuse, and animate.\nA little photo mischief, entirely on your Mac."))
                        .font(.callout)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(L("Open a Photo…")) { (NSApp.delegate as? AppDelegate)?.openDocument(nil) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(MacTheme.berry)
                        .keyboardShortcut("o")

                    Divider().frame(width: 240, height: 1).padding(.top, 4)
                    Text(L("Or try a sample")).font(.callout).foregroundStyle(.secondary)
                    HStack(spacing: 20) {
                        sample("goo-guy", "Goo Guy")
                        sample("candy-blobs", "Candy Blobs")
                    }
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
        .background(MacTheme.welcome)
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

    private func sample(_ name: String, _ title: String) -> some View {
        Button { session.loadSample(name) } label: {
            VStack(spacing: 7) {
                if let url = ResourceBundle.url(forResource: name, withExtension: "png"),
                   let image = NSImage(contentsOf: url) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 110, height: 95)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                }
                Text(L(title)).font(.callout)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.primary)
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
