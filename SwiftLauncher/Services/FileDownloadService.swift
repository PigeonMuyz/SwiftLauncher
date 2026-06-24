import Foundation

actor FileDownloadService {
    private let http: PublicHTTPClient

    init(http: PublicHTTPClient = .shared) {
        self.http = http
    }

    func data(
        from url: URL,
        expectedSHA1: String? = nil,
        expectedSHA512: String? = nil
    ) async throws -> Data {
        let data = try await http.data(from: url)
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
        expectedSHA1: String? = nil,
        expectedSHA512: String? = nil
    ) async throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            let sha1Matches = expectedSHA1 == nil
                || (try? Hashing.sha1(fileAt: destination)) == expectedSHA1?.lowercased()
            let sha512Matches = expectedSHA512 == nil
                || (try? Hashing.sha512(fileAt: destination)) == expectedSHA512?.lowercased()
            if sha1Matches && sha512Matches {
                return
            }
            try? FileManager.default.removeItem(at: destination)
        }

        let data = try await data(
            from: url,
            expectedSHA1: expectedSHA1,
            expectedSHA512: expectedSHA512
        )
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: [.atomic])
    }
}
