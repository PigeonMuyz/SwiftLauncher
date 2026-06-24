import Foundation

enum DownloadEndpointResolver {
    nonisolated static let defaultsKey = "downloadSource"
    nonisolated static let bmclBase = URL(string: "https://bmclapi2.bangbang93.com")!

    nonisolated static var selectedSource: DownloadSource {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let source = DownloadSource(rawValue: rawValue) else {
            return .automatic
        }
        return source
    }

    nonisolated static func candidates(for url: URL) -> [URL] {
        guard let mirror = bmclURL(for: url), mirror != url else { return [url] }
        switch selectedSource {
        case .automatic:
            return [url, mirror]
        case .official:
            return [url]
        case .bmclapi:
            return [mirror, url]
        }
    }

    nonisolated static func bmclURL(for url: URL) -> URL? {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return nil }
        let path = url.path

        switch host {
        case "piston-meta.mojang.com", "launchermeta.mojang.com":
            return append(path: path, query: url.query, to: bmclBase)

        case "piston-data.mojang.com", "launcher.mojang.com":
            return append(path: path, query: url.query, to: bmclBase)

        case "resources.download.minecraft.net":
            return append(path: "/assets\(path)", query: url.query, to: bmclBase)

        case "libraries.minecraft.net", "maven.minecraftforge.net":
            let relativePath = path.hasPrefix("/maven/")
                ? String(path.dropFirst("/maven".count))
                : path
            return append(path: "/maven\(relativePath)", query: url.query, to: bmclBase)

        case "files.minecraftforge.net":
            guard let range = path.range(of: "/maven/") else { return nil }
            return append(
                path: "/maven/\(path[range.upperBound...])",
                query: url.query,
                to: bmclBase
            )

        default:
            return nil
        }
    }

    nonisolated private static func append(path: String, query: String?, to base: URL) -> URL? {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = path
        components?.percentEncodedQuery = query
        return components?.url
    }
}
