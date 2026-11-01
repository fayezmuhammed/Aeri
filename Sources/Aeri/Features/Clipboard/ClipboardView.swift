import SwiftUI

struct ClipboardView: View {
    @ObservedObject var history: ClipboardHistory

    var body: some View {
        if history.items.isEmpty {
            VStack(spacing: 4) {
                Image(systemName: "doc.on.clipboard").font(.title3)
                Text("Copied items appear here").font(.system(size: 11))
            }
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(history.items) { item in
                            ClipCard(item: item,
                                     onCopy: { history.copy(item) },
                                     onRemove: { history.remove(item) })
                        }
                    }
                }
                Button(action: history.clear) {
                    Image(systemName: "xmark.bin").font(.system(size: 13))
                }
                .buttonStyle(PressableButtonStyle())
                .help("Clear history")
            }
        }
    }
}

/// Click to copy again. Hex colors show a swatch, images a thumbnail, links their host.
private struct ClipCard: View {
    let item: ClipboardHistory.Item
    let onCopy: () -> Void
    let onRemove: () -> Void
    @StateObject private var hover = HoverFlag()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            preview.frame(width: 72, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(caption).font(.system(size: 9)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 72, alignment: .leading)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.white.opacity(hover.on ? 0.14 : 0.07)))
        .overlay(alignment: .topTrailing) {
            if hover.on {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
                .padding(2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hover.on = $0 }
        .onTapGesture(perform: onCopy)
        .help("Click to copy")
    }

    @ViewBuilder private var preview: some View {
        switch item.kind {
        case .color(_, let c):
            Rectangle().fill(Color(nsColor: c))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.2)))
        case .image(let img):
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
        case .link(let url):
            ZStack {
                Color.white.opacity(0.08)
                VStack(spacing: 2) {
                    Image(systemName: "link").font(.system(size: 12))
                    Text(Self.host(url)).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                }
                .padding(.horizontal, 4)
            }
        case .text(let s):
            ZStack(alignment: .topLeading) {
                Color.white.opacity(0.08)
                Text(s).font(.system(size: 9)).lineLimit(3).padding(4)
            }
        }
    }

    private var caption: String {
        switch item.kind {
        case .color(let hex, _): return hex
        case .image(let img): return "Image \(Int(img.size.width))×\(Int(img.size.height))"
        case .link(let url): return url.absoluteString
        case .text(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func host(_ url: URL) -> String {
        let h = url.host ?? ""
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }
}
