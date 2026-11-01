import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var panel: NotchPanel!
    var tracker: MouseTracker!
    let state = NotchState()
    let nowPlaying = NowPlaying()
    let shelf = Shelf()
    let clipboard = ClipboardHistory()
    let weather = Weather()
    let liveSettings = LiveSettings()
    var live: LiveActivityController!
    var battery: BatteryMonitor!
    var audio: SystemAudio!
    var mediaKeys: MediaKeys!
    private var liveSubscription: Any?

    func applicationDidFinishLaunching(_ note: Notification) {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }

        // Real notch size on notched Macs; fallback pill elsewhere.
        var notch = CGSize(width: 200, height: 32)
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notch = CGSize(width: screen.frame.width - left.width - right.width,
                           height: screen.safeAreaInsets.top)
        }

        let size = CGSize(width: 500, height: 200)   // max expanded area
        let f = screen.frame
        let rect = NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                          width: size.width, height: size.height)

        panel = NotchPanel(rect: rect)
        panel.contentView = NSHostingView(rootView: NotchView(state: state, nowPlaying: nowPlaying, shelf: shelf, clipboard: clipboard, weather: weather, notchSize: notch))
        panel.orderFrontRegardless()
        tracker = MouseTracker(panel: panel, state: state, notchSize: notch)
        startLiveActivities(space: MenuBarSpace(screen: screen, notchWidth: notch.width))
        SettingsWindow.shared = SettingsWindow(state: state, weather: weather, liveSettings: liveSettings, mediaKeys: mediaKeys)
    }

    private func startLiveActivities(space: MenuBarSpace) {
        live = LiveActivityController(state: state, nowPlaying: nowPlaying, settings: liveSettings, space: space)
        battery = BatteryMonitor { [weak self] event in
            guard let self, self.liveSettings.batteryAlerts else { return }
            if case .battery(_, _, let low) = event { self.live.flash(event, for: low ? 4 : 2.5) }
        }
        audio = SystemAudio()
        audio.onChange = { [weak self] volume, muted in
            guard let self, self.liveSettings.levelBars else { return }
            self.live.flash(.volume(volume, muted: muted), for: 1.5)
        }
        audio.onActivityChange = { [weak self] running in self?.nowPlaying.audioActivityChanged(running) }
        mediaKeys = MediaKeys(audio: audio) { [weak self] brightness in
            guard let self, self.liveSettings.levelBars else { return }
            self.live.flash(.brightness(brightness), for: 1.5)
        }
        mediaKeys.setReplacing(liveSettings.replaceSystemHUD && liveSettings.levelBars)
        liveSubscription = liveSettings.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.mediaKeys.setReplacing(self.liveSettings.replaceSystemHUD && self.liveSettings.levelBars)
            }
        }
    }
}
