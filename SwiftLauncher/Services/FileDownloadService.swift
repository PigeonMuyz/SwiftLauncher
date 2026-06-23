import Foundation

actor FileDownloadService {
    private let http: PublicHTTPClient

    init(http: PublicHTTPClient = .shared) {
        self.http = http
    }

    func data(from url: URL, expectedSHA1: String? = nil) async throws -> Data {
        let data = try await http.data(from: url)
        if let expectedSHA1, !expectedSHA1.isEmpty,
           Hashing.sha1(data) != expectedSHA1.lowercased() {
            throw LauncherError.checksumMismatch(url.lastPathComponent)
        }
        return data
    }

    func download(
        from url: URL,
        to destination: URL,
        expectedSHA1: String? = nil
    ) async throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            if expectedSHA1 == nil || (try? Hashing.sha1(fileAt: destination)) == expectedSHA1?.lowercased() {
                return
            }
            try? FileManager.default.removeItem(at: destination)
        }

        let data = try await data(from: url, expectedSHA1: expectedSHA1)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: [.atomic])
    }
}
