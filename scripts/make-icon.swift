// Draws Resources/AppIcon.icns: the menu bar's progress ring, lit and set into a night-blue tile.
// Run from the repo root: swift scripts/make-icon.swift [previewDir]
// With a folder it also writes icon-1024.png and a contact sheet of every size there.
//
// How macOS 26+ draws a plain .icns (checked on macOS 27, NSWorkspace.icon(forFile:) on a built app):
//  - Artwork whose silhouette is a rounded square counts as conforming. The system re-masks it to
//    its own shape, scales it to fill, and adds its own rim light and shadow, so the tile's margin
//    and baked shadow are dropped and there is no plate.
//  - Any other silhouette (a bare ring, a circle) is shrunk onto a dark plate, at every size.
//  - One exception: the 1x 16px and 32px PNGs get the plate even as rounded squares, but only on a
//    1x display (Retina draws those sizes from the @2x PNGs). The iconset leaves them out, so the
//    system scales the @2x ones down instead.
// So the ring sits in a rounded-square tile and the two 1x PNGs are left out. No Icon Composer
// file or asset catalog needed.
import AppKit
import SwiftUI

// MARK: - Palette (the icon's own; the app's UI uses system colours)

let tileTop: UInt32 = 0x2C3568, tileBottom: UInt32 = 0x080A1A
/// The lit arc, tail to head: gold, amber, coral. It heats up the way the meter's levels do.
let arcStops: [(CGFloat, UInt32)] = [(0, 0xFFC95F), (0.5, 0xFF9650), (1, 0xFF4B5C)]
let lit: CGFloat = 0.70   // how much of the ring is lit

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }
/// The arc's colour `t` of the way from tail to head.
func arcColor(_ t: CGFloat) -> CGColor {
    let hi = min(max(arcStops.firstIndex { t <= $0.0 } ?? arcStops.count - 1, 1), arcStops.count - 1)
    let (t0, c0) = arcStops[hi - 1], (t1, c1) = arcStops[hi]
    let k = min(max((t - t0) / (t1 - t0), 0), 1)
    func channel(_ shift: UInt32) -> CGFloat {
        lerp(CGFloat((c0 >> shift) & 0xFF), CGFloat((c1 >> shift) & 0xFF), k) / 255
    }
    return CGColor(srgbRed: channel(16), green: channel(8), blue: channel(0), alpha: 1)
}

// MARK: - Drawing

let space = CGColorSpace(name: CGColorSpace.sRGB)!

func bitmap(_ width: Int, _ height: Int? = nil) -> CGContext {
    let g = CGContext(data: nil, width: width, height: height ?? width, bitsPerComponent: 8, bytesPerRow: 0,
                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    g.interpolationQuality = .high
    return g
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

/// The tile's silhouette: the system's rounded square (continuous corners), which is what lets
/// macOS 26+ recognise the icon as conforming.
func tileShape(_ r: CGRect) -> CGPath {
    RoundedRectangle(cornerRadius: r.width * 0.225, style: .continuous).path(in: r).cgPath
}

/// Shades the inside edge of `shape`, as if it were cut into the surface.
func innerShadow(_ g: CGContext, _ shape: CGPath, color: CGColor, offset: CGSize, blur: CGFloat) {
    g.saveGState()
    g.addPath(shape); g.clip()
    let around = CGMutablePath()
    around.addRect(shape.boundingBox.insetBy(dx: -blur * 6, dy: -blur * 6))
    around.addPath(shape)
    g.setShadow(offset: offset, blur: blur, color: color)
    g.setFillColor(rgb(0x000000))
    g.addPath(around); g.fillPath(using: .evenOdd)
    g.restoreGState()
}

/// Draws only the shadow of `shape`, not the shape: it is moved off the canvas and the shadow's
/// offset brings the shadow back. That leaves the caller to paint the shape itself once, with a
/// clean edge, instead of over a fill that fringes it.
func shadowOnly(_ g: CGContext, _ shape: CGPath, color: CGColor, offset: CGSize, blur: CGFloat) {
    let away = CGFloat(g.width) * 4
    g.saveGState()
    g.translateBy(x: away, y: 0)
    g.setShadow(offset: CGSize(width: offset.width - away, height: offset.height), blur: blur, color: color)
    g.setFillColor(rgb(0x000000))
    g.addPath(shape); g.fillPath()
    g.restoreGState()
}

func render(_ pixels: Int) -> CGImage {
    let px = CGFloat(pixels)
    let g = bitmap(pixels)
    let c = CGPoint(x: px / 2, y: px / 2)

    // Big sizes carry the depth (glow, groove, highlights); small ones keep what survives 16px:
    // a bolder ring, no fine shading.
    let detail = min(max((px - 48) / 160, 0), 1)

    // The standard icon grid: a tile inset by ~10%, less at small sizes so it isn't tiny.
    let margin = pixels >= 128 ? (px * 100 / 1024).rounded() : px / 16
    let tile = CGRect(x: margin, y: margin, width: px - 2 * margin, height: px - 2 * margin)
    let size = tile.width
    let tilePath = tileShape(tile)

    // The tile: night-blue lit from above, a pool of light behind the ring, a soft shadow for
    // systems that don't draw one (macOS 26+ discards it).
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -px * 0.012), blur: px * 0.028, color: rgb(0x000000, 0.4))
    g.beginTransparencyLayer(auxiliaryInfo: nil)
    g.addPath(tilePath); g.clip()
    g.drawLinearGradient(gradient([rgb(tileTop), rgb(tileBottom)], [0, 1]),
                         start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])
    let pool = CGPoint(x: c.x, y: c.y + size * 0.08)
    g.drawRadialGradient(gradient([rgb(0x4C57AE, 0.34), rgb(0x4C57AE, 0)], [0, 1]),
                         startCenter: pool, startRadius: 0, endCenter: pool, endRadius: size * 0.6, options: [])
    g.endTransparencyLayer()
    g.restoreGState()

    // The ring, clockwise from 12 o'clock like the menu bar's: outer radius, stroke, centre line.
    let outer = lerp(0.385, 0.335, detail) * size
    let w = lerp(0.205, 0.125, detail) * size
    let r = outer - w / 2
    let inner = r - w / 2
    let start = CGFloat.pi / 2
    let end = start - lit * 2 * .pi

    let circle = CGMutablePath()
    circle.addEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    let track = circle.copy(strokingWithWidth: w, lineCap: .butt, lineJoin: .round, miterLimit: 10)
    let sweep = CGMutablePath()
    sweep.addArc(center: c, radius: r, startAngle: start, endAngle: end, clockwise: true)
    let arc = sweep.copy(strokingWithWidth: w, lineCap: .round, lineJoin: .round, miterLimit: 10)

    // The empty track: a groove, shaded along its top edge, a thin lip catching light below. Small
    // sizes have no shading to show it, so it is more opaque there and the ring still reads as one.
    g.setFillColor(rgb(0x9AA6F2, lerp(0.30, 0.15, detail)))
    g.addPath(track); g.fillPath()
    if detail > 0 {
        innerShadow(g, track, color: rgb(0x000000, 0.5 * detail), offset: CGSize(width: 0, height: -w * 0.08), blur: w * 0.22)
        innerShadow(g, track, color: rgb(0xFFFFFF, 0.12 * detail), offset: CGSize(width: 0, height: w * 0.05), blur: w * 0.08)
    }

    // The lit arc's shadow lifts it off the groove, and its additive glow spills onto the tile.
    shadowOnly(g, arc, color: rgb(0x000000, 0.45), offset: CGSize(width: 0, height: -w * 0.10), blur: w * 0.25)
    g.saveGState()
    g.setBlendMode(.plusLighter)
    shadowOnly(g, arc, color: rgb(0xFF6A3D, 0.44 * detail + 0.12), offset: .zero, blur: w * 0.8)
    g.restoreGState()

    // The arc itself, painted once: its colour in thin wedges along the sweep (the round caps run
    // past both ends)...
    g.saveGState()
    g.addPath(arc); g.clip()
    let wedges = 360
    let overshoot = (w / 2 / r) / (lit * 2 * .pi)
    for i in 0..<wedges {
        let t0 = CGFloat(i) / CGFloat(wedges), t1 = CGFloat(i + 1) / CGFloat(wedges)
        let a0 = start + (end - start) * (i == 0 ? t0 - overshoot : t0 - 0.002)
        let a1 = start + (end - start) * (i == wedges - 1 ? t1 + overshoot : t1 + 0.002)
        let wedge = CGMutablePath()
        wedge.move(to: c)
        wedge.addArc(center: c, radius: outer * 1.3, startAngle: a0, endAngle: a1, clockwise: true)
        wedge.closeSubpath()
        g.setFillColor(arcColor((t0 + t1) / 2))
        g.addPath(wedge); g.fillPath()
    }
    // ...tube shading: the inside edge falls into shade and the outside catches the light...
    let shade: UInt32 = 0xA33324
    g.drawRadialGradient(gradient([rgb(shade, 0.30), rgb(shade, 0.17), rgb(shade, 0.06), rgb(shade, 0)], [0, 0.2, 0.4, 0.55]),
                         startCenter: c, startRadius: inner, endCenter: c, endRadius: outer, options: [])
    g.drawRadialGradient(gradient([rgb(0xFFFFFF, 0), rgb(0xFFFFFF, 0.05), rgb(0xFFFFFF, 0.11), rgb(0xFFFFFF, 0.15)], [0.45, 0.7, 0.9, 1]),
                         startCenter: c, startRadius: inner, endCenter: c, endRadius: outer, options: [])
    // ...the whole ring brighter at the top, deeper at the bottom...
    g.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.10), rgb(0xFFFFFF, 0), rgb(0xB02A30, 0), rgb(0xB02A30, 0.16)], [0, 0.45, 0.6, 1]),
                         start: CGPoint(x: 0, y: c.y + outer), end: CGPoint(x: 0, y: c.y - outer), options: [])
    if detail > 0 {   // ...and a fine highlight just inside the outer edge, strongest at the top
        let rim = CGMutablePath()
        let rimRadius = outer - w * 0.05
        rim.addEllipse(in: CGRect(x: c.x - rimRadius, y: c.y - rimRadius, width: 2 * rimRadius, height: 2 * rimRadius))
        g.saveGState()
        g.addPath(rim); g.setLineWidth(w * 0.05); g.replacePathWithStrokedPath(); g.clip()
        g.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.55 * detail), rgb(0xFFFFFF, 0)], [0, 1]),
                             start: CGPoint(x: 0, y: c.y + outer), end: CGPoint(x: 0, y: c.y), options: [])
        g.restoreGState()
    }
    g.restoreGState()

    // A shine across the top of the tile.
    g.saveGState()
    g.addPath(tilePath); g.clip()
    g.drawLinearGradient(gradient([rgb(0xFFFFFF, 0.08), rgb(0xFFFFFF, 0)], [0, 1]),
                         start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.maxY - size * 0.4), options: [])
    g.restoreGState()
    return g.makeImage()!
}

func png(_ image: CGImage) -> Data {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

// MARK: - Output

guard FileManager.default.fileExists(atPath: "Resources") else {
    print("run this from the repo root: swift scripts/make-icon.swift")
    exit(1)
}
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

var images: [Int: CGImage] = [:]
for pixels in [32, 64, 128, 256, 512, 1024] { images[pixels] = render(pixels) }
// No icon_16x16.png or icon_32x32.png (see the note at the top).
let reps: [(String, Int)] = [
    ("icon_16x16@2x.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, pixels) in reps { try png(images[pixels]!).write(to: iconset.appendingPathComponent(name)) }

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")

// MARK: - Preview

if CommandLine.arguments.count > 1 {
    let dir = URL(fileURLWithPath: CommandLine.arguments[1])
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try png(images[1024]!).write(to: dir.appendingPathComponent("icon-1024.png"))

    // A contact sheet on a light and a dark backdrop. Bottom row: 16 to 512pt on a 1x display
    // (16 and 32 are the @2x reps scaled down, as the system does without the 1x ones). Top row,
    // magnified: those two, then the @2x reps themselves (16pt and 32pt on a Retina display).
    let pad: CGFloat = 16
    let shown = [16, 32, 64, 128, 256, 512]
    let width = Int(shown.reduce(0) { $0 + CGFloat($1) } + pad * CGFloat(shown.count + 1))
    let zoomed: [(pixels: Int, shownAt: Int, zoom: Int)] = [(32, 16, 8), (64, 32, 4), (32, 32, 4), (64, 64, 2)]
    let half = 512 + 3 * Int(pad) + 16 * 8   // one backdrop's height
    let sheet = bitmap(width, half * 2)
    for (row, back) in [rgb(0xF0F0F0), rgb(0x242424)].enumerated() {
        let y0 = CGFloat(half * (1 - row))
        sheet.setFillColor(back)
        sheet.fill(CGRect(x: 0, y: y0, width: CGFloat(width), height: CGFloat(half)))
        var x = pad
        for s in shown {
            let rep = s <= 32 ? images[s * 2]! : images[s]!   // no 1x rep at 16 and 32
            sheet.draw(rep, in: CGRect(x: x, y: y0 + pad, width: CGFloat(s), height: CGFloat(s)))
            x += CGFloat(s) + pad
        }
        x = pad
        for (pixels, shownAt, zoom) in zoomed {
            let small = bitmap(shownAt)
            small.draw(images[pixels]!, in: CGRect(x: 0, y: 0, width: shownAt, height: shownAt))
            sheet.interpolationQuality = .none
            sheet.draw(small.makeImage()!, in: CGRect(x: x, y: y0 + 512 + 2 * pad, width: CGFloat(shownAt * zoom), height: CGFloat(shownAt * zoom)))
            sheet.interpolationQuality = .high
            x += CGFloat(shownAt * zoom) + pad
        }
    }
    try png(sheet.makeImage()!).write(to: dir.appendingPathComponent("contact-sheet.png"))
    print("wrote preview to \(dir.path)")
}
