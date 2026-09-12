import DuoCore
import Foundation
import IOKit

public enum MacBookFamily: String, CaseIterable, Codable, Sendable {
    case air, pro, neo
    public var title: String { "MacBook " + rawValue.capitalized }
    public var sizes: [Int] { switch self { case .air: [13,15]; case .pro: [14,16]; case .neo: [13] } }
    public var colors: [MacBookColor] {
        switch self { case .air: [.skyBlue,.silver,.starlight,.midnight]; case .pro: [.spaceBlack,.silver]; case .neo: [.silver,.blush,.citrus,.indigo] }
    }
    public var colorChoices: [MacBookColorChoice] {
        (self == .pro ? [.system] : []) + colors.map(MacBookColorChoice.fixed)
    }
}
public enum MacBookColor: String, CaseIterable, Codable, Sendable {
    case silver, spaceBlack, skyBlue, starlight, midnight, blush, citrus, indigo
    public var title: String {
        switch self { case .silver: L10n.text("Silver"); case .spaceBlack: L10n.text("Space Black"); case .skyBlue: L10n.text("Sky Blue"); case .starlight: L10n.text("Starlight"); case .midnight: L10n.text("Midnight"); case .blush: L10n.text("Blush"); case .citrus: L10n.text("Citrus"); case .indigo: L10n.text("Indigo") }
    }
    var variant: String { self == .spaceBlack ? "Space_Black" : rawValue.capitalized }
    var filename: String { self == .skyBlue ? "sky-blue" : rawValue }
}

/// A preference stays automatic even when the resolved asset colour changes.
public enum MacBookColorChoice: Hashable, Sendable {
    case system
    case fixed(MacBookColor)

    public var title: String {
        switch self { case .system: L10n.text("Follow system appearance"); case .fixed(let color): color.title }
    }

    public init(storedValue: String?, fallback: MacBookColor) {
        if storedValue == "system" { self = .system }
        else { self = .fixed(storedValue.flatMap(MacBookColor.init(rawValue:)) ?? fallback) }
    }
    public var storedValue: String {
        switch self { case .system: "system"; case .fixed(let color): color.rawValue }
    }
    public func resolved(for family: MacBookFamily, dark: Bool) -> MacBookColor {
        switch self {
        case .system: return family == .pro && dark ? .spaceBlack : .silver
        case .fixed(let color): return family.colors.contains(color) ? color : family.colors[0]
        }
    }
}
public struct MacBookConfiguration: Codable, Equatable, Sendable {
    public let family: MacBookFamily
    public let size: Int
    public let color: MacBookColor
    public init(family: MacBookFamily, size: Int, color: MacBookColor) {
        self.family = family
        self.size = family.sizes.contains(size) ? size : family.sizes[0]
        self.color = family.colors.contains(color) ? color : family.colors[0]
    }
    public var title: String { "\(family.title) \(size)″" }
    public var assetURL: URL {
        let root = "https://www.apple.com/105/media/us/"
        let path: String
        switch family {
        case .neo: path = "macbook-neo/2026/eee281c9-06d4-45d9-9a37-ef16ad413279/ar/macbook-neo.usdz"
        case .pro where size == 14:
            path = "macbook-pro/2025/785e1bc4-d1bd-4cf4-b1b3-94b9411c9e74/ar/macbook-pro-14-in-space-black-variant.usdz"
        case .pro:
            path = "macbook-pro/2023/232a2dbf-5898-4fd1-a350-6a7c5c2e31c9/ar/macbook_pro_m3_pro_16_\(color == .silver ? "silver" : "space_black").usdz"
        case .air:
            let release = color == .skyBlue ? "2026/ff11cb38-708e-4c28-9653-1b01a2f8fd2b" : "2025/0833fe28-c438-4dc4-8edc-e39ef30df5f9"
            path = "macbook-air/\(release)/ar/macbook-air-\(size)in-\(color.filename).usdz"
        }
        return URL(string:root+path)!
    }
    public var usesColorVariant: Bool { family == .neo || (family == .pro && size == 14) }
    public var sourceDescription: String {
        family == .pro && size == 16 ? L10n.text("Apple 3D model · 16-inch M3 Pro enclosure (2023)") : L10n.text("Apple 3D model · original geometry and materials")
    }
    /// Product names come from IODeviceTree, without reading serial numbers or UUIDs.
    /// Unknown sizes deliberately stay unknown instead of silently choosing the wrong enclosure.
    public static func detected(productName: String) -> MacBookConfiguration? {
        let name = productName.lowercased()
        guard let family = MacBookFamily.allCases.first(where: { name.contains($0.title.lowercased()) }) else { return nil }
        let size = family.sizes.first { name.contains("\($0)-inch") || name.contains("\($0) inch") || name.contains("\($0)\"") }
        guard let size = size ?? (family == .neo ? 13 : nil) else { return nil }
        return Self(family:family,size:size,color:family.colors[0])
    }
    public static var currentProductName: String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/product")
        guard entry != 0 else { return nil }; defer { IOObjectRelease(entry) }
        guard let value = IORegistryEntryCreateCFProperty(entry,"product-name" as CFString,kCFAllocatorDefault,0)?.takeRetainedValue() else { return nil }
        if let data = value as? Data { return String(data:data,encoding:.utf8)?.trimmingCharacters(in:.controlCharacters) }
        return value as? String
    }
}
