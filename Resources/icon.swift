// Draws the app icon: dark squircle, 270° gauge ring, mint progress, needle.
// Run through icon.sh, which turns the iconset into Resources/AppIcon.icns.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let design = 1024.0

func draw(_ size: Int, to url: URL) {
    let scale = Double(size) / design
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { exit(1) }

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: x * scale, y: Double(size) - y * scale)
    }
    func radius(_ value: Double) -> Double { value * scale }

    // Squircle body with a soft vertical gradient.
    let body = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
        cornerWidth: radius(230), cornerHeight: radius(230), transform: nil
    )
    ctx.addPath(body)
    ctx.clip()
    let colors = [
        CGColor(srgbRed: 0.15, green: 0.17, blue: 0.21, alpha: 1),
        CGColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 1),
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1]) {
        ctx.drawLinearGradient(
            gradient, start: point(0, 0), end: point(0, design), options: []
        )
    }

    let center = point(512, 560)
    let ring = radius(300)
    let width = radius(88)

    func arc(from: Double, to: Double, color: CGColor, clockwise: Bool) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.addArc(
            center: center, radius: ring,
            startAngle: from * .pi / 180, endAngle: to * .pi / 180, clockwise: clockwise
        )
        ctx.strokePath()
    }

    // One 270° ring, gap at the upper left: that gap is what reads as a gauge
    // instead of a letter at 16pt, so there is deliberately no second color.
    arc(from: 135, to: 405, color: CGColor(srgbRed: 0.31, green: 0.89, blue: 0.69, alpha: 1), clockwise: false)

    // Needle pointing up-right, out of a mint hub.
    ctx.setStrokeColor(CGColor(srgbRed: 0.91, green: 0.93, blue: 0.95, alpha: 1))
    ctx.setLineWidth(radius(26))
    ctx.setLineCap(.round)
    ctx.move(to: center)
    ctx.addLine(to: point(512 + 190, 560 - 190))
    ctx.strokePath()

    ctx.setFillColor(CGColor(srgbRed: 0.31, green: 0.89, blue: 0.69, alpha: 1))
    ctx.fillEllipse(
        in: CGRect(
            x: center.x - radius(36), y: center.y - radius(36),
            width: radius(72), height: radius(72)
        )
    )

    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(
              url as CFURL, UTType.png.identifier as CFString, 1, nil
          )
    else { exit(1) }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

guard CommandLine.arguments.count > 1 else {
    print("usage: icon.swift <iconset dir>")
    exit(1)
}
let dir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

for (name, size) in [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
] {
    draw(size, to: dir.appendingPathComponent("\(name).png"))
}
print("iconset written to \(dir.path)")
