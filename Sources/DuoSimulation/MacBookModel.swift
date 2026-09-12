import AppKit
import SceneKit

/// Studio and articulated laptop. Apple USDZ geometry is loaded on demand;
/// the procedural enclosure remains an explicit offline fallback.
/// World units are decimetres; proportions follow the 16-inch enclosure.
public final class MacBookModel {
    public let scene = SCNScene()
    public let hinge = SCNNode()
    public let product = SCNNode()
    public let bodyInteractionBounds = SCNNode()
    public let contactEdgeBounds = SCNNode()
    public let floatingShadow = SCNNode()
    public let screenMaterial = SCNMaterial()
    public private(set) var screenNode: SCNNode?
    public let camera = SCNNode()
    public private(set) var isOfficialModel = false
    public private(set) var screenAspectRatio: Double = 1.536
    private var cameraScale: CGFloat = 1
    private let metal = MacBookModel.material(NSColor(white: 0.38, alpha: 1), metalness: 0.9, roughness: 0.38)
    private let edge = MacBookModel.material(NSColor(white: 0.30, alpha: 1), metalness: 1, roughness: 0.22)
    private let black = MacBookModel.material(NSColor(white: 0.012, alpha: 1), metalness: 0.12, roughness: 0.4)

    public init() {
        buildStudio()
        buildChassis()
        buildKeyboard()
        buildDisplay()
        groupProduct()
        addFloatingShadow(width: 3.557)
        resetCamera()
        setAngle(110)
    }
    public init(assetURL: URL, configuration: MacBookConfiguration) throws {
        buildStudio()
        let imported = try SCNScene(url:assetURL,options:[.checkConsistency:true])
        let root = imported.rootNode
        // Apple's emissive display mesh is separate from the glass, bezel and camera.
        var screens: [SCNNode] = []
        root.enumerateChildNodes { node,_ in
            guard let geometry = node.geometry else { return }
            let bounds = node.boundingBox
            if bounds.max.x-bounds.min.x > 20,
               geometry.materials.contains(where: { $0.emission.contents is URL }) { screens.append(node) }
        }
        guard screens.count == 1, let display = screens.first else { throw AppleModelCache.ModelError.geometry }
        var lid = display
        // Neo and the 2026 Sky Blue Air have an authored joint; older Air and Pro bake the open pose into vertices.
        var ancestor = display.parent
        var nativeJoint: SCNNode?
        while let node = ancestor, node !== root {
            if node.eulerAngles.x < -1 { nativeJoint = node; break }
            ancestor = node.parent
        }
        var pivot: SCNVector3
        if let joint = nativeJoint {
            lid = joint; pivot = joint.convertPosition(.init(0,0,0),to:root)
        } else {
            // In the pinned Pro assets, all lid parts share a group entirely behind the chassis.
            while let parent = lid.parent, parent !== root, parent.boundingBox.max.z < -5 { lid = parent }
            guard lid !== display else { throw AppleModelCache.ModelError.geometry }
            if configuration.family == .air {
                // Centimetres in the source root, measured from Apple's authored Sky Blue joints.
                // A Pro pivot places the older Air lid below its keyboard when closed.
                pivot = configuration.size == 13 ? SCNVector3(0,-0.108489,-10.506382) : SCNVector3(0,-0.293,-11.633058)
            } else {
                pivot = configuration.size == 14 ? SCNVector3(0,-0.090,-10.767) : SCNVector3(0,-0.115,-12.10)
            }
        }
        let carrier = SCNNode()
        // USD centimetres -> the studio's decimetres. Keep real relative sizes across models.
        carrier.scale = SCNVector3(0.1,0.1,0.1)
        scene.rootNode.addChildNode(carrier); carrier.addChildNode(root)
        let oldTransform = lid.simdWorldTransform
        hinge.position = pivot; root.addChildNode(hinge)
        let closedPose = SCNNode(); closedPose.eulerAngles.x = 110 * .pi / 180
        // Reparent with the original world transform before rotating to the closed reference pose.
        hinge.addChildNode(closedPose)
        closedPose.eulerAngles.x = 0
        lid.removeFromParentNode(); closedPose.addChildNode(lid)
        lid.simdTransform = simd_inverse(closedPose.simdWorldTransform) * oldTransform
        closedPose.eulerAngles.x = 110 * .pi / 180
        // Pinned Pro 16, Sky Blue Air and Neo assets contain a static AR occlusion shell.
        // Exclude shells spanning the open display; they must not affect picking/contact bounds
        // or leave a ghost after articulating the real lid. Stationary chassis parts are <5 cm tall.
        root.enumerateChildNodes { node,_ in
            guard node.geometry != nil, !node.isDescendant(of:lid) else { return }
            let b = node.boundingBox
            let top = [b.min.y,b.max.y].flatMap { y in [b.min.z,b.max.z].map { z in
                node.convertPosition(SCNVector3(0,y,z),to:root).y
            } }.max() ?? 0
            if top > 5 { node.isHidden = true }
        }
        setAngle(110)
        carrier.position.y = -root.boundingBox.min.y * 0.1
        screenMaterial.lightingModel = .constant
        screenMaterial.diffuse.contents = NSColor.black
        screenMaterial.diffuse.minificationFilter = .linear
        screenMaterial.diffuse.magnificationFilter = .linear
        screenMaterial.diffuse.maxAnisotropy = 8
        display.geometry = display.geometry?.copy() as? SCNGeometry
        display.geometry?.materials = [screenMaterial]
        screenNode = display
        let screenBounds = display.boundingBox
        screenAspectRatio = Double((screenBounds.max.x-screenBounds.min.x) / hypot(screenBounds.max.y-screenBounds.min.y,screenBounds.max.z-screenBounds.min.z))
        cameraScale = configuration.family == .pro && configuration.size == 16 ? 1 : 0.91
        scene.lightingEnvironment.intensity = 0.45
        camera.camera?.exposureOffset = -0.65
        for node in scene.rootNode.childNodes { if let light = node.light { light.intensity *= 0.55 } }
        groupProduct()
        addFloatingShadow(width: bodyInteractionBounds.boundingBox.max.x-bodyInteractionBounds.boundingBox.min.x)
        isOfficialModel = true
        resetCamera()
    }
    public func setAngle(_ angle: Double) {
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        hinge.eulerAngles.x = CGFloat(-min(130, max(0, angle)) * .pi / 180)
        SCNTransaction.commit()
    }
    public func resetCamera() {
        camera.position = SCNVector3(0, 1.2*cameraScale, 8*cameraScale)
        camera.look(at: SCNVector3(0, 0.95*cameraScale, 0))
    }
    private func groupProduct() {
        for node in scene.rootNode.childNodes where node.camera == nil && node.light == nil {
            node.removeFromParentNode(); product.addChildNode(node)
        }
        scene.rootNode.addChildNode(product)
        // Fixed bounds for the base, excluding Apple's invisible AR occlusion meshes.
        setAngle(0)
        var lower = SCNVector3(CGFloat.infinity,CGFloat.infinity,CGFloat.infinity)
        var upper = SCNVector3(-CGFloat.infinity,-CGFloat.infinity,-CGFloat.infinity)
        func collect(_ node: SCNNode, excludingLid: Bool = false) {
            guard !node.isHidden, !(excludingLid && node === hinge) else { return }
            if node.geometry != nil {
                let b = node.boundingBox
                for x in [b.min.x,b.max.x] { for y in [b.min.y,b.max.y] { for z in [b.min.z,b.max.z] {
                    let p = node.convertPosition(SCNVector3(x,y,z),to:product)
                    lower = SCNVector3(min(lower.x,p.x),min(lower.y,p.y),min(lower.z,p.z))
                    upper = SCNVector3(max(upper.x,p.x),max(upper.y,p.y),max(upper.z,p.z))
                } } }
            }
            for child in node.childNodes { collect(child,excludingLid:excludingLid) }
        }
        collect(product)
        bodyInteractionBounds.boundingBox = (lower,upper)
        product.addChildNode(bodyInteractionBounds)
        // Rotated lid AABBs are deliberately generous for dragging but unsuitable for particles.
        // Use only the stationary base for the visual contact line.
        lower = SCNVector3(CGFloat.infinity,CGFloat.infinity,CGFloat.infinity)
        upper = SCNVector3(-CGFloat.infinity,-CGFloat.infinity,-CGFloat.infinity)
        collect(product,excludingLid:true)
        contactEdgeBounds.boundingBox = (lower,upper)
        product.addChildNode(contactEdgeBounds)
        setAngle(110)
    }
    public func setFloatingOffset(_ offset: Double, impactOffset: Double = 0) {
        let height = CGFloat(max(0,min(ClosedLidFloat.maximumOffset,offset)))
        let floatFraction = height/CGFloat(ClosedLidFloat.maximumOffset)
        let displacement = height+CGFloat(max(-0.1,min(0.025,impactOffset)))
        let fraction = displacement/CGFloat(ClosedLidFloat.maximumOffset)
        SCNTransaction.begin(); SCNTransaction.disableActions = true
        product.position.y = displacement
        // A small pitch changes the visible depth without orbiting the fixed front camera.
        product.eulerAngles.x = -floatFraction * 0.65 * .pi / 180
        // Widening a Gaussian penumbra softens its edge; reduced alpha keeps it diffuse.
        // The shadow's position stays fixed while its distance from the enclosure changes.
        floatingShadow.scale = SCNVector3(1+fraction*0.08,1+fraction*0.22,1)
        floatingShadow.opacity = min(1,0.78*(1-fraction*0.22))
        SCNTransaction.commit()
    }

    /// A transparent, baked penumbra: no floor, live shadow pass or opaque backdrop.
    private func addFloatingShadow(width: CGFloat) {
        let size = 256
        var pixels = [UInt8](repeating: 0, count: size*size*4)
        for y in 0..<size {
            for x in 0..<size {
                let u = (Double(x)+0.5)/Double(size)*2-1
                let v = (Double(y)+0.5)/Double(size)*2-1
                let edge = max(0, 1-pow(u*u+v*v, 2))
                let alpha = (0.24/0.78) * exp(-2.8*u*u-4.5*v*v) * edge
                pixels[(y*size+x)*4+3] = UInt8(max(0, min(255, alpha*255)))
            }
        }
        let data = Data(pixels) as CFData
        guard let provider = CGDataProvider(data: data),
              let image = CGImage(width:size, height:size, bitsPerComponent:8, bitsPerPixel:32,
                bytesPerRow:size*4, space:CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
                provider:provider, decode:nil, shouldInterpolate:true, intent:.defaultIntent) else { return }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = image
        material.writesToDepthBuffer = false
        material.isDoubleSided = true
        let plane = SCNPlane(width:width*1.24, height:0.34)
        plane.materials = [material]
        let shadow = floatingShadow
        shadow.geometry = plane
        shadow.name = "Floating shadow"
        shadow.opacity = 0.78
        shadow.position = SCNVector3(0,-0.03,0.8)
        shadow.castsShadow = false
        scene.rootNode.addChildNode(shadow)
    }

    private static func material(_ color: NSColor, metalness: CGFloat = 0, roughness: CGFloat = 0.5) -> SCNMaterial {
        let m = SCNMaterial(); m.lightingModel = .physicallyBased
        m.diffuse.contents = color; m.metalness.contents = metalness; m.roughness.contents = roughness
        return m
    }
    @discardableResult
    private func box(_ width: CGFloat, _ height: CGFloat, _ depth: CGFloat, radius: CGFloat,
                     at position: SCNVector3, material: SCNMaterial, parent: SCNNode? = nil) -> SCNNode {
        let geometry = SCNBox(width: width, height: height, length: depth, chamferRadius: radius)
        geometry.chamferSegmentCount = 5; geometry.materials = [material]
        let node = SCNNode(geometry: geometry); node.position = position
        (parent ?? scene.rootNode).addChildNode(node)
        return node
    }
    private func buildStudio() {
        scene.background.contents = NSColor.clear
        // The HDR lights the aluminium but is never drawn as a backdrop.
        if let environment = Bundle.module.url(forResource: "studio_small_09_1k", withExtension: "hdr") {
            scene.lightingEnvironment.contents = environment
            scene.lightingEnvironment.intensity = 0.75
        }
        camera.camera = SCNCamera()
        camera.camera?.projectionDirection = .horizontal
        camera.camera?.fieldOfView = 36
        // The fixed studio camera keeps the whole enclosure between 4 and 12 units away.
        // A tight depth range preserves precision at the thin lid and chassis seams.
        camera.camera?.zNear = 1; camera.camera?.zFar = 20
        camera.camera?.wantsHDR = true; camera.camera?.wantsExposureAdaptation = false
        camera.camera?.exposureOffset = 0.1
        camera.camera?.screenSpaceAmbientOcclusionIntensity = 0.55
        camera.camera?.screenSpaceAmbientOcclusionRadius = 0.14
        camera.camera?.screenSpaceAmbientOcclusionBias = 0.015
        scene.rootNode.addChildNode(camera)
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional
        key.light?.intensity = 450; key.light?.temperature = 5700
        key.light?.castsShadow = true; key.light?.shadowRadius = 7
        key.light?.shadowSampleCount = 32; key.light?.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.light?.shadowColor = NSColor.black.withAlphaComponent(0.22)
        key.position = SCNVector3(-3, 6, 4); key.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(key)
        let fill = SCNNode(); fill.light = SCNLight(); fill.light?.type = .omni
        fill.light?.intensity = 100; fill.light?.temperature = 7000
        fill.position = SCNVector3(4, 3, -3); scene.rootNode.addChildNode(fill)
    }
    @discardableResult
    private func plate(_ width: CGFloat, _ height: CGFloat, _ depth: CGFloat, corner: CGFloat, bevel: CGFloat,
                       at position: SCNVector3, material: SCNMaterial, parent: SCNNode? = nil) -> SCNNode {
        let path = NSBezierPath(roundedRect:NSRect(x:-width/2,y:-depth/2,width:width,height:depth),xRadius:corner,yRadius:corner)
        path.flatness = 0.001
        let shape = SCNShape(path:path,extrusionDepth:height)
        shape.chamferRadius = bevel; shape.chamferMode = .both
        shape.materials = [material]
        let node = SCNNode(geometry:shape); node.eulerAngles.x = -.pi/2; node.position = position
        (parent ?? scene.rootNode).addChildNode(node)
        return node
    }
    private func buildChassis() {
        plate(3.557,0.108,2.481,corner:0.095,bevel:0.012,at:SCNVector3(0,0.058,0),material:metal)
        plate(3.49,0.006,2.41,corner:0.08,bevel:0.001,at:SCNVector3(0,0.113,0),material:metal)
        // Bottom-case seam and rubber feet.
        plate(3.48,0.003,2.40,corner:0.08,bevel:0.001,at:SCNVector3(0,0.026,0),material:edge)
        for x in [-1.40, 1.40] {
            for z in [-0.90, 0.90] {
                let foot = SCNCylinder(radius: 0.115, height: 0.018); foot.radialSegmentCount = 32
                foot.firstMaterial = black
                let node = SCNNode(geometry: foot); node.position = SCNVector3(x, 0.002, z)
                scene.rootNode.addChildNode(node)
            }
        }
        // Finger recess on the front lip and the glass trackpad with its hairline seam.
        box(0.43, 0.015, 0.025, radius: 0.006, at: SCNVector3(0, 0.109, 1.229), material: edge)
        plate(1.52,0.004,0.90,corner:0.035,bevel:0.001,at:SCNVector3(0,0.117,0.68),material:edge)
        let trackpad = Self.material(NSColor(white: 0.43, alpha: 1), metalness: 0.65, roughness: 0.36)
        plate(1.505,0.004,0.885,corner:0.03,bevel:0.001,at:SCNVector3(0,0.119,0.68),material:trackpad)
        // Machined side openings: MagSafe, Thunderbolt, headphone, HDMI and SD.
        for (side, z, length) in [(-1.0,-0.96,0.19),(-1,-0.67,0.105),(-1,-0.43,0.105),
                                   (-1,-0.15,0.065),(1,-0.94,0.19),(1,-0.61,0.105),(1,-0.25,0.25)] {
            box(0.012, 0.047, length, radius: 0.006, at: SCNVector3(side*1.776,0.065,z), material: edge)
            box(0.013, 0.034, length-0.018, radius: 0.005, at: SCNVector3(side*1.778,0.065,z), material: black)
        }
        let barrel = SCNCylinder(radius: 0.045, height: 3.05); barrel.radialSegmentCount = 48
        barrel.firstMaterial = black
        let cylinder = SCNNode(geometry: barrel); cylinder.eulerAngles.z = .pi/2
        cylinder.position = SCNVector3(0,0.132,-1.17); scene.rootNode.addChildNode(cylinder)
        hinge.position = SCNVector3(0,0.148,-1.18); scene.rootNode.addChildNode(hinge)
    }
    private func buildKeyboard() {
        box(2.78, 0.006, 1.12, radius: 0.003, at: SCNVector3(0,0.117,-0.42), material: black)
        let rows: [[(String, Double)]] = [
            [("esc",1.2)] + (1...12).map { ("F\($0)",0.9) } + [("◉",1.2)],
            [("`",1),("1",1),("2",1),("3",1),("4",1),("5",1),("6",1),("7",1),("8",1),("9",1),("0",1),("−",1),("=",1),("delete",1.4)],
            [("tab",1.4),("Q",1),("W",1),("E",1),("R",1),("T",1),("Y",1),("U",1),("I",1),("O",1),("P",1),("[",1),("]",1),("\\",1)],
            [("caps",1.7),("A",1),("S",1),("D",1),("F",1),("G",1),("H",1),("J",1),("K",1),("L",1),(";",1),("'",1),("return",1.7)],
            [("shift",2.2),("Z",1),("X",1),("C",1),("V",1),("B",1),("N",1),("M",1),(",",1),(".",1),("/",1),("shift",2.2)],
            [("fn",1),("⌃",1),("⌥",1),("⌘",1.25),("",5.1),("⌘",1.25),("⌥",1),("◀",0.9),("▲\n▼",0.9),("▶",0.9)]
        ]
        for (row, keys) in rows.enumerated() {
            let unit = 2.70 / keys.reduce(0) { $0 + $1.1 }
            var x = -1.35
            for (label, weight) in keys {
                let width = unit*weight - 0.022
                let height = row == 0 ? 0.115 : 0.148
                let top = Self.material(NSColor(white: 0.018, alpha: 1), roughness: 0.72)
                top.diffuse.contents = Self.keyTexture(label)
                let node = box(width,0.016,height,radius:0.006,
                    at:SCNVector3(x+unit*weight/2,0.126,-0.91+Double(row)*0.183),material:black)
                node.geometry?.materials = [black,black,black,black,top,black]
                x += unit*weight
            }
        }
        let speaker = Self.material(.black, metalness: 0.4, roughness: 0.5)
        speaker.diffuse.contents = Self.speakerTexture()
        for x in [-1.545, 1.545] {
            let plane = SCNPlane(width: 0.21, height: 1.22); plane.firstMaterial = speaker
            let node = SCNNode(geometry: plane); node.eulerAngles.x = -.pi/2
            node.position = SCNVector3(x,0.119,-0.36); scene.rootNode.addChildNode(node)
        }
    }
    private func buildDisplay() {
        plate(3.557,0.037,2.405,corner:0.075,bevel:0.004,at:SCNVector3(0,0,1.2025),material:metal,parent:hinge)
        plate(3.48,0.006,2.33,corner:0.06,bevel:0.001,at:SCNVector3(0,-0.020,1.2025),material:black,parent:hinge)
        let screen = SCNPlane(width: 3.35, height: 2.175); screen.cornerRadius = 0.027
        // Constant shading preserves the Metal output rather than lighting the pixels twice.
        screenMaterial.lightingModel = .constant; screenMaterial.diffuse.contents = NSColor.black
        screenMaterial.diffuse.magnificationFilter = .linear
        screenMaterial.diffuse.minificationFilter = .linear
        screenMaterial.diffuse.maxAnisotropy = 8
        screen.materials = [screenMaterial]
        let display = SCNNode(geometry: screen); display.eulerAngles.x = .pi/2
        display.position = SCNVector3(0,-0.024,1.225); hinge.addChildNode(display)
        screenNode = display
        box(0.35,0.004,0.067,radius:0.002,at:SCNVector3(0,-0.028,2.285),material:black,parent:hinge)
        let lens = SCNSphere(radius:0.007); lens.segmentCount = 16
        lens.firstMaterial = Self.material(NSColor(calibratedRed:0.015,green:0.04,blue:0.075,alpha:1),metalness:0.65,roughness:0.08)
        let webcam = SCNNode(geometry:lens); webcam.position = SCNVector3(0,-0.031,2.285); hinge.addChildNode(webcam)
        let logo = SCNPlane(width:0.39,height:0.43)
        let logoMaterial = Self.material(.black,metalness:0.9,roughness:0.13)
        logoMaterial.diffuse.contents = Self.logoTexture(); logoMaterial.transparencyMode = .aOne
        logo.firstMaterial = logoMaterial
        let apple = SCNNode(geometry:logo); apple.eulerAngles.x = -.pi/2
        apple.position = SCNVector3(0,0.0195,1.20); hinge.addChildNode(apple)
    }
    private static func keyTexture(_ text: String) -> NSImage {
        let size = NSSize(width:128,height:128)
        return NSImage(size:size,flipped:false) { rect in
            NSColor(white:0.026,alpha:1).setFill(); rect.fill()
            let font = NSFont.systemFont(ofSize:text.count > 2 ? 18 : 30,weight:.regular)
            let attributes: [NSAttributedString.Key:Any] = [.font:font,.foregroundColor:NSColor(white:0.84,alpha:1)]
            let label = text as NSString; let bounds = label.size(withAttributes:attributes)
            label.draw(at:NSPoint(x:(128-bounds.width)/2,y:(128-bounds.height)/2),withAttributes:attributes)
            return true
        }
    }
    private static func speakerTexture() -> NSImage {
        NSImage(size:NSSize(width:128,height:768),flipped:false) { rect in
            NSColor(white:0.39,alpha:1).setFill(); rect.fill()
            for row in 0..<100 { for column in 0..<15 {
                NSColor(white:0.045,alpha:1).setFill()
                NSBezierPath(ovalIn:NSRect(x:CGFloat(4+column*8),y:CGFloat(4+row*7),width:2.5,height:2.5)).fill()
            }}
            return true
        }
    }
    private static func logoTexture() -> NSImage {
        NSImage(size:NSSize(width:256,height:256),flipped:false) { _ in
            let attrs: [NSAttributedString.Key:Any] = [.font:NSFont.systemFont(ofSize:220),.foregroundColor:NSColor(white:0.08,alpha:1)]
            let text = "\u{f8ff}" as NSString; let size = text.size(withAttributes:attrs)
            text.draw(at:NSPoint(x:(256-size.width)/2,y:(256-size.height)/2),withAttributes:attrs)
            return true
        }
    }
}

private extension SCNNode {
    func isDescendant(of ancestor: SCNNode) -> Bool {
        var node: SCNNode? = self
        while let current = node { if current === ancestor { return true }; node = current.parent }
        return false
    }
}
