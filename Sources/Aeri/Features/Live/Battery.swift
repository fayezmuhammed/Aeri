import Foundation
import IOKit.ps

/// Reports plugging in / unplugging and low battery (20% and 10%) using IOKit power-source
/// notifications. No permission needed. Does nothing on Macs without an internal battery.
final class BatteryMonitor {
    private let onEvent: (LiveActivity) -> Void
    private var source: CFRunLoopSource?
    private var lastOnPower: Bool?
    private var warned = Set<Int>()
    private static let thresholds = [20, 10]

    init(onEvent: @escaping (LiveActivity) -> Void) {
        self.onEvent = onEvent
        read(initial: true)
        let context = Unmanaged.passUnretained(self).toOpaque()
        source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue().read(initial: false)
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }
    }

    private func read(initial: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(d[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let level = current * 100 / maximum
            let onPower = d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            defer { lastOnPower = onPower }

            if initial {
                // Don't alert at launch for a level that's already low.
                warned = Set(Self.thresholds.filter { level <= $0 })
                return
            }
            if onPower != lastOnPower {
                warned = onPower ? [] : Set(Self.thresholds.filter { level <= $0 })
                onEvent(.battery(level: level, onPower: onPower, low: false))
            } else if !onPower, Self.thresholds.contains(where: { level <= $0 && !warned.contains($0) }) {
                warned.formUnion(Self.thresholds.filter { level <= $0 })
                onEvent(.battery(level: level, onPower: false, low: true))
            }
            return
        }
    }
}
