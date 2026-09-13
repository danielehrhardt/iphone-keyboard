import UIKit
import ImageIO
import UniformTypeIdentifiers
import KeyboardCore

/// Feeds the system pasteboard into the `ClipboardHistory`.
///
/// The pasteboard is only *read* when its change count moved since the last capture (reading
/// shows the system's "pasted from …" banner and may ask for permission, so it must not happen
/// on every keystroke); the change count itself and the type queries are free. The count of
/// the last captured clip lives in the shared settings, so the app and the keyboard extension
/// never read the same clip twice.
final class ClipboardMonitor {
    let history: ClipboardHistory
    private let settings: KeyboardSettings
    private let pasteboard: UIPasteboard
    private var lastCheck: CFTimeInterval = 0

    /// Longest side of the stored copy of an image; more would not fit the extension's memory
    /// budget when several are shown, and pasting it back at this size is plenty for chats.
    static let storedImageMaxPixels = 1280
    static let thumbnailMaxPixels = 200

    init(history: ClipboardHistory, settings: KeyboardSettings, pasteboard: UIPasteboard = .general) {
        self.history = history
        self.settings = settings
        self.pasteboard = pasteboard
    }

    /// Drops expired items (call when the keyboard appears and before showing the history).
    func prune() {
        history.reloadIfChanged()
        history.prune(retention: settings.clipboardRetention)
    }

    /// Captures the current clip if there is a new one. Cheap when nothing changed; calls
    /// closer than `minimumInterval` apart are skipped so the host's edit reports (one per
    /// keystroke) do not turn into pasteboard queries.
    @discardableResult
    func captureIfChanged(minimumInterval: CFTimeInterval = 0) -> ClipboardItem? {
        guard settings.clipboardHistory else { return nil }
        let now = CACurrentMediaTime()
        guard now - lastCheck >= minimumInterval else { return nil }
        lastCheck = now
        let count = pasteboard.changeCount
        guard count != settings.clipboardChangeCount else { return nil }
        // Claim the clip before reading it: a failed or empty read must not be retried on every call.
        settings.clipboardChangeCount = count
        history.reloadIfChanged()
        return capture()
    }

    /// Reads the pasteboard and stores what it holds. Text wins over images when a clip carries
    /// both (a copied web selection comes with its rendering).
    private func capture() -> ClipboardItem? {
        if pasteboard.hasStrings, let s = pasteboard.string, ClipboardHistory.isStorable(s) {
            return history.addText(s)
        }
        if pasteboard.hasImages, let (type, data) = imageData() {
            return storeImage(data: data, type: type)
        }
        if pasteboard.hasURLs, let url = pasteboard.url {
            return history.addText(url.absoluteString)
        }
        return nil
    }

    /// The raw bytes of the clip's image in the first image type it offers; decoding happens
    /// later through ImageIO at thumbnail size, never as a full-size `UIImage`.
    private func imageData() -> (UTType, Data)? {
        for identifier in pasteboard.types {
            guard let type = UTType(identifier), type.conforms(to: .image),
                  let data = pasteboard.data(forPasteboardType: identifier), !data.isEmpty else { continue }
            return (type, data)
        }
        return nil
    }

    private func storeImage(data: Data, type: UTType) -> ClipboardItem? {
        guard let scaled = Self.downscale(data, maxPixels: Self.storedImageMaxPixels),
              let thumb = Self.downscale(data, maxPixels: Self.thumbnailMaxPixels, forceJPEG: true) else { return nil }
        return history.addImage(data: scaled.data, thumbnail: thumb.data, fileExtension: scaled.fileExtension,
                                width: scaled.width, height: scaled.height, hash: ClipboardHistory.hash(of: data))
    }

    /// Puts an item back on the pasteboard (the user pastes it with the system's Paste command;
    /// a keyboard can only *type* text, not insert images). The new change count is recorded
    /// so the item is not captured again as a fresh clip.
    func copyToPasteboard(_ item: ClipboardItem) {
        switch item.kind {
        case .text:
            pasteboard.string = item.text
        case .image:
            guard let data = history.imageData(for: item) else { return }
            let isPNG = item.imageFile?.hasSuffix(".png") ?? false
            pasteboard.setData(data, forPasteboardType: (isPNG ? UTType.png : UTType.jpeg).identifier)
        }
        settings.clipboardChangeCount = pasteboard.changeCount
    }

    // MARK: Images

    struct ScaledImage {
        let data: Data
        let fileExtension: String
        let width: Int
        let height: Int
    }

    /// Re-encodes `data` with its longest side at most `maxPixels`, via ImageIO's thumbnail path
    /// so a 12-megapixel photo never gets decoded in full. Images with transparency stay PNG,
    /// everything else becomes JPEG.
    static func downscale(_ data: Data, maxPixels: Int, forceJPEG: Bool = false) -> ScaledImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let thumbOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }
        let hasAlpha: Bool
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: hasAlpha = false
        default: hasAlpha = true
        }
        let png = hasAlpha && !forceJPEG
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out, (png ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil) else { return nil }
        let properties = png ? nil : [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return ScaledImage(data: out as Data, fileExtension: png ? "png" : "jpg", width: image.width, height: image.height)
    }
}
