import Foundation

actor FileDownloadService {
    typealias ProgressHandler = @MainActor @Sendable (Double) async throws -> Void
    typealias CheckpointHandler = @MainActor @Sendable () async throws -> Void

    enum ExistingFileValidation: Sendable {
        case checksum
        case sizeOnly
    }

    private let http: PublicHTTPClient

    init(http: PublicHTTPClient = .shared) {
        self.http = http
    }

    func data(
        from url: URL,
        expectedSHA1: String? = nil,
        expectedSHA512: String? = nil,
        checkpoint: CheckpointHandler? = nil
    ) async throws -> Data {
        try await checkpoint?()
        let data = try await http.data(from: url)
        try await checkpoint?()
        if let expectedSHA1, !expectedSHA1.isEmpty,
           Hashing.sha1(data) != expectedSHA1.lowercased() {
            throw LauncherError.checksumMismatch(url.lastPathComponent)
        }
        if let expectedSHA512, !expectedSHA512.isEmpty,
           Hashing.sha512(data) != expectedSHA512.lowercased() {
            throw LauncherError.checksumMismatch(url.lastPathComponent)
        }
        return data
    }

    func download(
        from url: URL,
        to destination: URL,
        expectedSize: Int64? = nil,
        expectedSHA1: String? = nil,
        expectedSHA512: String? = nil,
        existingFileValidation: ExistingFileValidation = .checksum,
        progress: ProgressHandler? = nil,
        checkpoint: CheckpointHandler? = nil
    ) async throws {
        try await checkpoint?()
        if FileManager.default.fileExists(atPath: destination.path) {
            let sizeMatches = expectedSize == nil || fileHasSize(expectedSize, at: destination)
            if existingFileValidation == .sizeOnly, sizeMatches {
                try await progress?(1)
                return
            }
            if existingFileValidation == .checksum, sizeMatches {
                let sha1Matches = expectedSHA1 == nil
                    || (try? Hashing.sha1(fileAt: destination)) == expectedSHA1?.lowercased()
                let sha512Matches = expectedSHA512 == nil
                    || (try? Hashing.sha512(fileAt: destination)) == expectedSHA512?.lowercased()
                if sha1Matches && sha512Matches {
                    try await progress?(1)
                    return
                }
            }
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let temporaryDestination = destination.deletingLastPathComponent()
            .appendingPathComponent(".swiftlauncher-download-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temporaryDestination) }

        try await progress?(0)
        try await http.download(from: url, to: temporaryDestination) { receivedBytes, totalBytes in
            try await checkpoint?()
            guard let totalBytes, totalBytes > 0 else { return }
            let fraction = min(max(Double(receivedBytes) / Double(totalBytes), 0), 1)
            try await progress?(fraction)
        }
        try await checkpoint?()
        try validateDownloadedFile(
            at: temporaryDestination,
            name: url.lastPathComponent,
            expectedSize: expectedSize,
            expectedSHA1: expectedSHA1,
            expectedSHA512: expectedSHA512
        )
        try await progress?(1)

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryDestination, to: destination)
    }

    private func fileHasSize(_ expectedSize: Int64?, at url: URL) -> Bool {
        guard let expectedSize else { return true }
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return Int64(size ?? -1) == expectedSize
    }

    private func validateDownloadedFile(
        at url: URL,
        name: String,
        expectedSize: Int64?,
        expectedSHA1: String?,
        expectedSHA512: String?
    ) throws {
        if !fileHasSize(expectedSize, at: url) {
            throw LauncherError.checksumMismatch(name)
        }
        if let expectedSHA1, !expectedSHA1.isEmpty,
           try Hashing.sha1(fileAt: url) != expectedSHA1.lowercased() {
            throw LauncherError.checksumMismatch(name)
        }
        if let expectedSHA512, !expectedSHA512.isEmpty,
           try Hashing.sha512(fileAt: url) != expectedSHA512.lowercased() {
            throw LauncherError.checksumMismatch(name)
        }
    }
}
