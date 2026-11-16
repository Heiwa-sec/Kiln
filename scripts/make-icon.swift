// Draws Kiln's icon (flat, no gradient) into an .appiconset. Run: swift scripts/make-icon.swift App/Assets.xcassets/AppIcon.appiconset
import AppKit

func icon(_ px: Int) -> Data {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: 0.086, green: 0.094, blue: 0.094, alpha: 1))
    ctx.addPath(CGPath(roundedRect: CGRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88), cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil)); ctx.fillPath()
    let c = CGPoint(x: s / 2, y: s / 2), r0 = s * 0.14, r1 = s * 0.36, n = 6, gap = 0.07
    for i in 0..<n {   // six flat wedges; one lit
        let a0 = Double(i) * 2 * .pi / Double(n) + gap, a1 = Double(i + 1) * 2 * .pi / Double(n) - gap
        let p = CGMutablePath()
        p.addArc(center: c, radius: r1, startAngle: a0, endAngle: a1, clockwise: false)
        p.addArc(center: c, radius: r0, startAngle: a1, endAngle: a0, clockwise: true); p.closeSubpath()
        ctx.setFillColor(i == 1 ? CGColor(red: 0.247, green: 0.659, blue: 0.588, alpha: 1) : CGColor(red: 0.91, green: 0.89, blue: 0.86, alpha: 0.9))
        ctx.addPath(p); ctx.fillPath()
    }
    return NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])
var images: [[String: String]] = []
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(pt)x\(pt)@\(scale)x.png"
    try icon(pt * scale).write(to: dir.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
}
let json = try JSONSerialization.data(withJSONObject: ["images": images, "info": ["version": 1, "author": "xcode"]], options: [.prettyPrinted])
try json.write(to: dir.appendingPathComponent("Contents.json"))
