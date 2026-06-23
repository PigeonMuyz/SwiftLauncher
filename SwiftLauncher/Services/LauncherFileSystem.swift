import Foundation

actor LauncherFileSystem {
    static let shared = LauncherFileSystem()

    nonisolated let root: URL
    nonisolated let minecraftRoot: URL
    nonisolated let instancesRoot: URL
    nonisolated let sharedGameRoot: URL
    nonisolated let versionsRoot: URL
    nonisolated let librariesRoot: URL
    nonisolated let assetsRoot: URL
    nonisolated let logsRoot: URL

    init(root: URL? = nil) {
        let base = root ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("SwiftLauncher", isDirectory: true)

        self.root = base
        self.minecraftRoot = base.appendingPathComponent("minecraft", isDirectory: true)
        self.instancesRoot = base.appendingPathComponent("instances", isDirectory: true)
        self.sharedGameRoot = base.appendingPathComponent("shared-game", isDirectory: true)
        self.versionsRoot = minecraftRoot.appendingPathComponent("versions", isDirectory: true)
        self.librariesRoot = minecraftRoot.appendingPathComponent("libraries", isDirectory: true)
        self.assetsRoot = minecraftRoot.appendingPathComponent("assets", isDirectory: true)
        self.logsRoot = base.appendingPathComponent("logs", isDirectory: true)
    }

    func prepare() throws {
        for directory in [root, minecraftRoot, instancesRoot, sharedGameRoot, versionsRoot, librariesRoot, assetsRoot, logsRoot] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(
            at: assetsRoot.appendingPathComponent("indexes", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: assetsRoot.appendingPathComponent("objects", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    func loadInstances() throws -> [LauncherInstance] {
        try load([LauncherInstance].self, from: root.appendingPathComponent("instances.json")) ?? []
    }

    func saveInstances(_ instances: [LauncherInstance]) throws {
        try save(instances, to: root.appendingPathComponent("instances.json"))
    }

    func loadAccounts() throws -> [PlayerAccount] {
        try load([PlayerAccount].self, from: root.appendingPathComponent("accounts.json")) ?? []
    }

    func saveAccounts(_ accounts: [PlayerAccount]) throws {
        try save(accounts, to: root.appendingPathComponent("accounts.json"))
    }

    nonisolated func instanceRoot(_ id: UUID) -> URL {
        instancesRoot.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    nonisolated func gameDirectory(_ id: UUID) -> URL {
        instanceRoot(id).appendingPathComponent("game", isDirectory: true)
    }

    nonisolated func gameDirectory(_ instance: LauncherInstance) -> URL {
        instance.isVersionIsolated ? gameDirectory(instance.id) : sharedGameRoot
    }

    nonisolated func nativesDirectory(_ id: UUID) -> URL {
        instanceRoot(id).appendingPathComponent("natives", isDirectory: true)
    }

    nonisolated func versionDirectory(_ versionID: String) -> URL {
        versionsRoot.appendingPathComponent(versionID, isDirectory: true)
    }

    nonisolated func versionJSON(_ versionID: String) -> URL {
        versionDirectory(versionID).appendingPathComponent("\(versionID).json")
    }

    nonisolated func versionJAR(_ versionID: String) -> URL {
        versionDirectory(versionID).appendingPathComponent("\(versionID).jar")
    }

    nonisolated func latestLogURL() -> URL {
        logsRoot.appendingPathComponent("latest.log")
    }

    nonisolated func manifestCacheURL() -> URL {
        root.appendingPathComponent("version_manifest_v2.json")
    }

    nonisolated func installationMarker(_ id: UUID) -> URL {
        instanceRoot(id).appendingPathComponent("installed.json")
    }

    nonisolated func loaderProfile(_ id: UUID) -> URL {
        instanceRoot(id).appendingPathComponent("loader-profile.json")
    }

    nonisolated func isInstalled(_ instance: LauncherInstance) -> Bool {
        FileManager.default.fileExists(atPath: installationMarker(instance.id).path)
            && FileManager.default.fileExists(atPath: versionJAR(instance.versionID).path)
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONCoding.makeDecoder().decode(T.self, from: Data(contentsOf: url))
    }

    private func save<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONCoding.makeEncoder().encode(value)
        try data.write(to: url, options: [.atomic])
    }
}
