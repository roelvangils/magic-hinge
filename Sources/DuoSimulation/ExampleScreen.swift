import AppKit
import ImageIO

/// Shared screen artwork for the simulator, onboarding and website renders.
/// Decode the original PNGs once; selecting appearance never captures a desktop.
public enum ExampleScreen {
    private static let light = load("light")
    private static let dark = load("dark")

    public static func image(dark appearanceIsDark: Bool) throws -> CGImage {
        guard let image = appearanceIsDark ? dark : light else {
            throw NSError(domain:"MagicHinge.ExampleScreen",code:1,userInfo:[NSLocalizedDescriptionKey:"The bundled example screenshot could not be loaded."])
        }
        return image
    }

    private static func load(_ name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource:name,withExtension:"png",subdirectory:"ExampleScreens"),
              let source = CGImageSourceCreateWithURL(url as CFURL,nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source,0,[kCGImageSourceShouldCacheImmediately:true] as CFDictionary)
    }
}
