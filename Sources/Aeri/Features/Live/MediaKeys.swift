import AppKit
import ApplicationServices

/// Volume and brightness keys.
/// - Always: watches brightness keys (passively) to show the brightness bar. Volume changes come
///   from SystemAudio's listener instead, so they're caught from any source.
/// - With "replace system HUD" on and Accessibility granted: an event tap consumes the five keys
///   and applies the change itself, so macOS never shows its on-screen box.
final class MediaKeys: ObservableObject {
    @Published private(set) var trusted = AXIsProcessTrusted()

    private let audio: SystemAudio
    private let onBrightness: (Float) -> Void
    private var monitor: Any?
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var trustPoll: Timer?
    private var replacing = false

    private enum Key: Int {
        case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7
    }

    /// NX_SYSDEFINED, the event type media keys arrive as.
    private static let systemDefined = CGEventType(rawValue: 14)!

    init(audio: SystemAudio, onBrightness: @escaping (Float) -> Void) {
        self.audio = audio
        self.onBrightness = onBrightness
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] e in
            guard let self, let (key, down) = Self.decode(e), down,
                  key == .brightnessUp || key == .brightnessDown else { return }
            // macOS applies the change asynchronously; read it a moment later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if let b = Brightness.get() { self.onBrightness(b) }
            }
        }
    }

    func setReplacing(_ on: Bool) {
        replacing = on
        if on {
            if AXIsProcessTrusted() { installTap() } else { requestAccess() }
        } else {
            removeTap()
        }
    }

    /// Shows the system Accessibility prompt, then waits for the user to grant it.
    func requestAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        trusted = AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
        guard !trusted else { return installTap() }
        trustPoll?.invalidate()
        trustPoll = .scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self, AXIsProcessTrusted() else { return }
            t.invalidate()
            self.trusted = true
            if self.replacing { self.installTap() }
        }
    }

    func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func installTap() {
        guard tap == nil else { return }
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let me = Unmanaged<MediaKeys>.fromOpaque(refcon!).takeUnretainedValue()
            return me.handle(type, event)
        }
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                eventsOfInterest: CGEventMask(1 << Self.systemDefined.rawValue),
                                callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else { return }
        tapSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), tapSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables slow taps; turn it back on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard replacing, type == Self.systemDefined, let e = NSEvent(cgEvent: event),
              let (key, down) = Self.decode(e) else { return Unmanaged.passUnretained(event) }
        if down { perform(key, fine: e.modifierFlags.contains([.option, .shift])) }
        return nil   // swallow both key-down and key-up so the system HUD never appears
    }

    private static func decode(_ e: NSEvent) -> (Key, Bool)? {
        guard e.type == .systemDefined, e.subtype.rawValue == 8 else { return nil }
        let code = (e.data1 & 0xFFFF0000) >> 16
        let down = ((e.data1 & 0xFF00) >> 8) == 0xA
        return Key(rawValue: code).map { ($0, down) }
    }

    /// Same steps as macOS: 16 per full range, or 64 with Option-Shift.
    private func perform(_ key: Key, fine: Bool) {
        let step: Float = fine ? 1 / 64 : 1 / 16
        let stepped = { (v: Float, d: Float) in min(max(((v + d) / step).rounded() * step, 0), 1) }
        switch key {
        case .volumeUp:
            audio.muted = false
            audio.volume = stepped(audio.volume, step)
        case .volumeDown:
            audio.volume = stepped(audio.volume, -step)
        case .mute:
            audio.muted.toggle()
        case .brightnessUp, .brightnessDown:
            guard let b = Brightness.get() else { return }
            let new = stepped(b, key == .brightnessUp ? step : -step)
            Brightness.set(new)
            onBrightness(new)
        }
    }
}
