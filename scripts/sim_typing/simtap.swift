// HID-level tap injection for the iOS Simulator, to type on the keyboard far faster than XCUITest can
// (XCUITest manages ~2.5 taps/s; this reaches 25+). Needs Accessibility permission for the terminal.
//
//   swiftc -O simtap.swift -o simtap
//   ./simtap window                                   # prints "x y width height" of the Simulator window
//   ./simtap tap <hold_ms|min-max> <gap_ms|min-max> x,y[,dx,dy] ...   # screen points; dx,dy = drift while down
//
// Coordinates are macOS screen points (negative on secondary displays). See fast_type_sim.py.
import CoreGraphics
import Foundation

func range(_ s: String) -> ClosedRange<Double> {
    let p = s.split(separator: "-").map { Double($0)! }
    return p.count == 2 ? p[0]...p[1] : p[0]...p[0]
}

let args = CommandLine.arguments
switch args.count > 1 ? args[1] : "" {
case "window":
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
    for w in list where (w[kCGWindowOwnerName as String] as? String) == "Simulator" && (w[kCGWindowLayer as String] as? Int) == 0 {
        let b = w[kCGWindowBounds as String] as! [String: CGFloat]
        print(b["X"]!, b["Y"]!, b["Width"]!, b["Height"]!)
        break
    }
case "tap":
    let hold = range(args[2]), gap = range(args[3])
    let src = CGEventSource(stateID: .hidSystemState)
    func post(_ type: CGEventType, _ p: CGPoint) {
        CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    let start = Date()
    for arg in args.dropFirst(4) {
        let c = arg.split(separator: ",").map { Double($0)! }
        let p = CGPoint(x: c[0], y: c[1])
        let q = c.count == 4 ? CGPoint(x: c[0] + c[2], y: c[1] + c[3]) : p
        let h = Double.random(in: hold), g = Double.random(in: gap)
        post(.mouseMoved, p); usleep(2000)
        post(.leftMouseDown, p)
        if q != p {
            usleep(UInt32(h * 500))
            post(.leftMouseDragged, CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)); usleep(4000)
            post(.leftMouseDragged, q)
            usleep(UInt32(h * 500))
        } else {
            usleep(UInt32(h * 1000))
        }
        post(.leftMouseUp, q)
        usleep(UInt32(g * 1000))
    }
    let n = args.count - 4
    let dt = Date().timeIntervalSince(start)
    print(String(format: "%d taps in %.2fs = %.1f taps/s", n, dt, Double(n) / dt))
default:
    print("usage: simtap window | simtap tap <hold> <gap> x,y[,dx,dy] ...")
    exit(2)
}
