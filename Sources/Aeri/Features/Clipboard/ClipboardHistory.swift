import AppKit

/// Recent clipboard entries, detected by polling the pasteboard's change count (macOS has no
/// clipboard notification). In memory only; skips items password managers mark as concealed.
final class ClipboardHistory: ObservableObject {
    enum Kind {
        case text(String)
        case link(URL)
        case color(String, NSColor)   // normalized "#RRGGBB"
        case image(NSImage)
    }

    struct Item: Identifiable {
        let id = UUID()
        let kind: Kind
        let date = Date()
    }

    @Published private(set) var items: [Item] = []

    private let limit = 20
    private var lastChange = NSPasteboard.general.changeCount
    private var timer: Timer?

    init() {
        timer = .scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChange else { return }
        lastChange = pb.changeCount
        let types = pb.types ?? []
        // nspasteboard.org conventions: secrets and app-internal temporary data.
        let skip = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType"].map { NSPasteboard.PasteboardType($0) }
        guard !types.contains(where: skip.contains) else { return }
        guard let kind = Self.classify(pb) else { return }
        add(kind)
    }

    private static func classify(_ pb: NSPasteboard) -> Kind? {
        // Images first: copied screenshots have no text representation.
        if pb.availableType(from: [.png, .tiff]) != nil, let image = NSImage(pasteboard: pb) {
            return .image(image)
        }
        guard let raw = pb.string(forType: .string) else { return nil }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if let (hex, color) = parseHex(s) { return .color(hex, color) }
        if !s.contains(where: \.isWhitespace), let url = URL(string: s),
           ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
            return .link(url)
        }
        return .text(raw)
    }

    /// "#abc", "abc", "#aabbcc" or "aabbcc".
    private static func parseHex(_ s: String) -> (String, NSColor)? {
        var h = s.hasPrefix("#") ? String(s.dropFirst()) : s
        guard [3, 6].contains(h.count), h.allSatisfy(\.isHexDigit) else { return nil }
        // Without "#", only accept 6 digits containing a letter, so numbers like "123456" stay text.
        if !s.hasPrefix("#") && (h.count != 6 || h.allSatisfy(\.isNumber)) { return nil }
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard let v = UInt32(h, radix: 16) else { return nil }
        let color = NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        return ("#" + h.uppercased(), color)
    }

    private func add(_ kind: Kind) {
        items.removeAll { Self.same($0.kind, kind) }
        items.insert(Item(kind: kind), at: 0)
        if items.count > limit { items.removeLast(items.count - limit) }
    }

    private static func same(_ a: Kind, _ b: Kind) -> Bool {
        switch (a, b) {
        case let (.text(x), .text(y)): return x == y
        case let (.link(x), .link(y)): return x == y
        case let (.color(x, _), .color(y, _)): return x == y
        case let (.image(x), .image(y)): return x.tiffRepresentation == y.tiffRepresentation
        default: return false
        }
    }

    /// Puts an entry back on the clipboard; it moves to the front of the history.
    func copy(_ item: Item) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text(let s): pb.setString(s, forType: .string)
        case .link(let u): pb.setString(u.absoluteString, forType: .string)
        case .color(let hex, _): pb.setString(hex, forType: .string)
        case .image(let img): pb.writeObjects([img])
        }
        lastChange = pb.changeCount
        add(item.kind)
    }

    func remove(_ item: Item) { items.removeAll { $0.id == item.id } }
    func clear() { items.removeAll() }
}
