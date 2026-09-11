import UIKit
import KeyboardCore

protocol KeyGridDelegate: AnyObject {
    func keyGrid(_ grid: KeyGridView, didTap key: Key)
    func keyGrid(_ grid: KeyGridView, didInsertAlternate text: String, for key: Key)
    func keyGrid(_ grid: KeyGridView, didSwipe path: [CGPoint], keyMap: KeyMap)
    func keyGrid(_ grid: KeyGridView, didLongPress key: Key)
    func keyGridBackspaceRepeat(_ grid: KeyGridView, wordwise: Bool)
    func keyGrid(_ grid: KeyGridView, moveCursorBy offset: Int)
    func keyGridDidDoubleTapShift(_ grid: KeyGridView)
    func keyGrid(_ grid: KeyGridView, didShiftSlideTo key: Key)
    /// Raw touch events on the globe key, forwarded to `handleInputModeList(from:with:)`.
    func keyGrid(_ grid: KeyGridView, globeTouchEvent event: UIEvent?)
    var swipeTypingEnabled: Bool { get }
    var keyPreviewEnabled: Bool { get }
    var swipeTrailEnabled: Bool { get }
    var longPressNumbersEnabled: Bool { get }
}

/// The key area: renders `KeyView`s from a `KeyboardGeometry` and turns raw touches into taps,
/// long-presses, glide gestures, backspace repeats, space-bar cursor drags and shift slides.
final class KeyGridView: UIView {

    weak var delegate: KeyGridDelegate?
    private(set) var geometry: KeyboardGeometry?
    private(set) var keyMap: KeyMap?
    private var keyViews: [String: KeyView] = [:]
    private var theme: KeyboardTheme
    private let trail = SwipeTrailLayer()
    private let popup: KeyPopupView
    private let feedback: Feedback

    var shiftState: ShiftState = .off {
        didSet { keyViews.values.forEach { $0.shiftState = shiftState } }
    }
    var returnLabel: String? { didSet { keyViews["return"]?.returnLabel = returnLabel } }
    var isReturnAccented = false { didSet { keyViews["return"]?.isAccented = isReturnAccented } }

    // MARK: Touch state

    private final class TouchState {
        enum Mode { case pending, swiping, alternates, spaceCursor, backspaceHold, shiftSlide, globe, finished }
        var mode: Mode = .pending
        let startFrame: KeyFrame
        let startPoint: CGPoint
        let startTime: CFTimeInterval
        var currentFrame: KeyFrame
        var points: [CGPoint] = []
        var longPressTimer: Timer?
        var repeatTimer: Timer?
        var cursorAnchorX: CGFloat = 0
        var deleteCount = 0

        init(frame: KeyFrame, point: CGPoint) {
            startFrame = frame; currentFrame = frame; startPoint = point
            startTime = CACurrentMediaTime()
            points = [point]
        }

        func invalidate() {
            longPressTimer?.invalidate(); longPressTimer = nil
            repeatTimer?.invalidate(); repeatTimer = nil
        }
    }

    private var touches: [UITouch: TouchState] = [:]
    private var lastShiftTap: CFTimeInterval = 0
    private static let topRowDigits: [String: String] = [
        "q": "1", "w": "2", "e": "3", "r": "4", "t": "5", "z": "6", "u": "7", "i": "8", "o": "9", "p": "0",
    ]

    init(theme: KeyboardTheme, feedback: Feedback) {
        self.theme = theme
        self.feedback = feedback
        popup = KeyPopupView(theme: theme)
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        clipsToBounds = false
        backgroundColor = .clear
        layer.addSublayer(trail)
        trail.color = theme.accent
        popup.isHidden = true
        addSubview(popup)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Configuration

    func configure(layout: KeyboardLayout, metrics: KeyboardGeometry.Metrics) {
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        let geometry = KeyboardGeometry(layout: layout, size: size, metrics: metrics)
        let changedLayout = self.geometry?.layout != layout
        self.geometry = geometry
        keyMap = layout.layer == .letters ? KeyMap(geometry: geometry) : nil

        if changedLayout {
            keyViews.values.forEach { $0.removeFromSuperview() }
            keyViews = [:]
            for kf in geometry.keyFrames {
                let v = KeyView(key: kf.key, theme: theme)
                v.shiftState = shiftState
                if kf.key.id == "return" { v.returnLabel = returnLabel; v.isAccented = isReturnAccented }
                insertSubview(v, belowSubview: popup)
                keyViews[kf.key.id] = v
            }
            bringSubviewToFront(popup)
        }
        for kf in geometry.keyFrames {
            let v = keyViews[kf.key.id]
            v?.frame = kf.frame
            v?.isCompact = geometry.rowHeight < 40
            v?.hint = (delegate?.longPressNumbersEnabled ?? true) && layout.layer == .letters ? Self.topRowDigits[kf.key.label] : nil
        }
        trail.frame = bounds
        popup.frame = bounds
        // Keep the trail above keys, popup on top.
        layer.insertSublayer(trail, below: popup.layer)
    }

    func apply(theme: KeyboardTheme) {
        self.theme = theme
        trail.color = theme.accent
        popup.apply(theme: theme)
        keyViews.values.forEach { $0.apply(theme: theme) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        trail.frame = bounds
        popup.frame = bounds
    }

    /// Cancels everything in flight (e.g. when the layout switches under the finger).
    func cancelAllTouches() {
        for (_, state) in touches {
            state.invalidate()
            state.mode = .finished
            keyViews[state.currentFrame.key.id]?.setPressed(false)
        }
        touches.removeAll()
        popup.hide()
        trail.end()
    }

    // MARK: Touch handling

    override func touchesBegan(_ newTouches: Set<UITouch>, with event: UIEvent?) {
        guard let geometry else { return }
        // A second finger while a key is pending commits that key (fast typing with both thumbs);
        // an open alternates popup commits its selection so the shared popup is free again.
        for (touch, state) in touches where state.mode == .pending || state.mode == .shiftSlide || state.mode == .alternates {
            finish(touch: touch, state: state, at: state.points.last ?? state.startPoint)
        }
        if touches.values.contains(where: { $0.mode == .swiping }) { return }

        for touch in newTouches {
            let p = touch.location(in: self)
            guard let kf = geometry.keyFrame(at: p) else { continue }
            if kf.key.action == .globe {
                // The system owns globe behaviour (tap = next keyboard, hold = list); forward raw events.
                keyViews[kf.key.id]?.setPressed(true)
                let state = TouchState(frame: kf, point: p)
                state.mode = .globe
                touches[touch] = state
                delegate?.keyGrid(self, globeTouchEvent: event)
                continue
            }
            let state = TouchState(frame: kf, point: p)
            touches[touch] = state
            keyViews[kf.key.id]?.setPressed(true)

            switch kf.key.action {
            case .backspace:
                feedback.deleteTap()
                delegate?.keyGrid(self, didTap: kf.key)
                state.mode = .backspaceHold
                state.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self, weak state] _ in
                    guard let self, let state else { return }
                    self.startBackspaceRepeat(state)
                }
            case .shift:
                state.mode = .shiftSlide
                feedback.functionTap()
            case .character, .space:
                if kf.key.isLetter || kf.key.action == .space || !kf.key.isFunction {
                    if kf.key.action != .space {
                        feedback.keyTap()
                        if delegate?.keyPreviewEnabled ?? true, kf.key.isLetter || (!kf.key.isFunction && kf.key.character != nil) {
                            popup.showPreview(text: displayText(for: kf.key), keyFrame: kf.frame, in: bounds)
                        }
                    } else {
                        feedback.keyTap()
                    }
                }
                scheduleLongPress(for: state)
            default:
                feedback.functionTap()
                scheduleLongPress(for: state)
            }
        }
    }

    override func touchesMoved(_ moved: Set<UITouch>, with event: UIEvent?) {
        guard let geometry else { return }
        for touch in moved {
            guard let state = touches[touch] else { continue }
            let p = touch.location(in: self)
            state.points.append(p)
            let dx = p.x - state.startPoint.x, dy = p.y - state.startPoint.y
            let dist = hypot(dx, dy)

            switch state.mode {
            case .pending:
                let key = state.startFrame.key
                let threshold = max(10, geometry.unitWidth * 0.3)
                if key.action == .space {
                    if abs(dx) > 14 && abs(dx) > abs(dy) {
                        state.mode = .spaceCursor
                        state.cursorAnchorX = p.x
                        state.invalidate()
                        feedback.selectionTick()
                    }
                } else if key.isLetter, (delegate?.swipeTypingEnabled ?? true), dist > threshold {
                    state.mode = .swiping
                    state.invalidate()
                    popup.hide()
                    keyViews[state.currentFrame.key.id]?.setPressed(false)
                    if delegate?.swipeTrailEnabled ?? true {
                        trail.begin(at: state.startPoint)
                        state.points.forEach { trail.add(point: $0) }
                    }
                } else if dist > threshold {
                    // Slide to a neighbouring key (system behaviour): the key under the finger wins.
                    if let kf = geometry.keyFrame(at: p), kf.key.id != state.currentFrame.key.id {
                        keyViews[state.currentFrame.key.id]?.setPressed(false)
                        state.currentFrame = kf
                        keyViews[kf.key.id]?.setPressed(true)
                        state.invalidate()
                        if delegate?.keyPreviewEnabled ?? true, kf.key.isLetter {
                            popup.showPreview(text: displayText(for: kf.key), keyFrame: kf.frame, in: bounds)
                        } else {
                            popup.hide()
                        }
                    }
                }
            case .swiping:
                if delegate?.swipeTrailEnabled ?? true { trail.add(point: p) }
            case .alternates:
                if popup.select(at: p) { feedback.selectionTick() }
            case .spaceCursor:
                let step = max(12, geometry.unitWidth * 0.5)
                let delta = p.x - state.cursorAnchorX
                if abs(delta) >= step {
                    let steps = Int(delta / step)
                    delegate?.keyGrid(self, moveCursorBy: steps)
                    state.cursorAnchorX += CGFloat(steps) * step
                    feedback.selectionTick()
                }
            case .shiftSlide:
                // Same drift tolerance as taps, otherwise an edge tap on shift "slides" to y.
                if dist > max(10, geometry.unitWidth * 0.3), let kf = geometry.keyFrame(at: p), kf.key.id != state.currentFrame.key.id {
                    keyViews[state.currentFrame.key.id]?.setPressed(false)
                    state.currentFrame = kf
                    keyViews[kf.key.id]?.setPressed(true)
                }
            case .globe:
                delegate?.keyGrid(self, globeTouchEvent: event)
            case .backspaceHold, .finished:
                break
            }
        }
    }

    override func touchesEnded(_ ended: Set<UITouch>, with event: UIEvent?) {
        for touch in ended {
            guard let state = touches[touch] else { continue }
            if state.mode == .globe { delegate?.keyGrid(self, globeTouchEvent: event) }
            finish(touch: touch, state: state, at: touch.location(in: self))
        }
    }

    override func touchesCancelled(_ cancelled: Set<UITouch>, with event: UIEvent?) {
        for touch in cancelled {
            guard let state = touches[touch] else { continue }
            if state.mode == .globe { delegate?.keyGrid(self, globeTouchEvent: event) }
            state.invalidate()
            state.mode = .finished
            keyViews[state.currentFrame.key.id]?.setPressed(false)
            touches[touch] = nil
        }
        popup.hide()
        trail.end()
    }

    // MARK: Gesture completion

    private func finish(touch: UITouch, state: TouchState, at point: CGPoint) {
        guard state.mode != .finished else { return }
        state.invalidate()
        keyViews[state.currentFrame.key.id]?.setPressed(false)
        keyViews[state.startFrame.key.id]?.setPressed(false)
        let mode = state.mode
        state.mode = .finished
        touches[touch] = nil
        // Any other key ends the shift double-tap window (shift, H, shift must not lock caps).
        if state.currentFrame.key.action != .shift { lastShiftTap = 0 }

        switch mode {
        case .pending:
            popup.hide()
            let key = state.currentFrame.key
            if key.action == .shift {
                handleShiftTap()
            } else {
                delegate?.keyGrid(self, didTap: key)
            }
        case .swiping:
            trail.end()
            var path = state.points
            path.append(point)
            if let keyMap {
                delegate?.keyGrid(self, didSwipe: path, keyMap: keyMap)
                feedback.swipeCommit()
            }
        case .alternates:
            if let option = popup.selectedOption {
                delegate?.keyGrid(self, didInsertAlternate: option, for: state.startFrame.key)
                feedback.keyTap()
            }
            popup.hide()
        case .spaceCursor:
            // Movement can arrive with the lift itself; don't lose it.
            if let geometry {
                let step = max(12, geometry.unitWidth * 0.5)
                let steps = Int((point.x - state.cursorAnchorX) / step)
                if steps != 0 { delegate?.keyGrid(self, moveCursorBy: steps) }
            }
        case .backspaceHold, .globe:
            break
        case .shiftSlide:
            let key = state.currentFrame.key
            if key.action == .shift {
                handleShiftTap()
            } else if key.isLetter {
                delegate?.keyGrid(self, didShiftSlideTo: key)
            } else {
                delegate?.keyGrid(self, didTap: key)
            }
        case .finished:
            break
        }
    }

    private func handleShiftTap() {
        let now = CACurrentMediaTime()
        if now - lastShiftTap < 0.35 {
            lastShiftTap = 0
            delegate?.keyGridDidDoubleTapShift(self)
        } else {
            lastShiftTap = now
            delegate?.keyGrid(self, didTap: GermanLayouts.shift)
        }
    }

    private func scheduleLongPress(for state: TouchState) {
        state.longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.42, repeats: false) { [weak self, weak state] _ in
            guard let self, let state, state.mode == .pending else { return }
            self.beginLongPress(state)
        }
    }

    private func beginLongPress(_ state: TouchState) {
        let kf = state.currentFrame
        var options: [String] = []
        let shifted = shiftState.isActive && kf.key.isLetter
        if kf.key.isLetter, delegate?.longPressNumbersEnabled ?? true, let digit = Self.topRowDigits[kf.key.label] {
            options.append(digit)
        }
        if let c = kf.key.character, kf.key.isLetter || !kf.key.alternates.isEmpty {
            let base = shifted ? String(c).uppercased() : String(c)
            if options.isEmpty { options.append(base) } else { options.append(base) }
        }
        options.append(contentsOf: kf.key.alternates.map { shifted ? $0.uppercased() : $0 })
        var seen = Set<String>()
        options = options.filter { seen.insert($0).inserted }

        if options.count <= 1 {
            delegate?.keyGrid(self, didLongPress: kf.key)
            if kf.key.action == .space {
                // Holding space arms cursor movement; the following drag moves the caret.
                state.mode = .spaceCursor
                state.cursorAnchorX = state.points.last?.x ?? state.startPoint.x
                feedback.selectionTick()
            }
            return
        }
        state.mode = .alternates
        let preferLeft = kf.frame.midX > bounds.midX
        popup.showAlternates(options, keyFrame: kf.frame, in: bounds, preferLeft: preferLeft)
        feedback.selectionTick()
    }

    private func startBackspaceRepeat(_ state: TouchState) {
        state.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.09, repeats: true) { [weak self, weak state] timer in
            guard let self, let state, state.mode == .backspaceHold else { timer.invalidate(); return }
            state.deleteCount += 1
            let wordwise = state.deleteCount > 18
            if wordwise && state.deleteCount % 2 == 1 { return }   // slow down once deleting whole words
            self.delegate?.keyGridBackspaceRepeat(self, wordwise: wordwise)
            self.feedback.deleteTap()
        }
    }

    private func displayText(for key: Key) -> String {
        guard let c = key.character else { return key.label }
        return shiftState.isActive && key.isLetter ? String(c).uppercased() : String(c)
    }
}
