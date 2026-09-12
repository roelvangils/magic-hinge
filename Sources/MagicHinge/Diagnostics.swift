import AppKit
import OSLog

enum Diagnostics {
    private static let logger = Logger(subsystem: "be.elevenways.MacBookDuo", category: "render")
    static func record(_ message: String) { logger.notice("\(message, privacy: .public)") }
    /// Aggregate luminance only: never saves or logs screenshot pixels.
    static func brightness(_ image: CGImage) -> Double {
        let c = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        c.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        let bytes = c.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<1024).reduce(0.0) { $0 + Double(bytes[$1*4]) + Double(bytes[$1*4+1]) + Double(bytes[$1*4+2]) } / (1024*3*255)
    }
}
