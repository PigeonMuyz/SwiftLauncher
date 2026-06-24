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

    func data(from url: URL, headers: [String: String] = [:]) async throws -> Data {
        var lastError: Error = LauncherError.invalidResponse
        var lastCandidate = url
        for candidate in DownloadEndpointResolver.candidates(for: url) {
            lastCandidate = candidate
            do {
                return try await request(candidate, headers: headers)
            } catch {
                lastError = error
            }
        }
        let reason = (lastError as? LocalizedError)?.errorDescription ?? lastError.localizedDescription
        throw LauncherError.requestFailed(lastCandidate.absoluteString, reason)
    }

    private func request(_ url: URL, headers: [String: String]) async throws -> Data {
        if preferCurl {
            return try await curl(url, headers: headers)
        }

        var request = URLRequest(url: url)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        do {
            let (data, response) = try await session.data(for: request)
            try MojangMetadataService.validate(response)
            return data
        } catch {
            guard url.scheme == "https" else { throw error }
            let result = try await curl(url, headers: headers)
            preferCurl = true
            return result
        }
    }

    private func curl(_ url: URL, headers: [String: String]) async throws -> Data {
        try await Task.detached(priority: .utility) {
            let headerArguments = headers.flatMap { ["-H", "\($0.key): \($0.value)"] }
            return try ProcessRunner.runData(
                executable: URL(fileURLWithPath: "/usr/bin/curl"),
                arguments: [
                    "--proto", "=https",
                    "--tlsv1.2",
                    "-LfsS",
                    "--retry", "2",
                    "--connect-timeout", "30",
                    "--max-time", "300"
                ] + headerArguments + [
                    url.absoluteString
                ]
            )
        }.value
    }
}
