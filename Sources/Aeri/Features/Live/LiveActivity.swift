import Combine
import SwiftUI

/// What the closed notch shows in "wings" on either side of the hardware notch.
enum LiveActivity: Equatable {
    case music
    case battery(level: Int, onPower: Bool, low: Bool)
    case volume(Float, muted: Bool)
    case brightness(Float)

    /// Width of each wing beside the hardware notch.
    var wing: CGFloat {
        switch self {
        case .music: return 34
        case .battery: return 54
        case .volume, .brightness: return 64
        }
    }
}

/// Picks the current live activity: a short-lived alert (battery, volume, brightness) wins over
/// the music indicator, which shows whenever something is playing.
final class LiveActivityController {
    private let state: NotchState
    private let nowPlaying: NowPlaying
    private let settings: LiveSettings
    private let space: MenuBarSpace?
    private var alert: LiveActivity?
    private var clearAlert: DispatchWorkItem?
    private var subscriptions = Set<AnyCancellable>()

    init(state: NotchState, nowPlaying: NowPlaying, settings: LiveSettings, space: MenuBarSpace?) {
        self.state = state
        self.nowPlaying = nowPlaying
        self.settings = settings
        self.space = space
        // Menus change with the frontmost app.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            self?.space?.measure { self?.update(force: true) }
        }
        // @Published fires before the value changes, so read it on the next run loop pass.
        nowPlaying.$isPlaying.sink { [weak self] _ in DispatchQueue.main.async { self?.update() } }.store(in: &subscriptions)
        settings.objectWillChange.sink { [weak self] _ in DispatchQueue.main.async { self?.update() } }.store(in: &subscriptions)
    }

    /// Shows an alert for a moment; repeated calls (e.g. holding a volume key) extend it.
    func flash(_ activity: LiveActivity, for seconds: Double) {
        alert = activity
        clearAlert?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.alert = nil
            self?.update()
        }
        clearAlert = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
        update()
    }

    private func update(force: Bool = false) {
        var next = alert ?? (settings.musicIndicator && nowPlaying.isPlaying ? .music : nil)
        // Re-measure when an activity appears (shown with the last measurement meanwhile).
        if next != nil && state.live == nil && !force { space?.measure { [weak self] in self?.update(force: true) } }
        var placement = state.livePlacement
        if let n = next, let space {
            if let p = space.placement(for: n) { placement = p } else { next = nil }   // no room: hide
        }
        guard next != state.live || placement != state.livePlacement else { return }
        // Only animate the shape when its size changes; level updates should feel instant.
        if next?.wing != state.live?.wing || (next == nil) != (state.live == nil) || placement != state.livePlacement {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                state.livePlacement = placement
                state.live = next
            }
        } else {
            state.live = next
        }
    }
}

/// Live activity preferences, saved in UserDefaults.
final class LiveSettings: ObservableObject {
    @Published var musicIndicator: Bool { didSet { save(musicIndicator, "live.music") } }
    @Published var batteryAlerts: Bool { didSet { save(batteryAlerts, "live.battery") } }
    @Published var levelBars: Bool { didSet { save(levelBars, "live.levels") } }
    /// Intercept volume/brightness keys so the system's on-screen box doesn't appear. Needs Accessibility.
    @Published var replaceSystemHUD: Bool { didSet { save(replaceSystemHUD, "live.replaceHUD") } }

    init() {
        let d = UserDefaults.standard
        musicIndicator = d.object(forKey: "live.music") as? Bool ?? true
        batteryAlerts = d.object(forKey: "live.battery") as? Bool ?? true
        levelBars = d.object(forKey: "live.levels") as? Bool ?? true
        replaceSystemHUD = d.object(forKey: "live.replaceHUD") as? Bool ?? false
    }

    private func save(_ value: Bool, _ key: String) { UserDefaults.standard.set(value, forKey: key) }
}
