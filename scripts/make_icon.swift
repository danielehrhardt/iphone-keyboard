#!/usr/bin/env swift
//
// Renders the 1024×1024 Umlaut app icon with CoreGraphics/CoreText – no external dependencies.
//
//   swift scripts/make_icon.swift [output.png]
//
// Default output: Umlaut/Assets.xcassets/AppIcon.appiconset/AppIcon.png
// The icon is drawn full-bleed and fully opaque (no alpha channel), as required for iOS app icons;
// iOS applies the rounded superellipse mask itself.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/Umlaut/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

guard let context = CGContext(data: nil,
                              width: side,
                              height: side,
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    FileHandle.standardError.write(Data("Konnte den Grafikkontext nicht erzeugen.\n".utf8))
    exit(1)
}

let s = CGFloat(side)

func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}

// MARK: Background – indigo → blue, top-left to bottom-right.

context.saveGState()
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: [srgb(0.290, 0.247, 0.780),
                                   srgb(0.345, 0.337, 0.839),
                                   srgb(0.075, 0.478, 1.000)] as CFArray,
                          locations: [0.0, 0.45, 1.0])!
context.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: s),
                           end: CGPoint(x: s, y: 0),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
context.restoreGState()

// Soft highlight in the upper left so the flat gradient gets some depth.
context.saveGState()
let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [srgb(1, 1, 1, 0.22), srgb(1, 1, 1, 0)] as CFArray,
                      locations: [0, 1])!
context.drawRadialGradient(glow,
                           startCenter: CGPoint(x: s * 0.28, y: s * 0.82), startRadius: 0,
                           endCenter: CGPoint(x: s * 0.28, y: s * 0.82), endRadius: s * 0.62,
                           options: [])
context.restoreGState()

// MARK: Swipe trail behind the glyph.

context.saveGState()
let trail = CGMutablePath()
trail.move(to: CGPoint(x: s * 0.13, y: s * 0.34))
trail.addCurve(to: CGPoint(x: s * 0.50, y: s * 0.24),
               control1: CGPoint(x: s * 0.24, y: s * 0.58),
               control2: CGPoint(x: s * 0.38, y: s * 0.12))
trail.addCurve(to: CGPoint(x: s * 0.88, y: s * 0.66),
               control1: CGPoint(x: s * 0.66, y: s * 0.38),
               control2: CGPoint(x: s * 0.72, y: s * 0.72))
context.setStrokeColor(srgb(1, 1, 1, 0.20))
context.setLineWidth(s * 0.055)
context.setLineCap(.round)
context.setLineJoin(.round)
context.addPath(trail)
context.strokePath()

// A brighter head on the trail, like a finger that just lifted off.
context.setFillColor(srgb(1, 1, 1, 0.42))
context.fillEllipse(in: CGRect(x: s * 0.88 - s * 0.035, y: s * 0.66 - s * 0.035,
                               width: s * 0.07, height: s * 0.07))
context.restoreGState()

// MARK: The „ü“.

let fontSize = s * 0.62
let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
let attributes: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): srgb(1, 1, 1),
]
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "ü", attributes: attributes))
let glyphBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)

context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -s * 0.012),
                  blur: s * 0.045,
                  color: srgb(0, 0, 0, 0.28))
context.textPosition = CGPoint(x: (s - glyphBounds.width) / 2 - glyphBounds.minX,
                               y: (s - glyphBounds.height) / 2 - glyphBounds.minY)
CTLineDraw(line, context)
context.restoreGState()

// MARK: Write the PNG.

guard let image = context.makeImage() else {
    FileHandle.standardError.write(Data("Konnte kein Bild erzeugen.\n".utf8))
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    FileHandle.standardError.write(Data("Konnte \(outputPath) nicht schreiben.\n".utf8))
    exit(1)
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("Konnte das PNG nicht finalisieren.\n".utf8))
    exit(1)
}

print("Icon geschrieben: \(outputPath) (\(side)×\(side))")
