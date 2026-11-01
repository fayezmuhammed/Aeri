import AppKit

/// Picks an accent color from cover art: the average of its pixels weighted toward vivid ones
/// (so a black cover with a red logo gives red, not grey), then brightened to glow on black.
enum ArtworkColor {
    static func accent(of image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let n = 16
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))

        var r = 0.0, g = 0.0, b = 0.0, total = 0.0
        for i in stride(from: 0, to: px.count, by: 4) {
            let c = NSColor(srgbRed: CGFloat(px[i]) / 255, green: CGFloat(px[i + 1]) / 255, blue: CGFloat(px[i + 2]) / 255, alpha: 1)
            let s = Double(c.saturationComponent), v = Double(c.brightnessComponent)
            let w = pow(s * v, 2) + 0.002   // tiny floor so grey covers still get a color
            r += Double(c.redComponent) * w
            g += Double(c.greenComponent) * w
            b += Double(c.blueComponent) * w
            total += w
        }
        guard total > 0 else { return nil }
        let avg = NSColor(srgbRed: r / total, green: g / total, blue: b / total, alpha: 1)
        // Keep the hue; lift saturation and brightness so it reads as a glow.
        let sat = avg.saturationComponent < 0.08 ? avg.saturationComponent : max(avg.saturationComponent, 0.55)
        return NSColor(hue: avg.hueComponent, saturation: sat, brightness: max(avg.brightnessComponent, 0.85), alpha: 1)
    }
}
