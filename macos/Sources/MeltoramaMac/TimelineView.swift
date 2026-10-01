import MeltoramaCore
import SwiftUI

struct GoovieTimelineView: View {
    @ObservedObject var session: EditorSession
    @Environment(\.colorSchemeContrast) private var contrast

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
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                filmstrip
                frameControls
            }
        }
        .padding(12)
        .background(MacTheme.window)
        .disabled(!session.hasPhoto)
    }

    private var title: some View {
        Label(L("GOOvie"), systemImage: "film")
            .font(.headline)
            .fixedSize()
    }

    private var frameCount: some View {
        Text("\(session.state.keyframes.count) / 64")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    private var playbackButton: some View {
        Button { session.togglePlayback() } label: {
            Image(systemName: session.playing ? "pause.fill" : "play.fill")
                .frame(width: 14, height: 14)
        }
        .help(L("Play or pause the animation"))
        .accessibilityLabel(L("Play or pause the animation"))
        .disabled(session.state.keyframes.count < 2)
        .fixedSize()
    }

    private var captureButton: some View {
        Button { session.captureKeyframe() } label: {
            Label(L("Capture"), systemImage: "plus")
        }
        .help(L("Pin the live photo as a new frame (⌘K)"))
        .disabled(session.state.keyframes.count >= 64)
        .fixedSize()
    }

    private var updateButton: some View {
        Button(L("Update")) { session.updateKeyframe() }
            .disabled(!session.state.keyframes.indices.contains(session.selectedKeyframe ?? -1))
            .fixedSize()
    }

    private var closeButton: some View {
        Button { session.showTimeline = false } label: {
            Image(systemName: "xmark").frame(width: 24, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(L("Hide GOOvie timeline"))
        .accessibilityLabel(L("Hide GOOvie timeline"))
        .fixedSize()
    }

    private var filmstrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(session.state.keyframes.indices, id: \.self) { index in
                    frameButton(index)
                }
            }.padding(3)
        }
    }

    private func frameButton(_ index: Int) -> some View {
        let selected = session.selectedKeyframe == index
        return Button { session.selectFrame(index) } label: {
            VStack(spacing: 5) {
                FrameThumbnail(session: session, index: index)
                HStack(spacing: 4) {
                    Image(systemName: "checkmark").font(.caption2.weight(.semibold))
                        .opacity(selected ? 1 : 0).accessibilityHidden(true)
                    Text(LF("Frame %d", index + 1)).font(.caption).lineLimit(1)
                }
            }.frame(width: 88, height: 78).padding(4)
                .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.bordered)
        .foregroundStyle(.primary)
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? MacTheme.accent : .clear, lineWidth: contrast == .increased ? 3 : 2)
            .allowsHitTesting(false).accessibilityHidden(true))
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
                .disabled(index == 0)
                .help(L("Move frame earlier"))
                .accessibilityLabel(L("Move frame earlier"))
            Button { session.moveFrame(1) } label: { Image(systemName: "chevron.right") }
                .disabled(index == session.state.keyframes.count - 1)
                .help(L("Move frame later"))
                .accessibilityLabel(L("Move frame later"))
            Button { session.deleteFrame() } label: { Image(systemName: "trash") }
                .help(L("Delete selected frame"))
                .accessibilityLabel(L("Delete selected frame"))
        }
    }
}
