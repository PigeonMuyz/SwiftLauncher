import Foundation

/// Public, read-only transport for Mojang metadata and game files.
/// URLSession is preferred; curl is a compatibility fallback for macOS VPNs
/// that break Network.framework's TLS/HTTP3 handshake.
actor PublicHTTPClient {
    static let shared = PublicHTTPClient()

    private let session: URLSession
    private var sessionCooldowns: [String: Date] = [:]
    private let sessionCooldownInterval: TimeInterval = 300

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.httpShouldUsePipelining = false
        session = URLSession(configuration: configuration)
    }

    func data(from url: URL, headers: [String: String] = [:]) async throws -> Data {
        var lastError: Error = LauncherError.invalidResponse
        var lastCandidate = url
        let candidates = orderedCandidates(for: DownloadEndpointResolver.candidates(for: url))

        for candidate in candidates where !sessionIsCoolingDown(for: candidate) {
            lastCandidate = candidate
            do {
                let data = try await request(candidate, headers: headers)
                markSessionSuccess(for: candidate)
                return data
            } catch {
                lastError = error
                markSessionFailureIfNeeded(for: candidate, error: error)
            }
        }

        for candidate in candidates where candidate.scheme == "https" {
            lastCandidate = candidate
            do {
                return try await curl(candidate, headers: headers)
            } catch {
                lastError = error
            }
        }
        let reason = (lastError as? LocalizedError)?.errorDescription ?? lastError.localizedDescription
        throw LauncherError.requestFailed(lastCandidate.absoluteString, reason)
    }

    private func request(_ url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        let (data, response) = try await session.data(for: request)
        try MojangMetadataService.validate(response)
        return data
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

    private func orderedCandidates(for candidates: [URL]) -> [URL] {
        candidates.stablePartitioned { !sessionIsCoolingDown(for: $0) }
    }

    private func sessionIsCoolingDown(for url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              let cooldownUntil = sessionCooldowns[host] else {
            return false
        }
        if cooldownUntil > Date() {
            return true
        }
        sessionCooldowns[host] = nil
        return false
    }

    private func markSessionSuccess(for url: URL) {
        guard let host = url.host?.lowercased() else { return }
        sessionCooldowns[host] = nil
    }

    private func markSessionFailureIfNeeded(for url: URL, error: Error) {
        guard shouldCooldownSession(for: error),
              let host = url.host?.lowercased() else {
            return
        }
        sessionCooldowns[host] = Date().addingTimeInterval(sessionCooldownInterval)
    }

    private func shouldCooldownSession(for error: Error) -> Bool {
        if let launcherError = error as? LauncherError,
           case let .httpStatus(status) = launcherError {
            return status >= 500
        }
        return true
    }
}

private extension Array {
    func stablePartitioned(_ belongsInFirstGroup: (Element) -> Bool) -> [Element] {
        filter(belongsInFirstGroup) + filter { !belongsInFirstGroup($0) }
    }
}
