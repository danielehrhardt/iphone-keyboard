import XCTest
@testable import KeyboardCore

final class ClipboardHistoryTests: XCTestCase {
    private var directory: URL!
    private var history: ClipboardHistory!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("clipboard-tests-\(UUID().uuidString)", isDirectory: true)
        history = ClipboardHistory(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private var imagesDirectory: URL { directory.appendingPathComponent("images") }
    private func imageFiles() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: imagesDirectory.path))?.sorted() ?? []
    }

    func testNewestTextComesFirstAndBlankTextIsIgnored() {
        XCTAssertNil(history.addText("   \n"))
        history.addText("erstes", at: Date(timeIntervalSince1970: 100))
        history.addText("zweites", at: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(history.items.map(\.text), ["zweites", "erstes"])
        XCTAssertEqual(history.items[0].kind, .text)
        XCTAssertEqual(history.items[0].preview, "zweites")
    }

    func testCopyingTheSameTextAgainMovesItToTheTop() {
        history.addText("a", at: Date(timeIntervalSince1970: 100))
        history.addText("b", at: Date(timeIntervalSince1970: 200))
        let again = history.addText("a", at: Date(timeIntervalSince1970: 300))
        XCTAssertEqual(history.items.map(\.text), ["a", "b"])
        XCTAssertEqual(history.items.count, 2)
        XCTAssertEqual(again?.id, history.items[0].id)
        XCTAssertEqual(history.items[0].createdAt, Date(timeIntervalSince1970: 300))
    }

    func testPreviewCollapsesWhitespace() {
        history.addText("  Hallo\n\n  Welt\t!  ")
        XCTAssertEqual(history.items[0].preview, "Hallo Welt !")
        XCTAssertEqual(history.items[0].text, "  Hallo\n\n  Welt\t!  ", "the stored text keeps its shape")
    }

    func testVeryLongTextIsCut() {
        let long = String(repeating: "x", count: ClipboardHistory.maxTextLength + 500)
        history.addText(long)
        XCTAssertEqual(history.items[0].text?.count, ClipboardHistory.maxTextLength)
    }

    func testImagesAreStoredAsFilesAndDeletedWithTheItem() throws {
        let item = try XCTUnwrap(history.addImage(data: Data([1, 2, 3]), thumbnail: Data([4]), fileExtension: "jpg",
                                                  width: 640, height: 480, hash: "abc"))
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(item.preview, "Bild · 640 × 480")
        XCTAssertEqual(imageFiles().count, 2)
        XCTAssertEqual(history.imageData(for: item), Data([1, 2, 3]))
        XCTAssertEqual(history.thumbnailData(for: item), Data([4]))
        // Same source image again: one item, moved to the top, no second copy on disk.
        history.addText("dazwischen")
        history.addImage(data: Data([9]), thumbnail: Data([9]), fileExtension: "jpg", width: 640, height: 480, hash: "abc")
        XCTAssertEqual(history.items.count, 2)
        XCTAssertEqual(history.items[0].id, item.id)
        XCTAssertEqual(imageFiles().count, 2)
        history.remove(id: item.id)
        XCTAssertEqual(history.items.map(\.text), ["dazwischen"])
        XCTAssertEqual(imageFiles(), [])
    }

    func testPruneDropsExpiredItemsAndTheirFiles() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        history.addText("alt", at: now.addingTimeInterval(-2 * 86_400))
        history.addImage(data: Data([1]), thumbnail: Data([1]), fileExtension: "png", width: 1, height: 1, hash: "old",
                         at: now.addingTimeInterval(-90_000))
        history.addText("frisch", at: now.addingTimeInterval(-3_600))
        XCTAssertEqual(history.prune(retention: .forever, now: now), 0)
        XCTAssertEqual(history.prune(retention: .day, now: now), 2)
        XCTAssertEqual(history.items.map(\.text), ["frisch"])
        XCTAssertEqual(imageFiles(), [])
        XCTAssertEqual(history.prune(retention: .hour, now: now.addingTimeInterval(1)), 1)
        XCTAssertTrue(history.isEmpty)
    }

    func testLimitsKeepTheNewestItems() {
        history.maxItems = 3
        history.maxImageItems = 1
        for i in 0..<5 { history.addText("t\(i)", at: Date(timeIntervalSince1970: Double(i))) }
        XCTAssertEqual(history.items.map(\.text), ["t4", "t3", "t2"])
        history.addImage(data: Data([1]), thumbnail: Data([1]), fileExtension: "jpg", width: 1, height: 1, hash: "one", at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(history.items.map(\.kind), [.image, .text, .text])
        XCTAssertEqual(imageFiles().count, 2)
        // A second image pushes the first out (only one is kept), the texts stay.
        history.addImage(data: Data([2]), thumbnail: Data([2]), fileExtension: "jpg", width: 1, height: 1, hash: "two", at: Date(timeIntervalSince1970: 11))
        XCTAssertEqual(history.items.filter { $0.kind == .image }.map(\.contentHash), ["itwo"])
        XCTAssertEqual(history.items.map(\.text), [nil, "t4", "t3"])
        XCTAssertEqual(imageFiles().count, 2, "the dropped image's files are gone")
    }

    func testPersistsAndReloadsAcrossInstances() throws {
        history.addText("bleibt", at: Date(timeIntervalSince1970: 42))
        let image = try XCTUnwrap(history.addImage(data: Data([7]), thumbnail: Data([8]), fileExtension: "png", width: 10, height: 20, hash: "img",
                                                   at: Date(timeIntervalSince1970: 43)))
        let reopened = ClipboardHistory(directory: directory)
        XCTAssertEqual(reopened.items, history.items)
        XCTAssertEqual(reopened.imageData(for: image), Data([7]))

        // The other process writes: the open instance picks it up on `reloadIfChanged`.
        reopened.removeAll()
        XCTAssertEqual(history.items.count, 2)
        history.reloadIfChanged()
        XCTAssertTrue(history.items.isEmpty)
        XCTAssertEqual(imageFiles(), [])
    }

    func testInMemoryHistoryWorksWithoutADirectory() {
        let memory = ClipboardHistory(directory: nil)
        memory.addText("nur im Speicher")
        XCTAssertNotNil(memory.addImage(data: Data([1]), thumbnail: Data([1]), fileExtension: "jpg", width: 1, height: 1, hash: "x"))
        XCTAssertEqual(memory.items.count, 2)
        XCTAssertNil(memory.imageData(for: memory.items[0]))
    }

    func testRetentionSetting() {
        let settings = KeyboardSettings(defaults: UserDefaults(suiteName: "clipboard-settings-\(UUID())")!)
        XCTAssertTrue(settings.clipboardHistory)
        XCTAssertEqual(settings.clipboardRetention, .day)
        settings.clipboardRetention = .week
        XCTAssertEqual(settings.clipboardRetention, .week)
        XCTAssertEqual(ClipboardRetention.week.duration, 7 * 86_400)
        XCTAssertNil(ClipboardRetention.forever.duration)
    }
}
