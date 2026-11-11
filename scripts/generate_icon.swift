// Draws the QuickShot app icon as vectors and writes every size the asset catalog needs,
// including the 1024 px image the App Store requires.
//
//   xcrun swift scripts/generate_icon.swift QuickShot/Assets.xcassets/AppIcon.appiconset

import AppKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: generate_icon.swift <AppIcon.appiconset>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

func bitmap(_ pixels: Int) -> NSBitmapImageRep {
    NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                     bytesPerRow: 0, bitsPerPixel: 0)!
}

func draw(into rep: NSBitmapImageRep, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    body()
    NSGraphicsContext.current?.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
}

// The standard macOS icon grid: an 824 pt rounded square centred in a 1024 pt canvas,
// with a transparent surround and a soft shadow.
let master = bitmap(1024)
draw(into: master) {
    let body = NSRect(x: 100, y: 100, width: 824, height: 824)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185.4, yRadius: 185.4)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(srgbRed: 0.52, green: 0.74, blue: 0.97, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [
        NSColor(srgbRed: 153 / 255, green: 228 / 255, blue: 252 / 255, alpha: 1),
        NSColor(srgbRed: 134 / 255, green: 189 / 255, blue: 247 / 255, alpha: 1),
        NSColor(srgbRed: 111 / 255, green: 146 / 255, blue: 247 / 255, alpha: 1)
    ])?.draw(in: shape, angle: -90)

    // Proportions measured from the original artwork, as fractions of the body.
    let stroke = body.width * 0.041
    let inset = body.width * 0.216
    let arm = body.width * 0.145
    let corner = body.width * 0.045
    NSColor.white.setStroke()

    // One viewfinder bracket per corner. `sx` and `sy` point into the body.
    for (cornerPoint, sx, sy) in [
        (CGPoint(x: body.minX + inset, y: body.maxY - inset), CGFloat(1), CGFloat(-1)),
        (CGPoint(x: body.maxX - inset, y: body.maxY - inset), CGFloat(-1), CGFloat(-1)),
        (CGPoint(x: body.minX + inset, y: body.minY + inset), CGFloat(1), CGFloat(1)),
        (CGPoint(x: body.maxX - inset, y: body.minY + inset), CGFloat(-1), CGFloat(1))
    ] {
        let bracket = NSBezierPath()
        bracket.move(to: CGPoint(x: cornerPoint.x + sx * arm, y: cornerPoint.y))
        bracket.appendArc(from: cornerPoint, to: CGPoint(x: cornerPoint.x, y: cornerPoint.y + sy * arm), radius: corner)
        bracket.line(to: CGPoint(x: cornerPoint.x, y: cornerPoint.y + sy * arm))
        bracket.lineWidth = stroke
        bracket.lineCapStyle = .round
        bracket.lineJoinStyle = .round
        bracket.stroke()
    }

    let radius = body.width * 0.0618
    let ring = NSBezierPath(ovalIn: NSRect(x: body.midX - radius, y: body.midY - radius, width: radius * 2, height: radius * 2))
    ring.lineWidth = stroke
    ring.stroke()
}

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32), ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256), ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512), ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for (name, pixels) in sizes {
    let rep = pixels == 1024 ? master : bitmap(pixels)
    if pixels != 1024 {
        draw(into: rep) {
            master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero,
                        operation: .copy, fraction: 1, respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
        }
    }
    rep.size = NSSize(width: pixels, height: pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("Could not encode \(name)\n".utf8))
        exit(1)
    }
    try png.write(to: output.appendingPathComponent(name), options: .atomic)
    print("\(name): \(pixels) × \(pixels)")
}
