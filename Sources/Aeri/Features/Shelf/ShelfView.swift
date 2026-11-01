import AppKit
import SwiftUI

struct ShelfView: View {
    @ObservedObject var shelf: Shelf
    @ObservedObject var state: NotchState

    var body: some View {
        Group {
            if shelf.items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down").font(.title3)
                    Text("Drop files here").font(.system(size: 11))
                }
                .foregroundStyle(.white.opacity(state.dropTargeted ? 0.9 : 0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 8) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(shelf.items, id: \.self) { url in
                                ShelfItemView(url: url) { shelf.remove(url) }
                            }
                        }
                    }
                    Button(action: shelf.clear) {
                        Image(systemName: "xmark.bin").font(.system(size: 13))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .help("Clear shelf")
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(state.dropTargeted ? 0.6 : 0.15),
                              style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .animation(.easeOut(duration: 0.15), value: state.dropTargeted)
        )
    }
}

/// Icon and name. Drag out to use the file, double-click to open, hover for a remove button.
private struct ShelfItemView: View {
    let url: URL
    let onRemove: () -> Void
    @StateObject private var hover = HoverFlag()

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable().frame(width: 36, height: 36)
            Text(url.lastPathComponent)
                .font(.system(size: 9)).lineLimit(1).truncationMode(.middle)
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: 60)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(.white.opacity(hover.on ? 0.1 : 0)))
        .overlay(alignment: .topTrailing) {
            if hover.on {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onHover { hover.on = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onDrag {
            // Hand over the file URL (like a Finder drag) so the destination copies the real file
            // with its original name; contents-only providers make Finder invent one ("PDF document").
            let provider = NSItemProvider(object: url as NSURL)
            provider.suggestedName = url.lastPathComponent
            return provider
        }
        .help(url.path)
    }
}
