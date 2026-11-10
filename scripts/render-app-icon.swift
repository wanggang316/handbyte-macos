// Render the Handbyte app icon into an Xcode app icon set.
//
// Usage: swift render-app-icon.swift <AppIcon.appiconset dir>
//
// The icon is drawn with Core Graphics at every size the set needs, so no
// binary source image is tracked. Rerun after a design change (make icon).
//
// Design (1024 pt canvas, Apple's macOS icon grid): an ink rounded square
// holds the mark. The mark is a white block of storage with one piece cut
// out of the top right corner, and a green rounded square in the cut: the
// byte that left. Flat colors, no gradient.

import AppKit
import Foundation

struct Slot {
    let pixels: Int
    let points: Int
    let scale: Int
    var filename: String { "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png" }
}

let slots: [Slot] = [
    Slot(pixels: 16, points: 16, scale: 1), Slot(pixels: 32, points: 16, scale: 2),
    Slot(pixels: 32, points: 32, scale: 1), Slot(pixels: 64, points: 32, scale: 2),
    Slot(pixels: 128, points: 128, scale: 1), Slot(pixels: 256, points: 128, scale: 2),
    Slot(pixels: 256, points: 256, scale: 1), Slot(pixels: 512, points: 256, scale: 2),
    Slot(pixels: 512, points: 512, scale: 1), Slot(pixels: 1024, points: 512, scale: 2),
]

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let ink = rgb(17, 18, 20)
let paper = rgb(255, 255, 255)
let green = rgb(61, 220, 151)

/// The block with the cut, on the 64 unit grid of the logo.
func blockPath() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 21, y: 8))
    path.addArc(tangent1End: CGPoint(x: 32.5, y: 8), tangent2End: CGPoint(x: 32.5, y: 31.5), radius: 3.5)
    path.addArc(tangent1End: CGPoint(x: 32.5, y: 31.5), tangent2End: CGPoint(x: 56, y: 31.5), radius: 11)
    path.addArc(tangent1End: CGPoint(x: 56, y: 31.5), tangent2End: CGPoint(x: 56, y: 56), radius: 3.5)
    path.addArc(tangent1End: CGPoint(x: 56, y: 56), tangent2End: CGPoint(x: 8, y: 56), radius: 13)
    path.addArc(tangent1End: CGPoint(x: 8, y: 56), tangent2End: CGPoint(x: 8, y: 8), radius: 13)
    path.addArc(tangent1End: CGPoint(x: 8, y: 8), tangent2End: CGPoint(x: 32.5, y: 8), radius: 13)
    path.closeSubpath()
    return path
}

/// Draw the icon in a 1024 x 1024 design space with the origin at the top left.
func drawIcon(in ctx: CGContext) {
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 186, cornerHeight: 186, transform: nil)

    // Plate shadow, as in Apple's icon template.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 14), blur: 28, color: rgb(0, 0, 0, 0.42))
    ctx.setFillColor(ink)
    ctx.addPath(platePath)
    ctx.fillPath()
    ctx.restoreGState()

    // The mark fills two thirds of the plate: 64 grid units become 544 pt.
    ctx.saveGState()
    ctx.translateBy(x: 240, y: 240)
    ctx.scaleBy(x: 8.5, y: 8.5)
    ctx.setFillColor(paper)
    ctx.addPath(blockPath())
    ctx.fillPath()
    ctx.setFillColor(green)
    ctx.addPath(CGPath(roundedRect: CGRect(x: 37, y: 8, width: 19, height: 19), cornerWidth: 6.5, cornerHeight: 6.5, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
}

func render(pixels: Int) -> Data {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    // Flip to a top-left origin and scale the 1024 pt design to the target.
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: -CGFloat(pixels) / 1024)
    drawIcon(in: ctx)
    let image = ctx.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])!
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: render-app-icon.swift <AppIcon.appiconset dir>\n".data(using: .utf8)!)
    exit(2)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

var images: [[String: String]] = []
for slot in slots {
    try render(pixels: slot.pixels).write(to: outDir.appendingPathComponent(slot.filename))
    images.append(["filename": slot.filename, "idiom": "mac", "scale": "\(slot.scale)x", "size": "\(slot.points)x\(slot.points)"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: outDir.appendingPathComponent("Contents.json"))
print("wrote \(slots.count) images to \(outDir.path)")
