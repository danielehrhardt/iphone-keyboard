import XCTest
import KeyboardCore
@testable import Umlaut

/// The keyboard on the iPhone Duo's two displays, laid out the way the extension sizes itself.
/// Renders each case to /tmp/umlaut-ui/duo-*.png for a look.
@MainActor
final class DuoLayoutTests: XCTestCase {
    private struct Display {
        let name: String
        let screen: CGSize
        let regularWidth: Bool
        let regularHeight: Bool
        let bottomInset: CGFloat
    }

    private let cover = Display(name: "cover", screen: CGSize(width: 466, height: 678), regularWidth: false, regularHeight: true, bottomInset: 21)
    private let innerUpright = Display(name: "inner-upright", screen: CGSize(width: 669, height: 951), regularWidth: true, regularHeight: true, bottomInset: 20)
    private let innerSideways = Display(name: "inner-sideways", screen: CGSize(width: 951, height: 669), regularWidth: true, regularHeight: true, bottomInset: 20)

    private func render(_ display: Display, split: Bool = true, dark: Bool = false) -> (coordinator: KeyboardCoordinator, keyboardTop: CGFloat) {
        let settings = KeyboardSettings(defaults: UserDefaults(suiteName: "duo-\(UUID())")!)
        settings.splitKeyboard = split
        let traits = UITraitCollection().modifyingTraits {
            $0.userInterfaceIdiom = .phone
            $0.horizontalSizeClass = display.regularWidth ? .regular : .compact
            $0.verticalSizeClass = display.regularHeight ? .regular : .compact
            $0.userInterfaceStyle = dark ? .dark : .light
            $0.displayScale = 3
        }
        let coordinator = KeyboardCoordinator(settings: settings, proxy: FakeTextProxy(), engine: nil, traits: traits, tapMap: nil)
        let height = coordinator.updateEnvironment(traits: traits, screenSize: display.screen) + display.bottomInset
        let window = UIWindow(frame: CGRect(origin: .zero, size: display.screen))
        window.backgroundColor = dark ? UIColor(white: 0.05, alpha: 1) : UIColor(white: 0.96, alpha: 1)
        let backdrop = UIView(frame: CGRect(x: 0, y: display.screen.height - height, width: display.screen.width, height: height))
        backdrop.backgroundColor = KeyboardTheme.current(traits: traits, settings: settings).backdropFallback
        window.addSubview(backdrop)
        let kv = coordinator.view
        kv.frame = backdrop.frame
        window.addSubview(kv)
        window.isHidden = false
        kv.layoutIfNeeded()
        // Outside a real keyboard window the safe area is unknown; keep the home-indicator strip.
        kv.grid.frame.size.height = height - kv.suggestionHeight - display.bottomInset
        kv.setNeedsLayout()
        kv.layoutIfNeeded()
        kv.grid.frame.size.height = height - kv.suggestionHeight - display.bottomInset
        kv.onLayout?()

        let dir = URL(fileURLWithPath: "/tmp/umlaut-ui")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { ctx in window.layer.render(in: ctx.cgContext) }
        let suffix = (split ? "" : "-unsplit") + (dark ? "-dark" : "")
        try? image.pngData()?.write(to: dir.appendingPathComponent("duo-\(display.name)\(suffix).png"))
        return (coordinator, display.screen.height - height)
    }

    func testSidewaysInnerDisplaySplitsAroundTheFold() {
        let (c, _) = render(innerSideways)
        let grid = c.view.grid
        let geometry = try! XCTUnwrap(grid.geometry)
        XCTAssertTrue(geometry.isSplit)
        let fold = innerSideways.screen.width / 2 - grid.frame.minX
        for kf in geometry.keyFrames {
            XCTAssertFalse(kf.frame.minX < fold && kf.frame.maxX > fold, "\(kf.key.id) lies on the fold")
        }
        XCTAssertGreaterThan(geometry.rowHeight, 44)
        _ = render(innerSideways, dark: true)
    }

    func testSplitCanBeTurnedOff() {
        let (c, _) = render(innerSideways, split: false)
        XCTAssertEqual(c.view.grid.geometry?.isSplit, false)
    }

    func testUprightInnerDisplayKeepsTheKeysBelowTheFold() {
        let (c, top) = render(innerUpright)
        XCTAssertGreaterThan(top, innerUpright.screen.height / 2, "the fold runs across the middle")
        let geometry = try! XCTUnwrap(c.view.grid.geometry)
        XCTAssertFalse(geometry.isSplit)
        let aspect = geometry.unitWidth / geometry.rowHeight
        XCTAssertLessThan(aspect, 1.25, "keys stay close to the phone's proportions, not stretched")
    }

    func testCoverDisplayIsAnOrdinaryPhoneKeyboard() {
        let (c, _) = render(cover)
        let geometry = try! XCTUnwrap(c.view.grid.geometry)
        XCTAssertFalse(geometry.isSplit)
        XCTAssertEqual(geometry.verticalGap, KeyboardGeometry.Metrics.phonePortrait.verticalGap)
    }
}
