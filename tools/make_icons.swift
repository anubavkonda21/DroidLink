// Renders the DroidLink app icon (Mac + phone linked, white on Apple blue) for both apps.
// Run from the repo root: swift tools/make_icons.swift
import AppKit

let blueTop = NSColor(srgbRed: 0x40 / 255.0, green: 0xA8 / 255.0, blue: 1, alpha: 1)
let blueBottom = NSColor(srgbRed: 0x00 / 255.0, green: 0x6A / 255.0, blue: 0xE6 / 255.0, alpha: 1)

/// White outline glyph: draw the template symbol, then recolour only its opaque pixels white.
func glyph(size: CGFloat) -> NSImage {
    let symbol = NSImage(systemSymbolName: "laptopcomputer.and.iphone", accessibilityDescription: nil)!
        .withSymbolConfiguration(.init(pointSize: size, weight: .medium))!
    return NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        NSColor.white.set()
        rect.fill(using: .sourceAtop)
        return true
    }
}

/// px x px PNG. `shape`: Mac squircle, Android legacy circle, or nil for a transparent adaptive foreground.
enum Shape { case squircle, circle }
func render(_ px: Int, shape: Shape?, glyphScale: CGFloat, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    if let shape {
        let body: NSBezierPath
        switch shape {
        case .squircle: // Apple icon grid: 824/1024 body with ~22.5% corner radius
            let inset = s * 100 / 1024
            let r = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
            body = NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225)
        case .circle:
            body = NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.04, dy: s * 0.04))
        }
        NSGradient(starting: blueTop, ending: blueBottom)!.draw(in: body, angle: -90)
    }
    let g = glyph(size: s * glyphScale)
    let w = s * glyphScale * 1.9, h = w * g.size.height / g.size.width
    g.draw(in: NSRect(x: (s - w) / 2, y: (s - h) / 2, width: w, height: h))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

let fm = FileManager.default
// Mac: iconset -> icns
let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try! fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    render(base, shape: .squircle, glyphScale: 0.33, to: "\(iconset)/icon_\(base)x\(base).png")
    render(base * 2, shape: .squircle, glyphScale: 0.33, to: "\(iconset)/icon_\(base)x\(base)@2x.png")
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", "mac/DroidLink/AppIcon.icns"]
try! p.run(); p.waitUntilExit()
precondition(p.terminationStatus == 0, "iconutil failed")
render(1024, shape: .squircle, glyphScale: 0.33, to: "docs/icon.png")

// Android: adaptive foreground (glyph inside the 66% safe zone) + legacy round-ish icon per density
let res = "android/app/src/main/res"
for (dir, scale) in [("mdpi", 1.0), ("hdpi", 1.5), ("xhdpi", 2.0), ("xxhdpi", 3.0), ("xxxhdpi", 4.0)] {
    let folder = "\(res)/mipmap-\(dir)"
    try! fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
    render(Int(108 * scale), shape: nil, glyphScale: 0.22, to: "\(folder)/ic_launcher_foreground.png")
    render(Int(48 * scale), shape: .circle, glyphScale: 0.33, to: "\(folder)/ic_launcher.png")
    render(Int(48 * scale), shape: .circle, glyphScale: 0.33, to: "\(folder)/ic_launcher_round.png")
}
print("icons written")
