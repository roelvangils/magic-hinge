import Foundation
import CryptoKit
import DuoCore

/// Apple assets remain in the user's cache, not in the source tree or distributable app.
public actor AppleModelCache {
    public static let shared = AppleModelCache()
    public let directory: URL
    private struct AssetRecord: Decodable { let url: String; let sha256: String }
    private static let records: [AssetRecord] = {
        guard let url = Bundle.module.url(forResource:"AppleModels",withExtension:"json"),
              let data = try? Data(contentsOf:url) else { return [] }
        return (try? JSONDecoder().decode([AssetRecord].self,from:data)) ?? []
    }()
    private func matches(_ data: Data, source: URL) -> Bool {
        guard let expected = Self.records.first(where:{ $0.url == source.absoluteString })?.sha256 else { return false }
        return SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined() == expected
    }
    public init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask)[0]
            .appendingPathComponent("be.elevenways.MacBookDuo/AppleModels",isDirectory:true)
    }
    public func modelURL(for configuration: MacBookConfiguration) async throws -> URL {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let source = configuration.assetURL
        let file = directory.appendingPathComponent(source.lastPathComponent)
        if let cached = try? Data(contentsOf:file,options:.mappedIfSafe), !matches(cached,source:source) {
            try FileManager.default.removeItem(at:file)
        }
        if !FileManager.default.fileExists(atPath:file.path) {
            var request = URLRequest(url:source); request.timeoutInterval = 60
            let (temporary,response) = try await URLSession.shared.download(for:request)
            defer { try? FileManager.default.removeItem(at:temporary) }
            try Task.checkCancellation()
            guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                  response.url?.scheme == "https", response.url?.host == "www.apple.com" else {
                throw ModelError.download
            }
            let data = try Data(contentsOf:temporary,options:.mappedIfSafe)
            guard data.count > 100_000, data.count < 100_000_000, data.prefix(4) == Data([0x50,0x4b,0x03,0x04]) else { throw ModelError.download }
            guard matches(data,source:source) else { throw ModelError.geometry }
            // Another window/task may have completed the same download while this actor awaited it.
            if !FileManager.default.fileExists(atPath:file.path) { try data.write(to:file,options:.atomic) }
        }
        try Task.checkCancellation()
        guard configuration.usesColorVariant else { return file }
        let wrapper = directory.appendingPathComponent("\(configuration.family.rawValue)-\(configuration.size)-\(configuration.color.rawValue).usda")
        // A local USD composition selects Apple's authored materials. No recolouring approximations.
        let layer = """
        #usda 1.0
        (defaultPrim = "Model"
        metersPerUnit = 0.01
        upAxis = "Y")
        def Xform "Model" (
            prepend references = @./\(source.lastPathComponent)@
            variants = { string Color = "\(configuration.color.variant)" }
        ) {}
        """
        try layer.write(to:wrapper,atomically:true,encoding:.utf8)
        return wrapper
    }
    public enum ModelError: LocalizedError {
        case download, geometry
        public var errorDescription: String? {
            switch self { case .download: L10n.text("The Apple model could not be downloaded. Check your connection and try again.")
            case .geometry: L10n.text("This Apple model has an unexpected structure. The simulator cannot safely control its hinge.") }
        }
    }
}
