import AppKit

/// Track info, artwork, progress and transport controls via AppleScript:
/// Music and Spotify directly, browsers through JavaScript in their tabs (see BrowserMedia).
/// (MediaRemote is private and blocked for third-party apps on recent macOS.)
/// Updates on Music/Spotify notifications, when the notch expands, and every few seconds while
/// expanded (browsers send no notifications).
final class NowPlaying: ObservableObject {
    enum Player: String {
        case music = "Music", spotify = "Spotify"
        var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
        var notification: String { self == .music ? "com.apple.Music.playerInfo" : "com.spotify.client.PlaybackStateChanged" }
    }

    enum Source {
        case app(Player)
        case browser(Browser, window: Int, tab: Int, canSkip: Bool)

        var name: String {
            switch self {
            case .app(let p): return p.rawValue
            case .browser(let b, _, _, _): return b.rawValue
            }
        }
    }

    struct Track {
        var source: Source
        var title: String
        var artist: String
        var isPlaying: Bool
        var position: Double   // seconds
        var duration: Double   // seconds
        var artworkURL: URL?   // browsers only
        var canSeek = true
    }

    @Published private(set) var source: Source?
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    /// Vivid color from the artwork, for the glow and progress bar.
    @Published private(set) var accent: NSColor?
    @Published private(set) var canSeek = false
    @Published private(set) var duration: Double = 0
    /// Position at `positionDate`; views extrapolate while playing.
    @Published private(set) var position: Double = 0
    private(set) var positionDate = Date()
    /// A running browser that refused JavaScript from Apple Events, shown as a hint when nothing plays.
    @Published private(set) var browserNeedingSetup: Browser?

    var hasTrack: Bool { source != nil }
    /// Browser tabs without their own next/previous buttons seek ±10s instead.
    var canSkipTracks: Bool {
        switch source {
        case .app: return true
        case .browser(_, _, _, let canSkip): return canSkip
        case nil: return false
        }
    }

    private let queue = DispatchQueue(label: "NowPlaying")   // AppleScript is slow; keep it off main
    private var artworkKey = ""
    private var refreshing = false
    private var pollTimer: Timer?
    private var active = false

    init() {
        let center = DistributedNotificationCenter.default()
        for p in [Player.music, .spotify] {
            center.addObserver(forName: .init(p.notification), object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        }
        refresh()
    }

    /// Polls while the notch is open.
    func setActive(_ active: Bool) {
        self.active = active
        if active { refresh() }
        reschedule()
    }

    /// Every 3s while open. While closed, only a playing browser is polled (every 8s) so the live
    /// indicator notices when it stops; Music/Spotify send notifications instead.
    private func reschedule() {
        let interval: TimeInterval? = active ? 3 : (isBrowser && isPlaying ? 8 : nil)
        guard interval != pollTimer?.timeInterval || (interval == nil) != (pollTimer == nil) else { return }
        pollTimer?.invalidate()
        pollTimer = interval.map { .scheduledTimer(withTimeInterval: $0, repeats: true) { [weak self] _ in self?.refresh() } }
    }

    private var isBrowser: Bool { if case .browser = source { return true } else { return false } }

    func elapsed(at date: Date) -> Double {
        let t = position + (isPlaying ? date.timeIntervalSince(positionDate) : 0)
        return duration > 0 ? min(max(t, 0), duration) : max(t, 0)
    }

    private func isRunning(_ p: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: p.bundleID).isEmpty
    }

    func refresh() {
        guard !refreshing else { return }   // browser scans can be slow; don't pile up
        refreshing = true
        // Only script running apps: `tell application` would launch a closed one.
        let players = [Player.spotify, .music].filter(isRunning)
        let browsers = Browser.allCases.filter(\.isRunning)
        queue.async { [weak self] in
            var tracks = players.compactMap(Self.fetch)
            var needsSetup: Browser?
            for b in browsers {
                switch BrowserMedia.scan(b) {
                case .found(let h):
                    tracks.append(Track(source: .browser(h.browser, window: h.window, tab: h.tab, canSkip: h.canSkip), title: h.title,
                                        artist: h.artist, isPlaying: h.isPlaying, position: h.position,
                                        duration: h.duration, artworkURL: h.artwork, canSeek: h.seekable))
                case .needsSetup(let b): needsSetup = needsSetup ?? b
                case .none: break
                }
            }
            // Playing beats paused; otherwise apps come first.
            let best = tracks.first(where: \.isPlaying) ?? tracks.first
            DispatchQueue.main.async {
                guard let self else { return }
                self.refreshing = false
                self.browserNeedingSetup = needsSetup
                self.apply(best)
            }
        }
    }

    private func apply(_ t: Track?) {
        source = t?.source
        title = t?.title ?? ""
        artist = t?.artist ?? ""
        isPlaying = t?.isPlaying ?? false
        duration = t?.duration ?? 0
        position = t?.position ?? 0
        positionDate = Date()
        canSeek = t?.canSeek ?? false
        reschedule()

        let key = t.map { "\($0.source.name)|\($0.title)|\($0.artist)" } ?? ""
        guard key != artworkKey else { return }
        artworkKey = key
        artwork = nil
        accent = nil
        if let t { loadArtwork(t, key: key) }
    }

    private static func fetch(_ p: Player) -> Track? {
        // Spotify reports duration in milliseconds, Music in seconds.
        let durationExpr = p == .spotify ? "(duration of current track) / 1000" : "duration of current track"
        guard let r = runScript("""
            tell application "\(p.rawValue)"
                if player state is stopped then return ""
                return (name of current track) & "\\n" & (artist of current track) & "\\n" & ((player state is playing) as string) & "\\n" & (player position as string) & "\\n" & ((\(durationExpr)) as string)
            end tell
            """)?.stringValue, !r.isEmpty else { return nil }
        let parts = r.components(separatedBy: "\n")
        guard parts.count == 5 else { return nil }
        // `as string` on a real can use the locale's decimal comma.
        let num = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        return Track(source: .app(p), title: parts[0], artist: parts[1], isPlaying: parts[2] == "true",
                     position: num(parts[3]), duration: num(parts[4]))
    }

    private func loadArtwork(_ t: Track, key: String) {
        queue.async { [weak self] in
            switch t.source {
            case .app(.music):
                let data = Self.runScript("tell application \"Music\" to get data of artwork 1 of current track")?.data
                let image = data.flatMap(NSImage.init(data:))
                DispatchQueue.main.async { self?.setArtwork(image, key: key) }
            case .app(.spotify):
                let s = Self.runScript("tell application \"Spotify\" to get artwork url of current track")?.stringValue
                self?.download(s.flatMap(URL.init(string:)), key: key, fallback: nil)
            case .browser(let b, _, _, _):
                // Sites without Media Session artwork get the browser's icon.
                self?.download(t.artworkURL, key: key, fallback: b.icon)
            }
        }
    }

    private func download(_ url: URL?, key: String, fallback: NSImage?) {
        guard let url else {
            DispatchQueue.main.async { self.setArtwork(fallback, key: key) }
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let image = data.flatMap(NSImage.init(data:)) ?? fallback
            DispatchQueue.main.async { self?.setArtwork(image, key: key) }
        }.resume()
    }

    private func setArtwork(_ image: NSImage?, key: String) {
        guard key == artworkKey else { return }   // track changed while loading
        artwork = image
        accent = image.flatMap(ArtworkColor.accent)
    }

    func playPause() { send(app: "playpause", js: BrowserMedia.togglePlay) }
    func next() { send(app: "next track", js: BrowserMedia.skip(forward: true)) }
    func previous() { send(app: "previous track", js: BrowserMedia.skip(forward: false)) }

    /// Jumps to `seconds`. Updates the position right away so the bar doesn't snap back
    /// before the player reports the new position.
    func seek(to seconds: Double) {
        guard let s = source, canSeek else { return }
        position = min(max(seconds, 0), duration)
        positionDate = Date()
        let target = String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), position)
        queue.async { [weak self] in
            switch s {
            case .app(let p): _ = Self.runScript("tell application \"\(p.rawValue)\" to set player position to \(target)")
            case .browser(let b, let w, let t, _): BrowserMedia.run(BrowserMedia.seek(to: Double(target) ?? 0), browser: b, window: w, tab: t)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.refresh() }
        }
    }

    private func send(app command: String, js: String) {
        guard let s = source else { return }
        queue.async { [weak self] in
            switch s {
            case .app(let p): _ = Self.runScript("tell application \"\(p.rawValue)\" to \(command)")
            case .browser(let b, let w, let t, _): BrowserMedia.run(js, browser: b, window: w, tab: t)
            }
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    static func runScript(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}
