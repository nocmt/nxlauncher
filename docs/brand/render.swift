#!/usr/bin/env swift
// Original NxLauncher artwork lives in the adjacent SVG files.
// Rebuild from any directory: swift /absolute/path/to/docs/brand/render.swift
// macOS only; AppKit + ImageIO, sips and iconutil are supplied with macOS.
import AppKit
import Foundation
import ImageIO

let brand = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let root = brand.deletingLastPathComponent().deletingLastPathComponent()
let resources = root.appendingPathComponent("Resources", isDirectory: true)
let fm = FileManager.default

enum BuildError: Error { case failed(String) }
func run(_ command: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: command)
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw BuildError.failed(command) }
}
func render(_ source: URL, _ output: URL, width: Int, height: Int) throws {
    let svg = try String(contentsOf: source, encoding: .utf8)
    guard let image = NSImage(data: Data(svg.utf8)),
          let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width,
            pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { throw BuildError.failed("Cannot load SVG or allocate bitmap: \(source.path)") }
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
               from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw BuildError.failed("Cannot encode PNG")
    }
    try data.write(to: output, options: .atomic)
}

let work = fm.temporaryDirectory.appendingPathComponent("nxlauncher-brand-\(UUID().uuidString)", isDirectory: true)
try fm.createDirectory(at: work, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: work) }
let iconset = work.appendingPathComponent("AppIcon.iconset", isDirectory: true)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
let source = brand.appendingPathComponent("app-icon.svg")
try render(source, resources.appendingPathComponent("AppIcon.png"), width: 1024, height: 1024)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try render(source, iconset.appendingPathComponent(name), width: pixels, height: pixels)
    }
}
try run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path])
try render(brand.appendingPathComponent("hero.svg"), brand.appendingPathComponent("hero-preview.png"), width: 1600, height: 640)
// This montage is deliberately generated from real icon rasters, not scaled screenshots.
let sheetBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 960, pixelsHigh: 640,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: sheetBitmap)
NSColor(srgbRed: 0.94, green: 0.96, blue: 0.98, alpha: 1).setFill()
NSRect(x: 0, y: 320, width: 960, height: 320).fill()
NSColor(srgbRed: 0.055, green: 0.075, blue: 0.11, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 960, height: 320).fill()
for (x, size) in [(40,16), (136,32), (248,64), (392,128), (612,256)] {
    let raster = work.appendingPathComponent("preview-\(size).png")
    try render(source, raster, width: size, height: size)
    guard let icon = NSImage(contentsOf: raster) else { throw BuildError.failed("preview") }
    for y in [32, 352] {
        icon.draw(in: NSRect(x: x, y: y + (256-size)/2, width: size, height: size))
    }
    let label = "\(size) px" as NSString
    label.draw(at: NSPoint(x: x, y: 327), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.gray])
}
NSGraphicsContext.restoreGraphicsState()
guard let png = sheetBitmap.representation(using: .png, properties: [:]) else { throw BuildError.failed("contact sheet") }
try png.write(to: brand.appendingPathComponent("icon-sizes.png"), options: .atomic)
print("Built Resources/AppIcon.png (1024px), AppIcon.icns (10 representations), hero-preview.png, icon-sizes.png")
