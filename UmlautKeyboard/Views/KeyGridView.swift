import UIKit
import KeyboardCore

protocol KeyGridDelegate: AnyObject {
    func keyGrid(_ grid: KeyGridView, didTap key: Key)
    /// A plain tap that stayed on one key, with the point where the finger landed (grid
    /// coordinates) so the tap map can learn from it. Defaults to `keyGrid(_:didTap:)`.
    func keyGrid(_ grid: KeyGridView, didTap key: Key, at point: CGPoint)
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

extension KeyGridDelegate {
    func keyGrid(_ grid: KeyGridView, didTap key: Key, at point: CGPoint) { keyGrid(grid, didTap: key) }
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
    /// Likely next letters get a larger touch area (see `KeyboardGeometry.keyFrame(at:prior:)`).
    var letterPrior: LetterPrior?
    /// Learned centre shifts of the letter keys (see `TapMap`); nil = geometric centres.
    var tapOffsets: TapMap.Offsets?
    var returnLabel: String? { didSet { if returnLabel != oldValue { keyViews["return"]?.returnLabel = returnLabel } } }
    var isReturnAccented = false { didSet { if isReturnAccented != oldValue { keyViews["return"]?.isAccented = isReturnAccented } } }

    /// How long a finger rests on a key before its hold action / alternates bubble.
    static let longPressDelay: TimeInterval = 0.42

    // MARK: Movement thresholds

    /// Drift a finger may have before a tap follows it to a neighbouring key (system behaviour:
    /// the key under the finger wins). Fast typing lands and lifts within this.
    private func slideThreshold(_ geometry: KeyboardGeometry) -> CGFloat { max(10, geometry.unitWidth * 0.3) }

    /// Travel before a touch on a letter becomes a glide. Most of a key width: a quick, slightly
    /// sloppy tap stays a tap (the key under the finger is typed), and only a path the decoder
    /// can actually read starts the trail. Below this the decoder would reject the path anyway.
    private func glideThreshold(_ geometry: KeyboardGeometry) -> CGFloat { max(20, geometry.unitWidth * 0.75) }

    // MARK: Touch state

    private final class TouchState {
        /// `held`: the key's `longPressAction` fired; the lift does nothing more.
        enum Mode { case pending, swiping, alternates, spaceCursor, backspaceHold, shiftSlide, globe, held, finished }
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
    private(set) var isTrackpadMode = false
    /// Digit reached by holding a top-row letter, by key label: q → 1 … p → 0 on every layout
    /// (the sixth key is z on QWERTZ and y on QWERTY).
    private var topRowDigits: [String: String] = [:]

    private static func topRowDigits(for layout: KeyboardLayout) -> [String: String] {
        guard layout.layer == .letters, let row = layout.rows.first else { return [:] }
        let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
        var map: [String: String] = [:]
        for (key, digit) in zip(row.keys.filter(\.isLetter), digits) { map[key.label] = digit }
        return map
    }

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
        topRowDigits = Self.topRowDigits(for: layout)

        if changedLayout {
            keyViews.values.forEach { $0.removeFromSuperview() }
            keyViews = [:]
            for kf in geometry.keyFrames {
                let v = KeyView(key: kf.key, theme: theme)
                v.shiftState = shiftState
                if isTrackpadMode, kf.key.id != "space" { v.setContentHidden(true, animated: false) }
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
            v?.hint = (delegate?.longPressNumbersEnabled ?? true) && layout.layer == .letters ? topRowDigits[kf.key.label] : nil
        }
        trail.frame = bounds
        layoutPopup()
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
        layoutPopup()
    }

    /// Key caps and the preview/alternates bubble are presentation only. Every touch inside the
    /// grid is resolved by `KeyboardGeometry`, never by a subview, so the bubble popping up over
    /// a neighbouring key can never intercept the next tap.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha >= 0.01, self.point(inside: point, with: event) else { return nil }
        return self
    }

    /// The popup covers the grid; only touch its frame when the size changed, and never while it
    /// is mid-animation with a transform (frame is undefined then).
    private func layoutPopup() {
        guard popup.bounds.size != bounds.size else { return }
        popup.transform = .identity
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
        setTrackpadMode(false)
    }

    /// While the space bar drives the cursor the caps go blank, so it reads as a trackpad.
    private func setTrackpadMode(_ on: Bool) {
        guard on != isTrackpadMode else { return }
        isTrackpadMode = on
        for (id, v) in keyViews where id != "space" {
            v.setContentHidden(on, animated: true)
        }
    }

    // MARK: Touch handling

    override func touchesBegan(_ newTouches: Set<UITouch>, with event: UIEvent?) {
        guard let geometry else { return }
        // A second finger while a key is pending commits that key (fast typing with both thumbs);
        // an open alternates popup commits its selection so the shared popup is free again.
        for (touch, state) in touches where state.mode == .pending || state.mode == .shiftSlide || state.mode == .alternates {
            finish(touch: touch, state: state, at: state.points.last ?? state.startPoint)
        }
        // A glide in flight never blocks the other thumb: its tap is tracked alongside and
        // commits on its own lift. Every touch that lands on the grid becomes a key event.

        for touch in newTouches {
            let p = touch.location(in: self)
            guard let kf = geometry.keyFrame(at: p, prior: letterPrior, offsets: tapOffsets) else { continue }
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
                if key.action == .space {
                    if abs(dx) > 14 && abs(dx) > abs(dy) {
                        state.mode = .spaceCursor
                        state.cursorAnchorX = p.x
                        state.invalidate()
                        setTrackpadMode(true)
                        feedback.selectionTick()
                    }
                } else if key.isLetter, (delegate?.swipeTypingEnabled ?? true), dist > glideThreshold(geometry) {
                    state.mode = .swiping
                    state.invalidate()
                    popup.hide()
                    keyViews[state.currentFrame.key.id]?.setPressed(false)
                    if delegate?.swipeTrailEnabled ?? true {
                        trail.begin(at: state.startPoint)
                        state.points.forEach { trail.add(point: $0) }
                    }
                } else if dist > slideThreshold(geometry) {
                    // Slide to a neighbouring key (system behaviour): the key under the finger wins.
                    // Resolved like the landing itself, so a wobble on a key the prior awarded
                    // does not hand the tap to the geometric neighbour.
                    if let kf = geometry.keyFrame(at: p, prior: letterPrior, offsets: tapOffsets), kf.key.id != state.currentFrame.key.id {
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
                if dist > slideThreshold(geometry), let kf = geometry.keyFrame(at: p), kf.key.id != state.currentFrame.key.id {
                    keyViews[state.currentFrame.key.id]?.setPressed(false)
                    state.currentFrame = kf
                    keyViews[kf.key.id]?.setPressed(true)
                }
            case .globe:
                delegate?.keyGrid(self, globeTouchEvent: event)
            case .backspaceHold, .held, .finished:
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
        setTrackpadMode(false)
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
            } else if state.currentFrame.key.id == state.startFrame.key.id {
                // The finger stayed on the key it landed on: the landing point tells the tap map
                // where this user aims. A slide to a neighbour is an eyes-on fix and teaches nothing.
                delegate?.keyGrid(self, didTap: key, at: state.startPoint)
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
            setTrackpadMode(false)
        case .backspaceHold, .globe, .held:
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
            delegate?.keyGrid(self, didTap: geometry?.layout.allKeys.first { $0.action == .shift } ?? GermanLayouts.shift)
        }
    }

    private func scheduleLongPress(for state: TouchState) {
        state.longPressTimer = Timer.scheduledTimer(withTimeInterval: Self.longPressDelay, repeats: false) { [weak self, weak state] _ in
            guard let self, let state, state.mode == .pending else { return }
            // Firing far too late means the run loop was stalled, and the lift that ends this
            // tap is most likely queued right behind: a quick tap must stay a quick tap and
            // never turn into a hold that swallows it or opens the bubble.
            if CACurrentMediaTime() - state.startTime > Self.longPressDelay + 0.3 { return }
            self.beginLongPress(state)
        }
    }

    private func beginLongPress(_ state: TouchState) {
        // A long press is slow and eyes-on: the key under the finger wins, not the one the
        // next-letter prior enlarged (digit hints and alternates must match what the user sees).
        if let geometry, let visual = geometry.keyFrame(at: state.points.last ?? state.startPoint), visual.key.id != state.currentFrame.key.id {
            keyViews[state.currentFrame.key.id]?.setPressed(false)
            state.currentFrame = visual
            keyViews[visual.key.id]?.setPressed(true)
        }
        let kf = state.currentFrame
        if kf.key.longPressAction != nil {
            // The hold *is* the action (emoji on the comma key): fire it and swallow the tap.
            state.mode = .held
            popup.hide()
            feedback.selectionTick()
            delegate?.keyGrid(self, didLongPress: kf.key)
            return
        }
        var options: [String] = []
        let shifted = shiftState.isActive && kf.key.isLetter
        if kf.key.isLetter, delegate?.longPressNumbersEnabled ?? true, let digit = topRowDigits[kf.key.label] {
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
                setTrackpadMode(true)
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
