// Draws Resources/AppIcon.icns: Night Shift, a prompt chevron over a usage bar on a dark slab.
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
// So the art sits in a rounded-square tile and the two 1x PNGs are left out. No Icon Composer
// file or asset catalog needed.
import AppKit
import SwiftUI

// MARK: - Palette (the icon's own; the app's UI uses system colours)

// Night Shift: a dark slab with a prompt chevron over a usage bar. Orange is the only colour, and it
// marks only the amount used and its glow; everything else is grayscale. Design and exact geometry:
// design/icon-night-shift/ (icon.svg, NOTES.md).
let tileTop: UInt32 = 0x202126, tileBottom: UInt32 = 0x09090B
let slabTop: UInt32 = 0x3A3B41, slabBottom: UInt32 = 0x16171A
let fillTop: UInt32 = 0xFFB35E, fillBottom: UInt32 = 0xF08A2A
let trackColor: UInt32 = 0x050506

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
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

    // The standard icon grid: a tile inset by ~10%, less at small sizes so it isn't tiny.
    let margin = pixels >= 128 ? (px * 100 / 1024).rounded() : px / 16
    let tile = CGRect(x: margin, y: margin, width: px - 2 * margin, height: px - 2 * margin)
    let tilePath = tileShape(tile)

    // The design's 1024 grid (y down) onto the tile (CG, y up).
    let k = tile.width / 1024
    func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
        CGRect(x: tile.minX + x * k, y: tile.maxY - (y + h) * k, width: w * k, height: h * k)
    }
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: tile.minX + x * k, y: tile.maxY - y * k) }
    func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: radius * k, cornerHeight: radius * k, transform: nil)
    }
    /// A vertical gradient over `r`, top colour to bottom.
    func vertical(_ r: CGRect, _ colors: [CGColor], _ locations: [CGFloat]) {
        g.drawLinearGradient(gradient(colors, locations), start: CGPoint(x: 0, y: r.maxY), end: CGPoint(x: 0, y: r.minY), options: [])
    }

    // The tile, with a soft shadow for systems that don't draw one (macOS 26+ discards it), and the
    // orange glow pooled at its foot.
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -px * 0.012), blur: px * 0.028, color: rgb(0x000000, 0.4))
    g.beginTransparencyLayer(auxiliaryInfo: nil)
    g.addPath(tilePath); g.clip()
    vertical(tile, [rgb(tileTop), rgb(tileBottom)], [0, 1])
    let glow = point(512, 840)
    g.saveGState()
    g.translateBy(x: glow.x, y: glow.y)
    g.scaleBy(x: 1, y: 150.0 / 400.0) // an ellipse 400 wide by 150 high, from a round gradient
    g.drawRadialGradient(gradient([rgb(fillBottom, 0.55), rgb(fillBottom, 0)], [0, 1]),
                         startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 400 * k, options: [])
    g.restoreGState()
    g.endTransparencyLayer()
    g.restoreGState()

    // The slab: its shadow, then the slab itself painted once over it.
    let slabRect = box(132, 220, 760, 584)
    let slab = rounded(slabRect, 150)
    shadowOnly(g, slab, color: rgb(0x000000, 0.7), offset: CGSize(width: 0, height: -30 * k), blur: 56 * k)
    g.saveGState()
    g.addPath(slab); g.clip()
    vertical(slabRect, [rgb(slabTop), rgb(slabBottom)], [0, 1])
    g.restoreGState()

    // A thin rim of light along its top edge, where there are pixels enough to show it.
    if pixels > 32 {
        let rimRect = box(134, 222, 756, 580)
        g.saveGState()
        g.addPath(rounded(rimRect, 148)); g.setLineWidth(5 * k); g.replacePathWithStrokedPath(); g.clip()
        vertical(rimRect, [rgb(0xFFFFFF, 0.3), rgb(0xFFFFFF, 0)], [0, 0.3])
        g.restoreGState()
    }

    // The prompt chevron.
    let chevron = CGMutablePath()
    chevron.move(to: point(282, 318)); chevron.addLine(to: point(398, 404)); chevron.addLine(to: point(282, 490))
    g.addPath(chevron)
    g.setStrokeColor(rgb(0xFFFFFF)); g.setLineWidth(84 * k); g.setLineCap(.round); g.setLineJoin(.round)
    g.strokePath()

    // The usage bar: a dark track, filled 72.7% in orange with a gloss on its upper half.
    let trackRect = box(212, 548, 600, 148)
    let track = rounded(trackRect, 74)
    g.setFillColor(rgb(trackColor))
    g.addPath(track); g.fillPath()
    g.saveGState()
    g.addPath(track); g.clip()
    let fill = box(212, 548, 436, 148)
    g.clip(to: fill)
    vertical(fill, [rgb(fillTop), rgb(fillBottom)], [0, 1])
    let gloss = box(212, 548, 436, 74)
    g.clip(to: gloss)
    vertical(gloss, [rgb(0xFFFFFF, 0.42), rgb(0xFFFFFF, 0)], [0, 0.55])
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
guard iconutil.terminationStatus == 0 else {
    print("iconutil failed; Resources/AppIcon.icns is unchanged")
    exit(1)
}
print("wrote Resources/AppIcon.icns")

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
