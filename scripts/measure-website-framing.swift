#!/usr/bin/env swift
import Foundation
import ImageIO
import CoreGraphics

// Build-time image analysis; never read pixels on the browser's animation path.
let html = try String(contentsOfFile: "website/index.html", encoding: .utf8)
let regex = try NSRegularExpression(pattern: #"data-(?:dark-)?(?:idle-)?sequence="([^"]+)""#)
var sequences: [String: Any] = [:]
for match in regex.matches(in: html, range: NSRange(html.startIndex..., in: html)) {
    let path = String(html[Range(match.range(at: 1), in: html)!])
    let url = URL(fileURLWithPath: "website/" + path)
    let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    let names = manifest["frames"] as! [String]
    let hex = UInt32(manifest["background"] as! String, radix: 16)!
    let background = [Int((hex >> 16) & 255), Int((hex >> 8) & 255), Int(hex & 255)]
    var measured: [String: [Double]] = [:]
    let width = 1440, height = 1000
    for name in Set(names) {
        let source = CGImageSourceCreateWithURL(url.deletingLastPathComponent().appendingPathComponent(name) as CFURL, nil)!
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        var top = height, bottom = 0
        for y in 0..<height {
            var occupied = 0
            for x in 0..<width {
                let i = (y * width + x) * 4
                if (0..<3).contains(where: { abs(Int(bytes[i + $0]) - background[$0]) > 8 }) { occupied += 1 }
            }
            if occupied >= width / 50 { top = min(top, y); bottom = y + 1 }
        }
        precondition(bottom > top, "No artwork in \(name)")
        measured[name] = [Double(top) / Double(height), Double(bottom) / Double(height)]
    }
    sequences[path] = ["width": manifest["width"]!, "height": manifest["height"]!, "bounds": names.map { measured[$0]! }]
    print("Measured \(path): \(names.count) poses")
}
let data = try JSONSerialization.data(withJSONObject: sequences, options: [.sortedKeys])
try data.write(to: URL(fileURLWithPath: "website/sequence-framing.json"))
