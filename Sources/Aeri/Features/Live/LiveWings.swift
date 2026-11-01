import SwiftUI

/// Content beside the hardware notch while the notch is closed.
struct LiveWings: View {
    let activity: LiveActivity
    let placement: LivePlacement
    let notchWidth: CGFloat
    let leftWing: CGFloat
    let rightWing: CGFloat
    @ObservedObject var nowPlaying: NowPlaying

    var body: some View {
        HStack(spacing: 0) {
            switch placement {
            case .split:
                left.frame(width: leftWing)
                Color.clear.frame(width: notchWidth)
                right.frame(width: rightWing)
            case .right:
                Color.clear.frame(width: notchWidth)
                HStack(spacing: 8) { left; right }.frame(width: rightWing)
            case .left:
                HStack(spacing: 8) { left; right }.frame(width: leftWing)
                Color.clear.frame(width: notchWidth)
            }
        }
        .foregroundStyle(.white)
        .transition(.opacity.animation(.easeOut(duration: 0.2)))
    }

    @ViewBuilder private var left: some View {
        switch activity {
        case .music:
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.white.opacity(0.15))
                if let art = nowPlaying.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").font(.system(size: 9))
                }
            }
            .frame(width: 18, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        case .battery(_, let onPower, let low):
            Image(systemName: onPower ? "bolt.fill" : low ? "battery.25percent" : "battery.100percent")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(onPower ? .green : low ? .red : .white)
        case .volume(let v, let muted):
            Image(systemName: Self.speaker(v, muted: muted)).font(.system(size: 11, weight: .semibold))
        case .brightness(let b):
            Image(systemName: b < 0.5 ? "sun.min.fill" : "sun.max.fill").font(.system(size: 12, weight: .semibold))
        }
    }

    @ViewBuilder private var right: some View {
        switch activity {
        case .music:
            AudioBars(playing: nowPlaying.isPlaying, color: nowPlaying.accent.map(Color.init(nsColor:)) ?? .white)
        case .battery(let level, let onPower, let low):
            Text("\(level)%")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .foregroundStyle(onPower ? .green : low ? .red : .white)
        case .volume(let v, let muted):
            LevelBar(value: muted ? 0 : v)
        case .brightness(let b):
            LevelBar(value: b)
        }
    }

    static func speaker(_ v: Float, muted: Bool) -> String {
        if muted || v == 0 { return "speaker.slash.fill" }
        return v < 0.34 ? "speaker.wave.1.fill" : v < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
    }
}

/// Slim level bar for volume and brightness.
private struct LevelBar: View {
    let value: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.2))
                Capsule().fill(.white).frame(width: geo.size.width * CGFloat(value))
            }
        }
        .frame(width: 44, height: 4)
        .animation(.easeOut(duration: 0.12), value: value)
    }
}

/// Four bars bouncing at different speeds; flat while paused.
/// Built on Core Animation layers: the window server runs the repeating animation by itself, so
/// the app does no per-frame work. (A SwiftUI repeatForever animation re-renders the view every
/// frame and cost ~5% CPU while music played.)
private struct AudioBars: NSViewRepresentable {
    let playing: Bool
    let color: Color

    private static let bars: [(low: CGFloat, high: CGFloat, speed: Double)] =
        [(0.3, 1.0, 0.42), (0.5, 0.8, 0.31), (0.25, 0.95, 0.52), (0.4, 0.7, 0.37)]
    private static let size = CGSize(width: 2.5, height: 12), gap: CGFloat = 2

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.size.height))
        view.wantsLayer = true
        for i in Self.bars.indices {
            let bar = CALayer()
            bar.frame = CGRect(x: CGFloat(i) * (Self.size.width + Self.gap), y: 0,
                               width: Self.size.width, height: Self.size.height)
            bar.cornerRadius = Self.size.width / 2
            view.layer?.addSublayer(bar)
        }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        let cg = NSColor(color).cgColor
        for (i, bar) in (view.layer?.sublayers ?? []).enumerated() {
            bar.backgroundColor = cg
            let spec = Self.bars[i]
            if playing {
                guard bar.animation(forKey: "bounce") == nil else { continue }
                let a = CABasicAnimation(keyPath: "transform.scale.y")
                a.fromValue = spec.low
                a.toValue = spec.high
                a.duration = spec.speed
                a.autoreverses = true
                a.repeatCount = .infinity
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                bar.add(a, forKey: "bounce")
            } else {
                bar.removeAnimation(forKey: "bounce")
                bar.transform = CATransform3DMakeScale(1, 0.2, 1)
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSView, context: Context) -> CGSize? {
        CGSize(width: Self.width, height: Self.size.height)
    }

    private static var width: CGFloat { CGFloat(bars.count) * size.width + CGFloat(bars.count - 1) * gap }
}
