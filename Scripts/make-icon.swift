// Draws the launcher's icon.
//
// The icon is drawn, not painted: the master picture is generated from the code, so it stays
// sharp at every size (every size is rendered on its own, not scaled down) and it can be changed
// by changing the code.
//
// The script writes the pictures of an .iconset folder; Scripts/make-icon.sh turns that folder
// into the AppIcon.icns the app bundle uses.
//
//   swift Scripts/make-icon.swift <output.iconset>
import AppKit
import Foundation

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

/// The same picture, painted in one colour: the symbol is drawn first, then the colour is poured
/// over it (sourceAtop keeps the shape).
func tinted(_ image: CGImage, _ color: CGColor) -> CGImage? {
    let w = image.width, h = image.height
    guard let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    c.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    c.setBlendMode(.sourceAtop)
    c.setFillColor(color)
    c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return c.makeImage()
}

/// The icon, drawn at the size it is asked for: a full-bleed blue tile with the game's
/// controller on it.
///
/// The picture has to fill the whole canvas, with no transparent pixels: on macOS 26 and later a
/// legacy .icns whose 1024 picture does not reach the edges is drawn smaller, on a grey
/// placeholder board (the system thinks it is a document, not an icon). A full-bleed picture is
/// taken as it is.
func renderIcon(pixels: CGFloat) -> CGImage? {
    let size = pixels
    guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    // the ground: a blue gradient, lighter at the top left
    let body = CGRect(x: 0, y: 0, width: size, height: size)
    let colors = [NSColor(srgbRed: 0.32, green: 0.66, blue: 1.00, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.11, green: 0.42, blue: 0.97, alpha: 1).cgColor,
                  NSColor(srgbRed: 0.34, green: 0.18, blue: 0.74, alpha: 1).cgColor] as CFArray
    if let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                             colors: colors, locations: [0.0, 0.52, 1.0]) {
        ctx.drawLinearGradient(grad,
                               start: CGPoint(x: body.minX, y: body.maxY),
                               end: CGPoint(x: body.maxX, y: body.minY),
                               options: [])
    }
    // a soft light from the top left, so the tile is not flat
    if let gloss = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [NSColor.white.withAlphaComponent(0.24).cgColor,
                                       NSColor.white.withAlphaComponent(0.0).cgColor] as CFArray,
                              locations: [0.0, 1.0]) {
        let c = CGPoint(x: body.midX - body.width * 0.24, y: body.maxY - body.height * 0.22)
        ctx.drawRadialGradient(gloss, startCenter: c, startRadius: 0, endCenter: c,
                               endRadius: body.width * 0.85, options: [])
    }
    // a shade at the bottom, for a little depth
    if let floor = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                              colors: [NSColor.black.withAlphaComponent(0.0).cgColor,
                                       NSColor.black.withAlphaComponent(0.16).cgColor] as CFArray,
                              locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(floor, start: CGPoint(x: body.midX, y: body.minY + body.height * 0.45),
                               end: CGPoint(x: body.midX, y: body.minY), options: [])
    }

    // the controller, in the middle
    if let symbol = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: nil) {
        let glyphSize = body.width * 0.46
        let cfg = NSImage.SymbolConfiguration(pointSize: glyphSize, weight: .regular)
        let glyph = symbol.withSymbolConfiguration(cfg) ?? symbol
        // Ask for the symbol at the size it will have on the icon: the template is rendered again
        // at that size, so the edges stay sharp (the default picture is 22x14 and turns to mush).
        var proposed = CGRect(x: 0, y: 0, width: glyphSize, height: glyphSize)
        if let raw = glyph.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
           let cg = tinted(raw, NSColor.white.cgColor) {
            let aspect = CGFloat(cg.width) / CGFloat(cg.height)
            let dw = glyphSize
            let dh = dw / aspect
            let rect = CGRect(x: body.midX - dw / 2, y: body.midY + body.height * 0.02 - dh / 2,
                              width: dw, height: dh)
            // its shadow, on the tile
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -glyphSize * 0.045), blur: glyphSize * 0.10,
                          color: NSColor.black.withAlphaComponent(0.28).cgColor)
            ctx.draw(cg, in: rect)
            ctx.restoreGState()
        }
    }

    return ctx.makeImage()
}

// the sizes an .iconset needs: the name is the size in points, the picture is the pixels
let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_48x48.png", 48),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

for (name, pixels) in sizes {
    // every size is drawn on its own: a small icon is not a big one that was made smaller
    guard let image = renderIcon(pixels: pixels) else {
        print("FAIL: cannot draw \(name)")
        exit(1)
    }
    let rep = NSBitmapImageRep(cgImage: image)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        print("FAIL: cannot encode \(name)")
        exit(1)
    }
    let path = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    try? png.write(to: path)
    print("  \(name)")
}
print("\(outDir): \(sizes.count) pictures")
