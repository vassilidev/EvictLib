// Draws the app icon: swift Tools/AppIcon.swift <out.png> [light|dark|tinted]
import AppKit
import CoreImage

let out = CommandLine.arguments[1]
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "light"
let S: CGFloat = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(h >> 16 & 0xff) / 255, green: CGFloat(h >> 8 & 0xff) / 255, blue: CGFloat(h & 0xff) / 255, alpha: a)
}
let light = mode == "light"

// Background: blue → indigo (light), near-black (dark, tinted)
let bgColors = light ? [rgb(0x3B8CFF), rgb(0x4A3FD8)] : [rgb(0x23233A), rgb(0x0B0B12)]
ctx.drawLinearGradient(CGGradient(colorsSpace: cs, colors: bgColors as CFArray, locations: [0, 1])!,
                       start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0), options: [])

func card(_ angle: CGFloat, _ alpha: CGFloat, _ dx: CGFloat, _ dy: CGFloat, body: ((CGRect) -> Void)? = nil) {
    ctx.saveGState()
    ctx.translateBy(x: S / 2 + dx, y: S / 2 + dy)
    ctx.rotate(by: angle * .pi / 180)
    let r = CGRect(x: -270, y: -210, width: 540, height: 420)
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: rgb(0x000000, light ? 0.3 : 0.6))
    ctx.addPath(CGPath(roundedRect: r, cornerWidth: 56, cornerHeight: 56, transform: nil))
    ctx.setFillColor(light ? rgb(0xFFFFFF, alpha) : rgb(0xE8E8F2, alpha * 0.9))
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    body?(r)
    ctx.restoreGState()
}
card(-16, 0.30, -40, 70)
card(-7, 0.55, -18, 40)
card(5, 1, 10, -10) { r in
    let inner = r.insetBy(dx: 34, dy: 34)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: inner, cornerWidth: 30, cornerHeight: 30, transform: nil))
    ctx.clip()
    let sky = light ? [rgb(0xD6E8FF), rgb(0xA9CCFF)] : [rgb(0x3A4A7A), rgb(0x24305A)]
    ctx.drawLinearGradient(CGGradient(colorsSpace: cs, colors: sky as CFArray, locations: [0, 1])!,
                           start: CGPoint(x: 0, y: inner.maxY), end: CGPoint(x: 0, y: inner.minY), options: [])
    ctx.setFillColor(rgb(0xFFC83D))
    ctx.fillEllipse(in: CGRect(x: inner.maxX - 150, y: inner.maxY - 150, width: 92, height: 92))
    ctx.setFillColor(rgb(0x5E8DF0))
    ctx.move(to: CGPoint(x: inner.minX - 20, y: inner.minY)); ctx.addLine(to: CGPoint(x: inner.minX + 150, y: inner.minY + 190))
    ctx.addLine(to: CGPoint(x: inner.minX + 330, y: inner.minY)); ctx.fillPath()
    ctx.setFillColor(rgb(0x3D5FD0))
    ctx.move(to: CGPoint(x: inner.minX + 170, y: inner.minY)); ctx.addLine(to: CGPoint(x: inner.minX + 340, y: inner.minY + 250))
    ctx.addLine(to: CGPoint(x: inner.maxX + 40, y: inner.minY)); ctx.fillPath()
    ctx.restoreGState()
}

// Badge: disc with a down arrow (a lighter library)
let c = CGPoint(x: S / 2 + 230, y: S / 2 - 215)
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 30, color: rgb(0x000000, 0.35))
ctx.setFillColor(light ? rgb(0xFFFFFF) : rgb(0x5B6CFF))
ctx.fillEllipse(in: CGRect(x: c.x - 120, y: c.y - 120, width: 240, height: 240))
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.setStrokeColor(light ? rgb(0x4A3FD8) : rgb(0xFFFFFF))
ctx.setLineWidth(34); ctx.setLineCap(.round); ctx.setLineJoin(.round)
ctx.move(to: CGPoint(x: c.x, y: c.y + 62)); ctx.addLine(to: CGPoint(x: c.x, y: c.y - 58))
ctx.move(to: CGPoint(x: c.x - 52, y: c.y - 6)); ctx.addLine(to: CGPoint(x: c.x, y: c.y - 58)); ctx.addLine(to: CGPoint(x: c.x + 52, y: c.y - 6))
ctx.strokePath()

var image = ctx.makeImage()!
if mode == "tinted" {   // grayscale: iOS applies the user's tint
    let gray = CIImage(cgImage: image).applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
    image = CIContext().createCGImage(gray, from: gray.extent)!
}
try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
