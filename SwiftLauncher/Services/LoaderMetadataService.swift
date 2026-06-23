import Foundation

actor LoaderMetadataService {
    private let http: PublicHTTPClient

    init(http: PublicHTTPClient = .shared) {
        self.http = http
    }

    func versions(for gameVersion: String, loader: ModLoader) async throws -> [LoaderVersionInfo] {
        if loader == .forge || loader == .neoForge {
            return try await mavenVersions(for: gameVersion, loader: loader)
        }
        guard let url = endpoint(loader: loader, gameVersion: gameVersion) else { return [] }
        let data = try await http.data(from: url)
        let entries = try JSONCoding.makeDecoder().decode([LoaderVersionEnvelope].self, from: data)
        return entries.map {
            LoaderVersionInfo(version: $0.loader.version, stable: $0.loader.stable)
        }
    }

    func profile(
        for gameVersion: String,
        loader: ModLoader,
        loaderVersion: String
    ) async throws -> LoaderProfile {
        guard let base = endpoint(loader: loader, gameVersion: gameVersion) else {
            throw LauncherError.unsupported("原版不需要加载器配置")
        }
        let url = base
            .appendingPathComponent(loaderVersion)
            .appendingPathComponent("profile")
            .appendingPathComponent("json")
        return try JSONCoding.makeDecoder().decode(
            LoaderProfile.self,
            from: try await http.data(from: url)
        )
    }

    private func endpoint(loader: ModLoader, gameVersion: String) -> URL? {
        let base: URL
        switch loader {
        case .vanilla:
            return nil
        case .fabric:
            base = URL(string: "https://meta.fabricmc.net/v2/versions/loader")!
        case .quilt:
            base = URL(string: "https://meta.quiltmc.org/v3/versions/loader")!
        case .forge, .neoForge:
            return nil
        }
        return base.appendingPathComponent(gameVersion)
    }

    private func mavenVersions(for gameVersion: String, loader: ModLoader) async throws -> [LoaderVersionInfo] {
        let url: URL
        let prefix: String
        switch loader {
        case .forge:
            url = URL(string: "https://maven.minecraftforge.net/net/minecraftforge/forge/maven-metadata.xml")!
            prefix = "\(gameVersion)-"
        case .neoForge:
            url = URL(string: "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml")!
            let pieces = gameVersion.split(separator: ".")
            guard pieces.count >= 2 else { return [] }
            let minor = pieces.count >= 3 ? String(pieces[2]) : "0"
            prefix = "\(pieces[1]).\(minor)."
        default:
            return []
        }

        let xml = String(decoding: try await http.data(from: url), as: UTF8.self)
        let expression = try NSRegularExpression(pattern: "<version>([^<]+)</version>")
        let range = NSRange(xml.startIndex..., in: xml)
        return expression.matches(in: xml, range: range)
            .compactMap { match -> String? in
                guard let versionRange = Range(match.range(at: 1), in: xml) else { return nil }
                let value = String(xml[versionRange])
                return value.hasPrefix(prefix) ? value : nil
            }
            .reversed()
            .map { LoaderVersionInfo(version: $0, stable: !$0.localizedCaseInsensitiveContains("beta")) }
    }
}

private struct LoaderVersionEnvelope: Decodable {
    let loader: Loader

    struct Loader: Decodable {
        let version: String
        let stable: Bool?
    }
}
