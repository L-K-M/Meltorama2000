import MeltoramaCore
import SwiftUI

struct GoovieTimelineView: View {
    @ObservedObject var session: EditorSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    title
                    playbackButton
                    captureButton
                    updateButton
                    Spacer(minLength: 4)
                    frameCount
                    closeButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        title
                        playbackButton
                        Spacer(minLength: 4)
                        frameCount
                        closeButton
                    }
                    HStack(spacing: 8) {
                        captureButton
                        updateButton
                        Spacer(minLength: 0)
                    }
                }
            }

            if session.state.keyframes.isEmpty {
                Text(L("Capture a frame, goo the photo, then capture another. Frames keep their own revisions through undo."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(GooPanelSurface(cornerRadius: 8, inset: true))
            } else {
                filmstrip
                frameControls
            }
        }
        .padding(12)
        .background(GooPanelSurface(cornerRadius: 0))
        .disabled(!session.hasPhoto)
    }

    private var title: some View {
        Label(L("GOOvie"), systemImage: "film")
            .font(.system(.headline, design: .rounded).weight(.semibold))
            .fixedSize()
    }

    private var frameCount: some View {
        Text("\(session.state.keyframes.count) / 64")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(GooPanelSurface(cornerRadius: 5, inset: true))
            .fixedSize()
    }

    private var playbackButton: some View {
        Button { session.togglePlayback() } label: {
            Image(systemName: session.playing ? "pause.fill" : "play.fill")
                .frame(width: 14, height: 14)
        }
        .buttonStyle(GooActionButtonStyle(tint: .aqua))
        .help(L("Play or pause the animation"))
        .accessibilityLabel(L("Play or pause the animation"))
        .disabled(session.state.keyframes.count < 2)
        .fixedSize()
    }

    private var captureButton: some View {
        Button { session.captureKeyframe() } label: {
            Label(L("Capture"), systemImage: "plus")
        }
        .buttonStyle(GooActionButtonStyle(tint: .amber))
        .help(L("Pin the live photo as a new frame (⌘K)"))
        .disabled(session.state.keyframes.count >= 64)
        .fixedSize()
    }

    private var updateButton: some View {
        Button(L("Update")) { session.updateKeyframe() }
            .buttonStyle(GooUtilityButtonStyle())
            .disabled(!session.state.keyframes.indices.contains(session.selectedKeyframe ?? -1))
            .fixedSize()
    }

    private var closeButton: some View {
        Button { session.showTimeline = false } label: {
            Image(systemName: "xmark").frame(width: 12, height: 12)
        }
        .buttonStyle(GooUtilityButtonStyle())
        .help(L("Hide GOOvie timeline"))
        .accessibilityLabel(L("Hide GOOvie timeline"))
        .fixedSize()
    }

    private var filmstrip: some View {
        VStack(spacing: 5) {
            GooFilmPerforations()
            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    ForEach(session.state.keyframes.indices, id: \.self) { index in
                        frameButton(index)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
            }
            GooFilmPerforations()
        }
        .padding(.vertical, 7)
        .background(GooWellSurface(cornerRadius: 8, dark: true))
    }

    private func frameButton(_ index: Int) -> some View {
        let selected = session.selectedKeyframe == index
        return Button { session.selectFrame(index) } label: {
            VStack(spacing: 5) {
                FrameThumbnail(session: session, index: index)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.black.opacity(0.5), lineWidth: 1))
                HStack(spacing: 5) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(selected ? GooTint.aqua.color : Color.white.opacity(0.3))
                        .accessibilityHidden(true)
                    Text(LF("Frame %d", index + 1))
                        .font(.caption2.monospacedDigit())
                        .lineLimit(1)
                }
                .foregroundStyle(.white.opacity(selected ? 1 : 0.8))
            }
            .padding(6)
            .frame(width: 94)
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(GooFrameButtonStyle(selected: selected))
        .accessibilityLabel(LF("Frame %d", index + 1))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            Button(L("Update from Live Photo")) { session.selectedKeyframe = index; session.updateKeyframe() }
            Button(L("Move Earlier")) { session.selectedKeyframe = index; session.moveFrame(-1) }.disabled(index == 0)
            Button(L("Move Later")) { session.selectedKeyframe = index; session.moveFrame(1) }
                .disabled(index == session.state.keyframes.count - 1)
            Divider()
            Button(L("Delete"), role: .destructive) { session.selectedKeyframe = index; session.deleteFrame() }
        }
    }

    private var frameControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                scrubber
                selectedFrameControls
            }
            VStack(alignment: .leading, spacing: 7) {
                scrubber
                HStack(spacing: 8) {
                    selectedFrameControls
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder private var scrubber: some View {
        if session.state.keyframes.count > 1 {
            Slider(value: Binding(get: { session.scrub }, set: {
                session.scrub = $0
                session.live = false
                session.playing = false
                session.requestRender()
            }), in: 0...Double(session.state.keyframes.count - 1))
                .accessibilityLabel(L("Animation position"))
                .frame(minWidth: 90)
        }
    }

    @ViewBuilder private var selectedFrameControls: some View {
        if let index = session.selectedKeyframe, session.state.keyframes.indices.contains(index) {
            Picker(L("Curve"), selection: EditorBindings.keyframeEasing(session: session, index: index)) {
                ForEach(Easing.allCases, id: \.rawValue) { Text(L($0.title)).tag($0) }
            }
            .frame(width: 158)
            Button { session.moveFrame(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(GooUtilityButtonStyle())
                .disabled(index == 0)
                .help(L("Move frame earlier"))
                .accessibilityLabel(L("Move frame earlier"))
            Button { session.moveFrame(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(GooUtilityButtonStyle())
                .disabled(index == session.state.keyframes.count - 1)
                .help(L("Move frame later"))
                .accessibilityLabel(L("Move frame later"))
            Button { session.deleteFrame() } label: { Image(systemName: "trash") }
                .buttonStyle(GooUtilityButtonStyle())
                .help(L("Delete selected frame"))
                .accessibilityLabel(L("Delete selected frame"))
        }
    }
}

private struct GooFrameButtonStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(GooWellSurface(cornerRadius: 6, dark: true))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .fill(configuration.isPressed ? .white.opacity(0.09) : .clear)
                .allowsHitTesting(false))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(selected ? GooTint.aqua.color : Color.white.opacity(0.14),
                              lineWidth: selected ? (contrast == .increased ? 3 : 2) : 1)
                .allowsHitTesting(false))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(focused ? Color.accentColor : .clear, lineWidth: 3)
                .padding(-2)
                .allowsHitTesting(false))
            .shadow(color: selected ? GooTint.aqua.color.opacity(0.2) : .clear, radius: 3)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .opacity(enabled ? 1 : 0.45)
    }
}

/// Decoration belongs to the film tray, never to its selectable frame controls.
private struct GooFilmPerforations: View {
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 7) {
                ForEach(0..<max(1, Int(geometry.size.width / 14)), id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white.opacity(0.13))
                        .overlay(RoundedRectangle(cornerRadius: 1.5).stroke(.black.opacity(0.65), lineWidth: 0.5))
                        .frame(width: 7, height: 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(height: 4)
        .padding(.horizontal, 7)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
