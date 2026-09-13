import AppKit
import CoreText
// The SF Symbol characters supplied for these exact system symbol names.
let symbols = [("cursorarrow.click","􀭆"),("rectangle.and.hand.point.up.left","􀪤"),("digitalcrown.arrow.counterclockwise","􀻘"),("cpu.fill","􀧓"),("applelogo","􀣺"),("sensor.tag.radiowaves.forward.fill","􁁞"),("rectangle.inset.filled.badge.record","􂃕"),("globe","􀆪")]
func n(_ value:CGFloat) -> String { String(format:"%.4f",Double(value)) }
for (name,character) in symbols {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string:character,attributes:[.font:NSFont.systemFont(ofSize:32)]))
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]
    precondition(runs.count == 1 && CTRunGetGlyphCount(runs[0]) == 1)
    let font = (CTRunGetAttributes(runs[0]) as NSDictionary)[kCTFontAttributeName] as! CTFont
    var glyph = CGGlyph(); CTRunGetGlyphs(runs[0],CFRange(location:0,length:1),&glyph)
    guard glyph != 0, let path = CTFontCreatePathForGlyph(font,glyph,nil) else { fatalError("Missing vector symbol: \(name)") }
    var data = ""
    path.applyWithBlock { pointer in
        let e=pointer.pointee
        func point(_ i:Int)->String { n(e.points[i].x)+" "+n(e.points[i].y) }
        switch e.type {
        case .moveToPoint: data += "M"+point(0)
        case .addLineToPoint: data += "L"+point(0)
        case .addQuadCurveToPoint: data += "Q"+point(0)+" "+point(1)
        case .addCurveToPoint: data += "C"+point(0)+" "+point(1)+" "+point(2)
        case .closeSubpath: data += "Z"
        @unknown default: fatalError("Unknown path command")
        }
    }
    let box=path.boundingBoxOfPath, scale=26/max(box.width,box.height)
    let svg="""
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32">
    <!-- Apple SF Symbols: \(name). Apple terms apply. -->
    <path fill="#55555a" transform="translate(16 16) scale(\(n(scale)) -\(n(scale))) translate(\(n(-box.midX)) \(n(-box.midY)))" d="\(data)"/>
    </svg>
    """
    try svg.write(toFile:"website/assets/symbols/\(name).svg",atomically:true,encoding:.utf8)
}
