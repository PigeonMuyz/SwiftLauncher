import Foundation

struct ModrinthInstalledModsIndex: Codable, Sendable {
    var records: [String: ModrinthInstalledModRecord] = [:]
}

struct ModrinthInstalledModRecord: Codable, Sendable {
    let projectID: String
    let versionID: String
    let title: String
    let versionNumber: String
    let iconURLString: String?

    var iconURL: URL? {
        iconURLString.flatMap(URL.init(string:))
    }
}

enum ModrinthInstalledModsIndexStore {
    static let fileName = ".swiftlauncher-modrinth-mods.json"

    static func url(in modsDirectory: URL) -> URL {
        modsDirectory.appendingPathComponent(fileName)
    }

    static func load(from modsDirectory: URL) -> ModrinthInstalledModsIndex {
        let url = url(in: modsDirectory)
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONCoding.makeDecoder().decode(ModrinthInstalledModsIndex.self, from: data) else {
            return ModrinthInstalledModsIndex()
        }
        return index
    }

    static func save(_ index: ModrinthInstalledModsIndex, to modsDirectory: URL) throws {
        try FileManager.default.createDirectory(at: modsDirectory, withIntermediateDirectories: true)
        let data = try JSONCoding.makeEncoder().encode(index)
        try data.write(to: url(in: modsDirectory), options: [.atomic])
    }
}
