import AppKit
import CoreGraphics

// Chivvy app icon: a countdown ring shaped like a "C", with an alert dot in the gap.
// Drawn on the macOS 11+ grid: 1024 canvas, 824 squircle body, room around it for the shadow.
// Run: swift generate_icon.swift && iconutil -c icns AppIcon.iconset

let colorSpace = CGColorSpaceCreateDeviceRGB()

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [
        CGFloat(hex >> 16 & 0xFF) / 255, CGFloat(hex >> 8 & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, alpha,
    ])!
}

func drawIcon(in ctx: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Body with drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(squircle)
    ctx.setFillColor(color(0x0E1016))
    ctx.fillPath()
    ctx.restoreGState()

    // Graphite gradient with a soft sheen at the top
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()
    let fill = CGGradient(colorsSpace: colorSpace, colors: [color(0x2B2F3A), color(0x0E1016)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(fill, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    let sheen = CGGradient(colorsSpace: colorSpace, colors: [color(0xFFFFFF, 0.10), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 560), options: [])
    ctx.restoreGState()

    // Hairline edge
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 184, cornerHeight: 184, transform: nil))
    ctx.setStrokeColor(color(0xFFFFFF, 0.08))
    ctx.setLineWidth(3)
    ctx.strokePath()

    let center = CGPoint(x: 512, y: 512)
    let radius: CGFloat = 250
    ctx.setLineCap(.round)
    ctx.setLineWidth(84)

    // Faint full track
    ctx.setStrokeColor(color(0xFFFFFF, 0.08))
    ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
    ctx.strokePath()

    // The "C": ring from 45° round to 315°, leaving the gap on the right
    ctx.saveGState()
    ctx.addArc(center: center, radius: radius, startAngle: .pi * 0.25, endAngle: .pi * 1.75, clockwise: false)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let ring = CGGradient(colorsSpace: colorSpace, colors: [color(0xFFFFFF), color(0xC9D2E3)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(ring, start: CGPoint(x: 512, y: 800), end: CGPoint(x: 512, y: 220), options: [])
    ctx.restoreGState()

    // Alert dot centred in the gap, with a glow
    let dot = CGPoint(x: center.x + radius, y: center.y)
    let dotRadius: CGFloat = 60
    ctx.saveGState()
    ctx.setShadow(offset: .zero, blur: 60, color: color(0xFF8A1F, 0.9))
    ctx.setFillColor(color(0xFF8A1F))
    ctx.fillEllipse(in: CGRect(x: dot.x - dotRadius, y: dot.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
    ctx.restoreGState()
}

func savePNG(to path: String, size: Int) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let ctx = context.cgContext
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    drawIcon(in: ctx)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let iconsetPath = "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for (name, px) in sizes {
    savePNG(to: "\(iconsetPath)/\(name).png", size: px)
    print("Generated \(name).png (\(px)x\(px))")
}

print("Done! Now run: iconutil -c icns AppIcon.iconset")
