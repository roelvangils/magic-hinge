import DuoCore
import AppKit

/// An explicitly illustrative image for the preview and reproducible GPU checks.
public enum DemoArtwork {
    public static func make(width: Int = 1440, height: Int = 900) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: CGFloat(width) / 1440, y: CGFloat(height) / 900)
        let colors = [NSColor(red: 0.07, green: 0.19, blue: 0.26, alpha: 1).cgColor,
                      NSColor(red: 0.38, green: 0.55, blue: 0.58, alpha: 1).cgColor,
                      NSColor(red: 0.91, green: 0.78, blue: 0.55, alpha: 1).cgColor]
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 0.7, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 700, y: 900), end: CGPoint(x: 1100, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        for i in (0..<4).reversed() {
            let p = CGMutablePath()
            let base = CGFloat(i) * 105
            p.move(to: CGPoint(x: -100, y: base - 80))
            p.addCurve(to: CGPoint(x: 1500, y: base + 190), control1: CGPoint(x: 300, y: base + 520), control2: CGPoint(x: 1050, y: base - 160))
            p.addLine(to: CGPoint(x: 1500, y: 0)); p.addLine(to: .zero); p.closeSubpath()
            context.setFillColor(NSColor(red: 0.84 - CGFloat(i)*0.08, green: 0.65 - CGFloat(i)*0.065, blue: 0.40 - CGFloat(i)*0.045, alpha: 1).cgColor)
            context.addPath(p); context.fillPath()
        }
        // Fine lines make the top-to-bottom defocus easy to judge.
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        context.setLineWidth(1)
        for x in stride(from: 0, through: 1440, by: 48) {
            context.move(to: CGPoint(x: x, y: 0)); context.addLine(to: CGPoint(x: x, y: 900)); context.strokePath()
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 128, weight: .thin), .foregroundColor: NSColor.white]
        (L10n.text("Hello, magic.") as NSString).draw(at: CGPoint(x: 90, y: 565), withAttributes: title)
        (L10n.text("A DIFFERENT PERSPECTIVE") as NSString).draw(at: CGPoint(x: 100, y: 715), withAttributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.72), .kern: 5])
        ("Magic Hinge" as NSString).draw(at: CGPoint(x: 50, y: 860), withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white])
        context.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
        context.addPath(CGPath(roundedRect: CGRect(x: 470, y: 22, width: 500, height: 66), cornerWidth: 22, cornerHeight: 22, transform: nil)); context.fillPath()
        let iconColors: [NSColor] = [.systemBlue, .systemOrange, .systemGreen, .systemPink, .systemPurple, .systemTeal, .white]
        for (i, color) in iconColors.enumerated() {
            context.setFillColor(color.withAlphaComponent(0.85).cgColor)
            context.addPath(CGPath(roundedRect: CGRect(x: 489+i*67, y: 34, width: 44, height: 44), cornerWidth: 12, cornerHeight: 12, transform: nil)); context.fillPath()
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }
}
