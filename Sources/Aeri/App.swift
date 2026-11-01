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
        SettingsWindow.shared = SettingsWindow(state: state, weather: weather)
    }
}
