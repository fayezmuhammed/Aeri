import AppKit

/// Finds a playing <video>/<audio> element in browser tabs by running JavaScript through AppleScript.
/// Requires the user to enable "Allow JavaScript from Apple Events" once per browser
/// (Safari: Develop menu; Chrome-based: View > Developer). Only top-level frames are checked,
/// so players inside iframes aren't seen.
enum Browser: String, CaseIterable {
    case safari = "Safari"
    case chrome = "Google Chrome"
    case brave = "Brave Browser"
    case edge = "Microsoft Edge"
    case arc = "Arc"

    var bundleID: String {
        switch self {
        case .safari: return "com.apple.Safari"
        case .chrome: return "com.google.Chrome"
        case .brave: return "com.brave.Browser"
        case .edge: return "com.microsoft.edgemac"
        case .arc: return "company.thebrowser.Browser"
        }
    }

    var isRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    var icon: NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    /// Where the user turns on JavaScript from Apple Events.
    var setupHint: String {
        self == .safari ? "Safari: Develop › Allow JavaScript from Apple Events"
                        : "\(rawValue): View › Developer › Allow JavaScript from Apple Events"
    }

    /// AppleScript that runs `js` in `tab` (an AppleScript tab reference).
    func runJS(_ js: String, in tab: String) -> String {
        // Must be an expression: `set r to tell t to execute ...` doesn't compile.
        self == .safari ? "do JavaScript \"\(js)\" in \(tab)" : "execute \(tab) javascript \"\(js)\""
    }
}

enum BrowserMedia {
    struct Hit {
        let browser: Browser
        let window: Int
        let tab: Int
        let title: String
        let artist: String
        let isPlaying: Bool
        let position: Double
        let duration: Double
        let artwork: URL?
        let canSkip: Bool
    }

    enum Result {
        case found(Hit)
        case none
        case needsSetup(Browser)
    }

    // JavaScript kept free of double quotes and backslashes so it can sit in an AppleScript string.
    //
    // Sites like Spotify Web play through an audio element kept off the page, so querySelectorAll can't
    // see it; their Media Session metadata (title, artist, artwork) is still readable. When the page has
    // its own player controls (Spotify Web data-testids, YouTube .ytp-* buttons) we read and click those:
    // they give the real play state and position (the element's duration is wrong for streamed chunks)
    // and real next/previous track.
    private static let findMedia = "var els=Array.from(document.querySelectorAll('video,audio'));var m=els.find(function(e){return !e.paused})||els.find(function(e){return e.currentTime>0&&!e.ended});"
    private static let findControls = "var q=function(s){return document.querySelector(s)};var btnPlay=q('[data-testid=control-button-playpause]');var btnNext=q('[data-testid=control-button-skip-forward]')||q('.ytp-next-button');var btnPrev=q('[data-testid=control-button-skip-back]')||q('.ytp-prev-button');"

    private static let probe = "(function(){" + findMedia + findControls + "var md=navigator.mediaSession&&navigator.mediaSession.metadata;if(!m&&!md)return '';var art=md&&md.artwork&&md.artwork.length?md.artwork[md.artwork.length-1].src:'';var playing=m?!m.paused:(navigator.mediaSession.playbackState=='playing'||(!!btnPlay&&/pause/i.test(btnPlay.getAttribute('aria-label')||'')));if(btnPlay&&m&&!els.some(function(e){return !e.paused}))playing=/pause/i.test(btnPlay.getAttribute('aria-label')||'');var pos=m?m.currentTime:0,dur=m&&isFinite(m.duration)?m.duration:0;var t2s=function(x){return x.trim().split(':').reduce(function(a,b){return a*60+(+b)},0)};var pe=q('[data-testid=playback-position]'),de=q('[data-testid=playback-duration]');if(pe&&de){pos=t2s(pe.textContent);var d=de.textContent.trim();dur=d.charAt(0)=='-'?pos+t2s(d.slice(1)):t2s(d)}return JSON.stringify({title:(md&&md.title)||document.title,artist:(md&&md.artist)||location.hostname.replace(/^www[.]/,''),playing:playing,position:pos,duration:dur,artwork:art,canSkip:!!(btnNext&&btnPrev)})})()"

    static let togglePlay = "(function(){" + findMedia + findControls + "if(btnPlay)btnPlay.click();else if(m){m.paused?m.play():m.pause()}return ''})()"

    /// Clicks the site's next/previous button if it has one, otherwise seeks ±10s.
    static func skip(forward: Bool) -> String {
        "(function(){" + findMedia + findControls + "var b=\(forward ? "btnNext" : "btnPrev");if(b)b.click();else if(m){m.currentTime=Math.max(0,m.currentTime+(\(forward ? 10 : -10)))}return ''})()"
    }

    /// Scans every tab, returning the first playing one, else the first paused one.
    static func scan(_ b: Browser) -> Result {
        let source = """
            tell application "\(b.rawValue)"
                set found to ""
                set lastErr to ""
                set wi to 0
                repeat with w in windows
                    set wi to wi + 1
                    set ti to 0
                    try
                        repeat with t in tabs of w
                            set ti to ti + 1
                            try
                                set r to \(b.runJS(probe, in: "t"))
                                if r is not missing value and r is not "" then
                                    set hit to (wi as string) & linefeed & (ti as string) & linefeed & r
                                    if r contains (quote & "playing" & quote & ":true") then return hit
                                    if found is "" then set found to hit
                                end if
                            on error msg
                                set lastErr to msg
                            end try
                        end repeat
                    end try
                end repeat
                if found is "" and lastErr is not "" then return "ERR:" & lastErr
                return found
            end tell
            """
        guard let r = NowPlaying.runScript(source)?.stringValue, !r.isEmpty else { return .none }
        if r.hasPrefix("ERR:") { return r.contains("JavaScript") ? .needsSetup(b) : .none }
        let parts = r.split(separator: "\n", maxSplits: 2).map(String.init)
        guard parts.count == 3, let w = Int(parts[0]), let t = Int(parts[1]),
              let json = try? JSONSerialization.jsonObject(with: Data(parts[2].utf8)) as? [String: Any] else { return .none }
        let art = (json["artwork"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) }
        return .found(Hit(browser: b, window: w, tab: t,
                          title: json["title"] as? String ?? "",
                          artist: json["artist"] as? String ?? "",
                          isPlaying: json["playing"] as? Bool ?? false,
                          position: (json["position"] as? NSNumber)?.doubleValue ?? 0,
                          duration: (json["duration"] as? NSNumber)?.doubleValue ?? 0,
                          artwork: art,
                          canSkip: json["canSkip"] as? Bool ?? false))
    }

    static func run(_ js: String, browser: Browser, window: Int, tab: Int) {
        _ = NowPlaying.runScript("""
            tell application "\(browser.rawValue)"
                \(browser.runJS(js, in: "tab \(tab) of window \(window)"))
            end tell
            """)
    }
}
