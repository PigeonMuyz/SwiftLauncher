import Foundation

/// Public, read-only transport for Mojang metadata and game files.
/// URLSession is preferred; curl is a compatibility fallback for macOS VPNs
/// that break Network.framework's TLS/HTTP3 handshake.
actor PublicHTTPClient {
    static let shared = PublicHTTPClient()

    private let session: URLSession
    private var preferCurl = false

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.httpShouldUsePipelining = false
        session = URLSession(configuration: configuration)
    }

    func data(from url: URL) async throws -> Data {
        if preferCurl {
            return try await curl(url)
        }

        do {
            let (data, response) = try await session.data(from: url)
            try MojangMetadataService.validate(response)
            return data
        } catch {
            guard url.scheme == "https" else { throw error }
            let result = try await curl(url)
            preferCurl = true
            return result
        }
    }

    private func curl(_ url: URL) async throws -> Data {
        try await Task.detached(priority: .utility) {
            try ProcessRunner.runData(
                executable: URL(fileURLWithPath: "/usr/bin/curl"),
                arguments: [
                    "--proto", "=https",
                    "--tlsv1.2",
                    "-LfsS",
                    "--retry", "2",
                    "--connect-timeout", "30",
                    "--max-time", "300",
                    url.absoluteString
                ]
            )
        }.value
    }
}
