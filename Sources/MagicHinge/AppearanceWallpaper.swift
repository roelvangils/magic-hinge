import SwiftUI
import ImageIO
import DuoGraphics

/// Follow the effective window appearance: system changes in Auto, explicit app overrides otherwise.
struct AppearanceWallpaper: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    private static let hasStarlessNight = Bundle.module.url(forResource:"DuoNightStarless",withExtension:"jpg") != nil
    private static let day = load("DuoDay")
    private static let night = load(hasStarlessNight ? "DuoNightStarless" : "DuoNight")

    var body: some View {
        let motionReduced = reduceMotion
        return GeometryReader { geometry in
            ZStack {
                wallpaper(Self.day, size:geometry.size)
                wallpaper(Self.night, size:geometry.size)
                    .overlay {
                        if Self.hasStarlessNight, let night = Self.night {
                            ProceduralNightSky(imageSize:night.size,
                                animating:!reduceMotion && colorScheme == .dark && scenePhase == .active)
                        }
                    }
                    .opacity(colorScheme == .dark ? 1 : 0)
                    .animation(.easeInOut(duration:0.36),value:colorScheme)
            }
            .compositingGroup()
            .keyframeAnimator(initialValue:0.0,trigger:colorScheme) { content, radius in
                content.blur(radius:motionReduced ? 0 : radius)
            } keyframes: { _ in
                CubicKeyframe(8,duration:0.12)
                CubicKeyframe(0,duration:0.24)
            }
            .clipped()
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func wallpaper(_ image: NSImage?, size: CGSize) -> some View {
        if let image {
            Image(nsImage:image).resizable().scaledToFill()
                .frame(width:size.width,height:size.height).clipped()
        }
    }
    private static func load(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource:name,withExtension:"jpg"),
              let source = CGImageSourceCreateWithURL(url as CFURL,nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:4096,
                kCGImageSourceShouldCacheImmediately:true
              ] as CFDictionary) else { return nil }
        // Decode both versions once, before switching. Bound GPU texture size while keeping Retina detail.
        return NSImage(cgImage:image,size:NSSize(width:image.width,height:image.height))
    }
}
