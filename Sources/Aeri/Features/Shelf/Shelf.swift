import AppKit

/// Files held temporarily on the notch. Stores references only; nothing is copied or moved.
/// In memory, so the shelf is empty after relaunch.
final class Shelf: ObservableObject {
    @Published private(set) var items: [URL] = []

    func add(_ urls: [URL]) {
        for u in urls where !items.contains(u) { items.append(u) }
    }

    func remove(_ url: URL) { items.removeAll { $0 == url } }
    func clear() { items.removeAll() }

    /// Drops files that were deleted or moved since they were shelved.
    func prune() {
        let alive = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        if alive != items { items = alive }
    }

    /// Accepts file URLs from a drop. Returns false if nothing looked like a file.
    func accept(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier("public.file-url") }
        for p in files {
            p.loadItem(forTypeIdentifier: "public.file-url") { [weak self] item, _ in
                guard let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { self?.add([url]) }
            }
        }
        return !files.isEmpty
    }
}
