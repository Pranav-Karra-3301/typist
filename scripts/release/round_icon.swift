import AppKit
import Foundation

let arguments = CommandLine.arguments

guard arguments.count >= 3 else {
    fputs("usage: round_icon.swift <input-path> <output-path> [corner-radius-ratio]\n", stderr)
    exit(1)
}

let inputPath = arguments[1]
let outputPath = arguments[2]
let radiusRatio = CGFloat(Double(arguments.dropFirst(3).first ?? "0.22") ?? 0.22)

let inputURL = URL(fileURLWithPath: inputPath)
let outputURL = URL(fileURLWithPath: outputPath)

guard let inputImage = NSImage(contentsOf: inputURL) else {
    fputs("failed to load icon from \(inputPath)\n", stderr)
    exit(1)
}

let outputSize = inputImage.size
guard outputSize.width > 0, outputSize.height > 0 else {
    fputs("icon has invalid size: \(outputSize.width)x\(outputSize.height)\n", stderr)
    exit(1)
}

let clampedRatio = min(max(radiusRatio, 0.0), 0.5)
let radius = min(outputSize.width, outputSize.height) * clampedRatio
let rect = NSRect(origin: .zero, size: outputSize)

let roundedImage = NSImage(size: outputSize)
roundedImage.lockFocus()

NSColor.clear.setFill()
rect.fill()

let clipPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
clipPath.addClip()
inputImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)

roundedImage.unlockFocus()

guard
    let tiffData = roundedImage.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiffData),
    let pngData = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to render rounded icon image\n", stderr)
    exit(1)
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)
try pngData.write(to: outputURL)
