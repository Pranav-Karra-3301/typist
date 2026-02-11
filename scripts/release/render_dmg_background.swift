import AppKit
import Foundation

let arguments = CommandLine.arguments

guard arguments.count >= 8 else {
    fputs("usage: render_dmg_background.swift <output-path> <width> <height> <app-x> <app-y> <applications-x> <applications-y>\n", stderr)
    exit(1)
}

let outputPath = arguments[1]
let width = CGFloat(Int(arguments[2]) ?? 560)
let height = CGFloat(Int(arguments[3]) ?? 360)
let appX = CGFloat(Int(arguments[4]) ?? 150)
let appY = CGFloat(Int(arguments[5]) ?? 170)
let applicationsX = CGFloat(Int(arguments[6]) ?? 410)
let applicationsY = CGFloat(Int(arguments[7]) ?? 170)

let imageSize = NSSize(width: width, height: height)
let image = NSImage(size: imageSize)

image.lockFocus()

NSColor.white.setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: imageSize)).fill()

let headingAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 30, weight: .semibold),
    .foregroundColor: NSColor(calibratedWhite: 0.08, alpha: 1)
]
let heading = "Drag Typist to Applications"
let headingSize = heading.size(withAttributes: headingAttributes)
heading.draw(
    at: NSPoint(x: (width - headingSize.width) / 2, y: height - 76),
    withAttributes: headingAttributes
)

let subheadingAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 15, weight: .medium),
    .foregroundColor: NSColor(calibratedWhite: 0.42, alpha: 1)
]
let subheading = "Then open it from Applications."
let subheadingSize = subheading.size(withAttributes: subheadingAttributes)
subheading.draw(
    at: NSPoint(x: (width - subheadingSize.width) / 2, y: height - 104),
    withAttributes: subheadingAttributes
)

let quoteAttributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .regular),
    .foregroundColor: NSColor(calibratedWhite: 0.50, alpha: 1)
]
let quote = "“Simple can be harder than complex.” — Steve Jobs"
let quoteSize = quote.size(withAttributes: quoteAttributes)
quote.draw(
    at: NSPoint(x: (width - quoteSize.width) / 2, y: 42),
    withAttributes: quoteAttributes
)

image.unlockFocus()

guard
    let tiffData = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to render DMG background image\n", stderr)
    exit(1)
}

let outputURL = URL(fileURLWithPath: outputPath)
try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL)
