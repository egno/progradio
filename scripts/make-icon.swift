// Renders the app icon from scripts/icon-source.png into App/Assets.xcassets/AppIcon.appiconset.
// Run from the repo root: swift scripts/make-icon.swift
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024

// scripts/icon-source.png: 1254 px artwork, a glowing tile on pure black.
// Measured edges of its bright border: x 108...1142, y 112...1140 (top-left origin).
let sourceTile = CGRect(x: 108, y: 112, width: 1034, height: 1028)

// The artwork with its black surround made transparent. Everything reachable from the corners
// without crossing the bright border is "outside"; its glow keeps its colour, with alpha from its brightness.
let artwork: CGImage = {
    let url = URL(fileURLWithPath: "scripts/icon-source.png")
    let source = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }!
    let w = source.width, h = source.height
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
    let px = ctx.data!.bindMemory(to: UInt8.self, capacity: w * h * 4)
    func brightness(_ i: Int) -> UInt8 { max(px[i * 4], px[i * 4 + 1], px[i * 4 + 2]) }
    var outside = [Bool](repeating: false, count: w * h)
    var stack = [0, w - 1, (h - 1) * w, h * w - 1]
    while let i = stack.popLast() {
        if outside[i] || brightness(i) > 200 { continue }
        outside[i] = true
        let x = i % w, y = i / w
        if x > 0 { stack.append(i - 1) }
        if x < w - 1 { stack.append(i + 1) }
        if y > 0 { stack.append(i - w) }
        if y < h - 1 { stack.append(i + w) }
    }
    // Premultiplied: keeping RGB and setting alpha to the brightest channel turns black-blended glow into translucent glow.
    for i in 0..<(w * h) where outside[i] { px[i * 4 + 3] = brightness(i) }
    return ctx.makeImage()!
}()

func draw(in ctx: CGContext) {
    // macOS icon grid: the tile's border lands on the 824 pt rounded square centred on the 1024 canvas.
    let scale = 824 / sourceTile.width
    let size = CGFloat(artwork.width) * scale
    let tileCenter = CGPoint(x: sourceTile.midX * scale, y: (CGFloat(artwork.height) - sourceTile.midY) * scale)
    ctx.draw(artwork, in: CGRect(x: 512 - tileCenter.x, y: 512 - tileCenter.y, width: size, height: size))
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
