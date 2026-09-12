import AppKit
import SceneKit
import DuoSimulation
import DuoGraphics

// Website-only tooling: shares the app's model articulation and Metal glass shader.
// Never captures a desktop. A custom image must be explicitly supplied.
@main struct WebsiteFrames {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.contains("--help") {
            print("WebsiteFrames --output DIR [--color silver|skyBlue|starlight|midnight] [--wallpaper FILE] [--frames 121] [--width 2880] [--height 2000] [--cache build/apple-models] [--background f5f5f7] [--appearance light|dark] [--finish original|space-gray] [--format jpg|png] [--motion scroll|idle]")
            return
        }
        guard arguments.count % 2 == 0 else { throw Failure.message("Options require values; use --help") }
        var options: [String:String] = [:]
        for i in stride(from:0,to:arguments.count,by:2) {
            guard ["--output","--color","--wallpaper","--frames","--width","--height","--cache","--background","--appearance","--finish","--format","--motion"].contains(arguments[i]), options[arguments[i]] == nil else { throw Failure.message("Unknown or duplicate option: \(arguments[i])") }
            options[arguments[i]] = arguments[i+1]
        }
        guard let output = options["--output"],
              let color = MacBookColor(rawValue:options["--color"] ?? "silver"), MacBookFamily.air.colors.contains(color),
              let count = Int(options["--frames"] ?? "121"), (2...361).contains(count),
              let width = Int(options["--width"] ?? "2880"), (320...3840).contains(width),
              let height = Int(options["--height"] ?? "2000"), (240...2160).contains(height) else { throw Failure.message("Invalid arguments; use --help") }
        let motion = options["--motion"] ?? "scroll"
        guard ["scroll","idle"].contains(motion) else { throw Failure.message("Motion must be scroll or idle") }
        let format = options["--format"] ?? "jpg"
        guard ["jpg","png"].contains(format) else { throw Failure.message("Format must be jpg or png") }
        let appearance = options["--appearance"] ?? "light"
        guard ["light","dark"].contains(appearance) else { throw Failure.message("Appearance must be light or dark") }
        let background = options["--background"] ?? "f5f5f7"
        guard background.count == 6, let rgb = UInt32(background,radix:16) else { throw Failure.message("Background must be six hex digits") }
        let destination = URL(fileURLWithPath:output)
        guard !FileManager.default.fileExists(atPath:destination.path) else { throw Failure.message("Output already exists; use a fresh directory to preserve the previous render.") }
        let configuration = MacBookConfiguration(family:.air,size:13,color:color)
        let cache = AppleModelCache(directory:URL(fileURLWithPath:options["--cache"] ?? "build/apple-models"))
        let asset = try await cache.modelURL(for:configuration)
        let model = try MacBookModel(assetURL:asset,configuration:configuration)
        let finish = options["--finish"] ?? "original"
        guard ["original","space-gray"].contains(finish), finish == "original" || color == .silver else { throw Failure.message("Space-gray finish requires the silver source model") }
        if finish == "space-gray" {
            // A presentation finish on the silver mesh, not a claim about an Apple SKU.
            // Preserve texture maps, black keys, screen, glass and bright white markings.
            var seen = Set<ObjectIdentifier>()
            model.product.enumerateChildNodes { node,_ in
                for material in node.geometry?.materials ?? [] where seen.insert(ObjectIdentifier(material)).inserted {
                    guard let original = material.diffuse.contents as? NSColor,
                          let rgb = original.usingColorSpace(.sRGB) else { continue }
                    let low = min(rgb.redComponent,rgb.greenComponent,rgb.blueComponent)
                    let high = max(rgb.redComponent,rgb.greenComponent,rgb.blueComponent)
                    guard low > 0.5, high < 0.94, high-low < 0.06 else { continue }
                    material.diffuse.contents = NSColor(srgbRed:rgb.redComponent*0.62,green:rgb.greenComponent*0.62,blue:rgb.blueComponent*0.62,alpha:rgb.alphaComponent)
                }
            }
        }
        let glass = try FoldRenderer()
        let wallpaper: CGImage
        if let file = options["--wallpaper"] {
            guard let image = NSImage(contentsOfFile:file), let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil) else { throw Failure.message("Cannot read wallpaper") }
            wallpaper = cg
        } else { wallpaper = try ExampleScreen.image(dark:appearance == "dark") }
        try glass.setImage(wallpaper)
        let renderer = SCNRenderer(device:glass.device,options:nil)
        renderer.scene = model.scene; renderer.pointOfView = model.camera
        model.scene.background.contents = NSColor.clear
        model.scene.lightingEnvironment.intensity = 1.4
        // Keep screenshot values display-referred: HDR tone mapping brightens even constant screen materials.
        model.camera.camera?.wantsHDR = false
        model.camera.camera?.exposureOffset = 0
        try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
        var frames:[String] = []
        var idleLift: CGFloat?
        for frame in 0..<count {
            try autoreleasepool {
                let progress = Double(frame)/Double(count-1)
                // Open over the first 85%; the final stretch lets the effect settle.
                let opening = min(1,progress/0.85)
                let eased = opening*opening*(3-2*opening)
                let angle = motion == "idle" ? 5*progress : 110*eased
                model.setAngle(angle)
                glass.foldDegrees = max(0,85*(1-angle/110))
                model.screenMaterial.diffuse.contents = try glass.renderOffscreen(width:wallpaper.width,height:Int(Double(wallpaper.width)/model.screenAspectRatio))
                // Fixed, centered camera: no lateral orbit or rotation during opening.
                model.camera.position = SCNVector3(0,2.4,6.9)
                model.camera.look(at:SCNVector3(0,0.82,0))
                let image = renderer.snapshot(atTime:Double(frame)/60,with:CGSize(width:width,height:height),antialiasingMode:.multisampling4X)
                // Composite after tone mapping so the site's white stays exactly white.
                guard let cg = image.cgImage(forProposedRect:nil,context:nil,hints:nil),
                      let context = CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Failure.message("Could not composite frame") }
                context.setFillColor(CGColor(colorSpace:context.colorSpace!,components:[CGFloat((rgb>>16)&255)/255,CGFloat((rgb>>8)&255)/255,CGFloat(rgb&255)/255,1])!);context.fill(CGRect(x:0,y:0,width:width,height:height))
                // Lift the closed device into the space directly below the introduction.
                // Keep a small, constant top margin without clipping the opening lid.
                let alpha = NSBitmapImageRep(cgImage:cg)
                var top = 0
                scan: for y in stride(from:0,to:height,by:2) {
                    for x in stride(from:0,to:width,by:4) {
                        if (alpha.colorAt(x:x,y:y)?.alphaComponent ?? 0) > 0.15 { top = y; break scan }
                    }
                }
                // Idle keeps the base stationary; reserve room for the five-degree lift.
                if motion == "idle", idleLift == nil { idleLift = CGFloat(max(0,top-160)) }
                let lift = idleLift ?? CGFloat(max(0,top-24))
                context.draw(cg,in:CGRect(x:0,y:lift,width:CGFloat(width),height:CGFloat(height)))
                guard let composited = context.makeImage(), let jpeg = NSBitmapImageRep(cgImage:composited).representation(using:format == "png" ? .png : .jpeg,properties:[.compressionFactor:0.94]) else { throw Failure.message("Could not encode frame") }
                let name = String(format:"frame-%03d",frame)+"."+format
                try jpeg.write(to:destination.appendingPathComponent(name));frames.append(name)
                if frame % 20 == 0 || frame == count-1 { print("Rendered \(frame+1)/\(count)") }
            }
        }
        // Only publish the manifest after every frame is present.
        let manifest:[String:Any] = ["schema":1,"motion":motion,"maximumAngle":motion == "idle" ? 5 : 110,"background":background,"camera":"symmetric-front","finish":finish,"model":"MacBook Air 13-inch","color":color.rawValue,"width":width,"height":height,"frames":frames,"poster":frames.last!,"wallpaper":options["--wallpaper"].map { URL(fileURLWithPath:$0).lastPathComponent } ?? "bundled screenshot (\(appearance))","source":configuration.assetURL.absoluteString]
        let json = try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys])
        try json.write(to:destination.appendingPathComponent("sequence.json"))
    }
    enum Failure: Error { case message(String) }
}
