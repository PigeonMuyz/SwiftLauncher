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
    nonisolated let runtimesRoot: URL
    nonisolated let baseInstallationsRoot: URL
    nonisolated let minecraftIconsRoot: URL
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
        self.runtimesRoot = base.appendingPathComponent("runtimes", isDirectory: true)
        self.baseInstallationsRoot = minecraftRoot.appendingPathComponent("base-installations", isDirectory: true)
        self.minecraftIconsRoot = minecraftRoot.appendingPathComponent("icons", isDirectory: true)
        self.logsRoot = base.appendingPathComponent("logs", isDirectory: true)
    }

    func prepare() throws {
        for directory in [
            root, minecraftRoot, instancesRoot, sharedGameRoot, versionsRoot,
            librariesRoot, assetsRoot, runtimesRoot, baseInstallationsRoot, minecraftIconsRoot, logsRoot
        ] {
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

    nonisolated func baseInstallationMarker(_ versionID: String) -> URL {
        baseInstallationsRoot.appendingPathComponent("\(versionID).json")
    }

    nonisolated func loaderProfile(_ id: UUID) -> URL {
        instanceRoot(id).appendingPathComponent("loader-profile.json")
    }

    nonisolated func instanceIcon(_ id: UUID) -> URL {
        instanceRoot(id).appendingPathComponent("icon.png")
    }

    nonisolated func minecraftIcon(_ versionID: String) -> URL {
        minecraftIconsRoot.appendingPathComponent("\(versionID).png")
    }

    func ensureMinecraftIcon(for versionID: String) throws {
        let destination = minecraftIcon(versionID)
        if FileManager.default.fileExists(atPath: destination.path) { return }

        let client = versionJAR(versionID)
        guard FileManager.default.fileExists(atPath: client.path) else { return }
        let data = try ProcessRunner.runData(
            executable: URL(fileURLWithPath: "/usr/bin/unzip"),
            arguments: ["-p", client.path, "pack.png"]
        )
        let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        guard data.starts(with: pngSignature) else {
            throw LauncherError.unsupported("Minecraft \(versionID) 没有可用的官方 pack.png 图标")
        }
        try data.write(to: destination, options: [.atomic])
    }

    nonisolated func isInstalled(_ instance: LauncherInstance) -> Bool {
        guard FileManager.default.fileExists(atPath: installationMarker(instance.id).path)
            && FileManager.default.fileExists(atPath: baseInstallationMarker(instance.versionID).path)
            && FileManager.default.fileExists(atPath: versionJSON(instance.versionID).path)
            && FileManager.default.fileExists(atPath: versionJAR(instance.versionID).path) else {
            return false
        }

        guard instance.loader != .vanilla else { return true }
        guard let profileData = try? Data(contentsOf: loaderProfile(instance.id)) else { return false }
        switch instance.loader {
        case .fabric, .quilt:
            guard let profile = try? JSONCoding.makeDecoder().decode(LoaderProfile.self, from: profileData) else {
                return false
            }
            return profile.libraries.allSatisfy { library in
                FileManager.default.fileExists(
                    atPath: librariesRoot.appendingPathComponent(MavenCoordinate.path(for: library.name)).path
                )
            }
        case .forge, .neoForge:
            guard let profile = try? JSONCoding.makeDecoder().decode(VersionMetadata.self, from: profileData) else {
                return false
            }
            return profile.libraries.allSatisfy { library in
                guard let artifact = library.downloads?.artifact else { return true }
                let path = artifact.path ?? MavenCoordinate.path(for: library.name)
                return FileManager.default.fileExists(atPath: librariesRoot.appendingPathComponent(path).path)
            }
        case .vanilla:
            return true
        }
    }

    nonisolated func hasImportedContent(_ instance: LauncherInstance) -> Bool {
        let directory = gameDirectory(instance)
        let meaningfulNames = [
            "mods", "config", "defaultconfigs", "saves", "resourcepacks", "shaderpacks",
            "kubejs", "options.txt", "servers.dat"
        ]
        return meaningfulNames.contains {
            let url = directory.appendingPathComponent($0)
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            if let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
               values.isDirectory == true {
                return ((try? FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty) == false)
            }
            return true
        }
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
