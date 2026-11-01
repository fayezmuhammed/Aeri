// Builds Assets/AppIcon.icns from the presentation logo (Assets/aeri_logo.png):
// finds the rounded-square icon above the wordmark, masks its corners to transparency,
// and places it on Apple's 1024px icon grid (824px body, 100px margin, soft shadow).
// Usage: swift scripts/make-icon.swift
import AppKit

let src = "Assets/aeri_logo.png"
guard let image = NSImage(contentsOfFile: src),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("can't read \(src)") }
let w = cg.width, h = cg.height

// Read pixels to find the icon's bounding box.
var px = [UInt8](repeating: 0, count: w * h * 4)
let rgb = CGColorSpace(name: CGColorSpace.sRGB)!
let reader = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                       space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
reader.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

// Rows from the top; a row belongs to the icon if it has a real run of lit pixels (ignores
// stray noise). Stop at the first dark gap after the icon, before the wordmark.
var minX = w, maxX = 0, minY = h, maxY = 0
var seenIcon = false
for row in 0..<h {
    var count = 0, rowMin = w, rowMax = 0
    for x in 0..<w {
        let i = (row * w + x) * 4   // bitmap memory starts at the top row
        if Int(px[i]) + Int(px[i + 1]) + Int(px[i + 2]) > 60 {
            count += 1
            rowMin = min(rowMin, x); rowMax = max(rowMax, x)
        }
    }
    if count > 40 {
        seenIcon = true
        minX = min(minX, rowMin); maxX = max(maxX, rowMax)
        minY = min(minY, row); maxY = max(maxY, row)
    } else if seenIcon { break }
}
let side = max(maxX - minX, maxY - minY)
let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
let crop = CGRect(x: cx - side / 2, y: cy - side / 2, width: side, height: side)
print("icon bounds: \(crop)")
let body = cg.cropping(to: crop)!

let canvas = 1024, inset: CGFloat = 100, size = CGFloat(canvas) - 2 * inset
let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                    space: rgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let rect = CGRect(x: inset, y: inset, width: size, height: size)
let path = CGPath(roundedRect: rect, cornerWidth: size * 0.225, cornerHeight: size * 0.225, transform: nil)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(path); ctx.setFillColor(CGColor(gray: 0, alpha: 1)); ctx.fillPath()
ctx.restoreGState()
ctx.addPath(path); ctx.clip()
// Slight overscan hides the anti-aliased dark rim of the source edge.
ctx.draw(body, in: rect.insetBy(dx: -size * 0.01, dy: -size * 0.01))

let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "Assets/AppIcon.png"))

// .iconset → .icns
let set = "Assets/AppIcon.iconset"
try? FileManager.default.removeItem(atPath: set)
try! FileManager.default.createDirectory(atPath: set, withIntermediateDirectories: true)
for s in [16, 32, 128, 256, 512] {
    for (scale, suffix) in [(1, ""), (2, "@2x")] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
        p.arguments = ["-z", "\(s * scale)", "\(s * scale)", "Assets/AppIcon.png", "--out", "\(set)/icon_\(s)x\(s)\(suffix).png"]
        p.standardOutput = FileHandle.nullDevice
        try! p.run(); p.waitUntilExit()
    }
}
let ic = Process()
ic.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
ic.arguments = ["-c", "icns", set, "-o", "Assets/AppIcon.icns"]
try! ic.run(); ic.waitUntilExit()
try? FileManager.default.removeItem(atPath: set)
print("wrote Assets/AppIcon.png and Assets/AppIcon.icns")
