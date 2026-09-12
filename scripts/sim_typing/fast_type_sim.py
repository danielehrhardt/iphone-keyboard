#!/usr/bin/env python3
"""Types a sentence on the keyboard running in the iOS Simulator with real HID clicks.

Reproduces fast typing (7–30 taps/s) with the finger landing anywhere on the cap and drifting a
little while down – the things XCUITest cannot do. Verified 2026-09: 157/157 keys at 7–26 taps/s.

Setup (once):
  swiftc -O scripts/sim_typing/simtap.swift -o /tmp/simtap
  In Simulator: Window ▸ Show Device Bezels off (the window then is title bar + screen).
  Key centres in device points: keys-<device>.txt ("id x y" per line). FastTypingUITests prints
  them as FAST-KEY lines for the demo keyboard; the layout is the same for the extension.
  Open the Ausprobieren tab and focus the text view (or any app with the Umlaut keyboard up).

Usage:
  fast_type_sim.py "<text>" [--keys FILE] [--hold 40-90] [--gap 30-80] [--jitter 12,18] [--drift 4] [--seed 1]
  Then read the text view (screenshot: xcrun simctl io booted screenshot out.png) and, in a debug
  build, the tap trace: log stream --level debug --predicate 'subsystem == "de.codext.umlaut.keyboard"'.
"""
import argparse, os, random, subprocess, sys

DEVICE_POINTS = {"iphone17pro": (402, 874)}
TITLE_BAR = 50.0   # Simulator window title area above the screen (Xcode 26)

ap = argparse.ArgumentParser()
ap.add_argument("text")
ap.add_argument("--keys", default=os.path.join(os.path.dirname(__file__), "keys-iphone17pro.txt"))
ap.add_argument("--device", default="iphone17pro")
ap.add_argument("--hold", default="40-90")
ap.add_argument("--gap", default="30-80")
ap.add_argument("--jitter", default="12,18")
ap.add_argument("--drift", type=float, default=4)
ap.add_argument("--seed", type=int, default=1)
ap.add_argument("--simtap", default="/tmp/simtap")
a = ap.parse_args()

wx, wy, ww, wh = map(float, subprocess.check_output([a.simtap, "window"]).split())
dev_w, dev_h = DEVICE_POINTS[a.device]
scale = ww / dev_w
def mac(x, y): return (wx + x * scale, wy + TITLE_BAR + y * scale)

keys = {}
for line in open(a.keys):
    k, x, y = line.split(); keys[k] = (float(x), float(y))
jx, jy = map(float, a.jitter.split(","))
random.seed(a.seed)
pts = []
for ch in a.text:
    k = "space" if ch == " " else ch
    if k not in keys: sys.exit(f"no key for {k!r}")
    x, y = keys[k]
    x += random.uniform(-jx, jx); y += random.uniform(-jy, jy)
    mx, my = mac(x, y)
    dx, dy = random.uniform(-a.drift, a.drift) * scale, random.uniform(-a.drift, a.drift) * scale
    pts.append(f"{mx:.1f},{my:.1f},{dx:.1f},{dy:.1f}")
subprocess.run(["osascript", "-e", 'tell application "Simulator" to activate'], check=False)
subprocess.run([a.simtap, "tap", a.hold, a.gap] + pts, check=True)
