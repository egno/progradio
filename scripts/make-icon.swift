// Renders the app icon (Prog Radio's logo from progradio.com, redrawn as vectors) into App/Assets.xcassets/AppIcon.appiconset.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

func draw(in ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    // macOS icon grid: an 824 pt rounded square centred on the 1024 canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // Drop shadow under the tile.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(shape)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    // White tile with a barely-there vertical shade, like the logo on progradio.com.
    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    let background = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF), color(0xEEF0F3)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(background, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    // Prog Radio's logo: a blue dot between two pairs of arcs, cut radially at ±45°.
    // Proportions measured from the station's 1024 px artwork (outer radius 437.5).
    let center = CGPoint(x: 512, y: 512)
    let scale: CGFloat = 0.72
    let arcs: [(inner: CGFloat, outer: CGFloat)] = [(175.5, 257.5), (336.5, 437.5)]
    ctx.setFillColor(color(0x333333))
    for arc in arcs {
        for side in [0, CGFloat.pi] {
            let from = side - CGFloat.pi / 4, to = side + CGFloat.pi / 4
            let path = CGMutablePath()
            path.addArc(center: center, radius: arc.outer * scale, startAngle: from, endAngle: to, clockwise: false)
            path.addArc(center: center, radius: arc.inner * scale, startAngle: to, endAngle: from, clockwise: true)
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()
        }
    }
    let dot: CGFloat = 85 * scale
    ctx.setFillColor(color(0x0099FF))
    ctx.fillEllipse(in: CGRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2))
    ctx.restoreGState()

    // Hairline edge so the white tile doesn't melt into light backgrounds.
    ctx.addPath(shape)
    ctx.setStrokeColor(color(0x000000, 0.08))
    ctx.setLineWidth(2)
    ctx.strokePath()
}

func render(_ pixels: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
    draw(in: ctx)
    return ctx.makeImage()!
}

func write(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    precondition(CGImageDestinationFinalize(dest), "couldn't write \(url.path)")
}

let dir = URL(fileURLWithPath: "App/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        write(render(points * scale), to: dir.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: dir.appendingPathComponent("Contents.json"))
try #"{"info":{"author":"xcode","version":1}}"#.write(
    to: dir.deletingLastPathComponent().appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote \(images.count) icons to \(dir.path)")
