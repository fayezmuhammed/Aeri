import SwiftUI

struct NowPlayingView: View {
    @ObservedObject var model: NowPlaying

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ArtworkView(image: model.artwork)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.hasTrack ? model.title : "Nothing playing")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if model.hasTrack {
                        Text(model.artist).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                }
                Spacer()
                if model.hasTrack {
                    HStack(spacing: 14) {
                        Button(action: model.previous) { Image(systemName: model.canSkipTracks ? "backward.fill" : "gobackward.10") }
                        Button(action: model.playPause) { Image(systemName: model.isPlaying ? "pause.fill" : "play.fill") }
                            .font(.title3)
                        Button(action: model.next) { Image(systemName: model.canSkipTracks ? "forward.fill" : "goforward.10") }
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            if model.hasTrack, model.duration > 0 {
                ProgressRow(model: model)
            } else if !model.hasTrack, let b = model.browserNeedingSetup {
                Text("To show browser media, enable \(b.setupHint)")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct ArtworkView: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.12))
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note").font(.title3).foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: image != nil)
    }
}

/// Thin progress bar with elapsed / remaining time, extrapolated once a second while playing.
private struct ProgressRow: View {
    @ObservedObject var model: NowPlaying

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = model.elapsed(at: context.date)
            HStack(spacing: 8) {
                Text(Self.format(elapsed))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.15))
                        Capsule().fill(.white.opacity(0.85))
                            .frame(width: geo.size.width * CGFloat(elapsed / model.duration))
                    }
                }
                .frame(height: 3)
                Text("-" + Self.format(model.duration - elapsed))
            }
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(.white.opacity(0.6))
        }
    }

    static func format(_ t: Double) -> String {
        let s = Int(max(t, 0).rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Shrinks slightly while pressed and brightens on hover.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration)
    }

    private struct PressableLabel: View {
        let configuration: ButtonStyleConfiguration
        @StateObject private var hover = HoverFlag()

        var body: some View {
            configuration.label
                .opacity(hover.on || configuration.isPressed ? 1 : 0.8)
                .scaleEffect(configuration.isPressed ? 0.85 : 1)
                .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
                .contentShape(Rectangle())
                .onHover { hover.on = $0 }
        }
    }
}

/// Stands in for @State, which needs macros.
final class HoverFlag: ObservableObject {
    @Published var on = false
}
