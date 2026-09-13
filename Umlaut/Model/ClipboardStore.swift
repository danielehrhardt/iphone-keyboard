import Foundation
import UIKit
import KeyboardCore

/// Observable view of the clipboard history shared with the keyboard extension.
@MainActor
final class ClipboardStore: ObservableObject {

    @Published private(set) var items: [ClipboardItem] = []

    private let settings = KeyboardSettings.shared
    private let monitor: ClipboardMonitor
    private var thumbnails: [UUID: UIImage] = [:]

    init() {
        monitor = ClipboardMonitor(history: .shared(appGroup: KeyboardSettings.appGroup), settings: settings)
        reload()
    }

    /// Drops expired items, picks up what the keyboard stored meanwhile and captures a clip
    /// copied since the last check (the app is a second collector while it is open).
    func reload() {
        monitor.prune()
        monitor.captureIfChanged()
        items = monitor.history.items
        thumbnails = thumbnails.filter { id, _ in items.contains { $0.id == id } }
    }

    func thumbnail(for item: ClipboardItem) -> UIImage? {
        if let cached = thumbnails[item.id] { return cached }
        guard let data = monitor.history.thumbnailData(for: item), let image = UIImage(data: data) else { return nil }
        thumbnails[item.id] = image
        return image
    }

    /// The stored (downscaled) image of an image item.
    func image(for item: ClipboardItem) -> UIImage? {
        monitor.history.imageData(for: item).flatMap(UIImage.init(data:))
    }

    /// Puts the item back on the system pasteboard.
    func copy(_ item: ClipboardItem) {
        monitor.copyToPasteboard(item)
    }

    func remove(at offsets: IndexSet) {
        for id in offsets.map({ items[$0].id }) { monitor.history.remove(id: id) }
        reload()
    }

    func remove(_ item: ClipboardItem) {
        monitor.history.remove(id: item.id)
        reload()
    }

    func removeAll() {
        monitor.history.removeAll()
        reload()
    }
}
