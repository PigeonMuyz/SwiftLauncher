import Foundation

actor MojangMetadataService {
    static let manifestURL = URL(
        string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json"
    )!

    private let http: PublicHTTPClient

    init(http: PublicHTTPClient = .shared) {
        self.http = http
    }

    func fetchManifest() async throws -> VersionManifest {
        try await fetch(VersionManifest.self, from: Self.manifestURL)
    }

    func fetchMetadata(for version: MinecraftVersion) async throws -> VersionMetadata {
        let data = try await http.data(from: version.url)
        if !version.sha1.isEmpty, Hashing.sha1(data) != version.sha1.lowercased() {
            throw LauncherError.checksumMismatch("\(version.id).json")
        }
        return try JSONCoding.makeDecoder().decode(VersionMetadata.self, from: data)
    }

    private func fetch<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        let data = try await http.data(from: url)
        return try JSONCoding.makeDecoder().decode(T.self, from: data)
    }

    nonisolated static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw LauncherError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw LauncherError.httpStatus(http.statusCode)
        }
    }
}
