import Foundation
import ImageIO

struct InstanceImportResult: Sendable {
    let instance: LauncherInstance
    let detail: String
}

actor InstanceImportService {
    typealias ProgressHandler = @MainActor @Sendable (Double, String) async throws -> Void

    private let fileSystem: LauncherFileSystem
    private let downloader: FileDownloadService
    private let http: PublicHTTPClient

    init(
        fileSystem: LauncherFileSystem = .shared,
        downloader: FileDownloadService = FileDownloadService(),
        http: PublicHTTPClient = .shared
    ) {
        self.fileSystem = fileSystem
        self.downloader = downloader
        self.http = http
    }

    func importModpack(
        from sourceURL: URL,
        accountID: UUID?,
        knownVersionIDs: Set<String>,
        progress: @escaping ProgressHandler
    ) async throws -> InstanceImportResult {
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
        try await progress(0.02, "正在解压整合包")

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLauncher-Import-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try await extractArchive(sourceURL, to: temporaryRoot)

        if let indexURL = firstFile(named: "modrinth.index.json", under: temporaryRoot) {
            return try await importModrinthPack(
                indexURL: indexURL,
                archiveURL: sourceURL,
                accountID: accountID,
                knownVersionIDs: knownVersionIDs,
                progress: progress
            )
        }
        if let packURL = firstFile(named: "mmc-pack.json", under: temporaryRoot) {
            return try await importPrismPack(
                packURL: packURL,
                accountID: accountID,
                knownVersionIDs: knownVersionIDs,
                progress: progress
            )
        }
        if let manifestURL = firstFile(named: "manifest.json", under: temporaryRoot),
           let manifest = try? JSONCoding.makeDecoder().decode(
               CurseForgeManifest.self,
               from: Data(contentsOf: manifestURL)
           ) {
            return try await importCurseForgePack(
                manifest: manifest,
                root: manifestURL.deletingLastPathComponent(),
                accountID: accountID,
                knownVersionIDs: knownVersionIDs,
                progress: progress
            )
        }
        if let gameDirectory = firstDirectory(named: ".minecraft", under: temporaryRoot) {
            return try await importMinecraftDirectory(
                gameDirectory,
                suggestedName: sourceURL.deletingPathExtension().lastPathComponent,
                accountID: accountID,
                knownVersionIDs: knownVersionIDs,
                progress: progress
            )
        }
        throw LauncherError.unsupported("未识别此整合包；支持 Modrinth、Prism/MultiMC 和 CurseForge 导出格式")
    }

    func importMinecraftFolder(
        from selectedURL: URL,
        accountID: UUID?,
        knownVersionIDs: Set<String>,
        progress: @escaping ProgressHandler
    ) async throws -> InstanceImportResult {
        let accessing = selectedURL.startAccessingSecurityScopedResource()
        defer { if accessing { selectedURL.stopAccessingSecurityScopedResource() } }
        let gameDirectory = selectedURL.lastPathComponent == ".minecraft"
            ? selectedURL
            : selectedURL.appendingPathComponent(".minecraft", isDirectory: true)
        guard FileManager.default.fileExists(atPath: gameDirectory.path) else {
            throw LauncherError.unsupported("所选目录中没有找到 .minecraft 文件夹")
        }
        return try await importMinecraftDirectory(
            gameDirectory,
            suggestedName: selectedURL.lastPathComponent,
            accountID: accountID,
            knownVersionIDs: knownVersionIDs,
            progress: progress
        )
    }

    private func importModrinthPack(
        indexURL: URL,
        archiveURL: URL,
        accountID: UUID?,
        knownVersionIDs: Set<String>,
        progress: @escaping ProgressHandler
    ) async throws -> InstanceImportResult {
        let index = try JSONCoding.makeDecoder().decode(
            ModrinthPackIndex.self,
            from: Data(contentsOf: indexURL)
        )
        guard index.game == "minecraft", let minecraftVersion = index.dependencies["minecraft"],
              knownVersionIDs.contains(minecraftVersion) else {
            throw LauncherError.unsupported("整合包声明的 Minecraft 版本不在 Mojang 版本清单中")
        }
        let loader = loader(from: index.dependencies)
        var instance = makeInstance(
            name: index.name,
            versionID: minecraftVersion,
            loader: loader.loader,
            loaderVersion: loader.version,
            accountID: accountID
        )
        let gameDirectory = try prepare(instance)
        let root = indexURL.deletingLastPathComponent()
        try copyTreeIfPresent(root.appendingPathComponent("overrides"), to: gameDirectory, overwrite: true)
        try copyTreeIfPresent(root.appendingPathComponent("client-overrides"), to: gameDirectory, overwrite: true)
        let embeddedIcon = firstValidIconData(in: [
            root,
            root.appendingPathComponent("overrides"),
            root.appendingPathComponent("client-overrides")
        ])
        let iconData: Data?
        if let embeddedIcon {
            iconData = embeddedIcon
        } else {
            iconData = await modrinthProjectIconData(for: archiveURL)
        }
        try applyIconData(iconData, to: &instance)

        let clientFiles = index.files.filter { $0.env?.client != "unsupported" }
        let downloadItems = try clientFiles.map { file -> ModrinthDownloadItem in
            guard let destination = safeDestination(for: file.path, under: gameDirectory) else {
                throw LauncherError.unsupported("整合包包含不安全的文件路径：\(file.path)")
            }
            return ModrinthDownloadItem(
                path: file.path,
                downloads: file.downloads,
                sha1: file.hashes["sha1"],
                sha512: file.hashes["sha512"],
                destination: destination
            )
        }
        try await downloadModrinthClientFiles(downloadItems, progress: progress)
        try await progress(1, "整合包已导入，启动时会自动补全游戏核心")
        return InstanceImportResult(
            instance: instance,
            detail: "已导入 Modrinth 整合包（\(clientFiles.count) 个文件，哈希校验通过）"
        )
    }

    private func importPrismPack(
        packURL: URL,
        accountID: UUID?,
        knownVersionIDs: Set<String>,
        progress: @escaping ProgressHandler
    ) async throws -> InstanceImportResult {
        let pack = try JSONCoding.makeDecoder().decode(PrismPack.self, from: Data(contentsOf: packURL))
        guard let minecraft = pack.components.first(where: { $0.uid == "net.minecraft" })?.version,
              knownVersionIDs.contains(minecraft) else {
            throw LauncherError.unsupported("Prism/MultiMC 包未声明可识别的 Minecraft 版本")
        }
        let loaderInfo = prismLoader(from: pack.components)
        let root = packURL.deletingLastPathComponent()
        let sourceGame = root.appendingPathComponent(".minecraft", isDirectory: true)
        var instance = makeInstance(
            name: root.lastPathComponent,
            versionID: minecraft,
            loader: loaderInfo.loader,
            loaderVersion: loaderInfo.version,
            accountID: accountID
        )
        let destination = try prepare(instance)
        try await progress(0.3, "正在复制 Prism/MultiMC 实例文件")
        try copyTreeIfPresent(sourceGame, to: destination, overwrite: true)
        try applyIconData(firstValidIconData(in: [root, sourceGame]), to: &instance)
        try await progress(1, "实例已导入，启动时会校验并补全基础文件")
        return InstanceImportResult(instance: instance, detail: "已导入 Prism/MultiMC 实例")
    }

    private func importCurseForgePack(
        manifest: CurseForgeManifest,
        root: URL,
        accountID: UUID?,
        knownVersionIDs: Set<String>,
        progress: @escaping ProgressHandler
    ) async throws -> InstanceImportResult {
        guard knownVersionIDs.contains(manifest.minecraft.version) else {
            throw LauncherError.unsupported("CurseForge 包使用了未知的 Minecraft 版本")
        }
        let primary = manifest.minecraft.modLoaders.first(where: { $0.primary == true })
            ?? manifest.minecraft.modLoaders.first
        let loaderInfo = parseCurseForgeLoader(primary?.id)
        var instance = makeInstance(
            name: manifest.name,
            versionID: manifest.minecraft.version,
            loader: loaderInfo.loader,
            loaderVersion: loaderInfo.version,
            accountID: accountID
        )
        let destination = try prepare(instance)
        try await progress(0.45, "正在复制 CurseForge overrides")
        try copyTreeIfPresent(root.appendingPathComponent("overrides"), to: destination, overwrite: true)
        try applyIconData(
            firstValidIconData(in: [root, root.appendingPathComponent("overrides")]),
            to: &instance
        )
        try await progress(1, "已导入本地文件；外部 CurseForge 模组需要 API 凭证")
        let missing = manifest.files.count
        return InstanceImportResult(
            instance: instance,
            detail: missing == 0
                ? "已导入 CurseForge 整合包"
                : "已导入配置；\(missing) 个 CurseForge 外部文件需通过原客户端或手动补全"
        )
    }

    private func importMinecraftDirectory(
        _ source: URL,
        suggestedName: String,
        accountID: UUID?,
        knownVersionIDs: Set<String>,
        progress: @escaping ProgressHandler
    ) async throws -> InstanceImportResult {
        try await progress(0.08, "正在识别 Minecraft 与加载器版本")
        let detected = try detectInstallation(at: source, knownVersionIDs: knownVersionIDs)
        var instance = makeInstance(
            name: suggestedName == ".minecraft" ? "导入的 Minecraft" : suggestedName,
            versionID: detected.versionID,
            loader: detected.loader,
            loaderVersion: detected.loaderVersion,
            accountID: accountID
        )
        let destination = try prepare(instance)

        try await progress(0.25, "正在复制存档、模组与配置")
        for name in Self.instanceDataNames {
            try copyTreeIfPresent(
                source.appendingPathComponent(name),
                to: destination.appendingPathComponent(name),
                overwrite: true
            )
        }
        try applyIconData(firstValidIconData(in: [source, source.deletingLastPathComponent()]), to: &instance)

        try await progress(0.62, "正在合并可复用的官方资源")
        try copyTreeIfPresent(source.appendingPathComponent("assets"), to: fileSystem.assetsRoot, overwrite: false)
        try copyTreeIfPresent(source.appendingPathComponent("libraries"), to: fileSystem.librariesRoot, overwrite: false)
        try copyTreeIfPresent(
            source.appendingPathComponent("versions").appendingPathComponent(detected.versionID),
            to: fileSystem.versionDirectory(detected.versionID),
            overwrite: false
        )
        try await progress(1, "导入完成；首次启动会校验并补全缺失文件")
        return InstanceImportResult(instance: instance, detail: "已导入 .minecraft，官方资源已并入共享缓存")
    }

    private func detectInstallation(
        at source: URL,
        knownVersionIDs: Set<String>
    ) throws -> DetectedInstallation {
        var candidates: [String] = []
        let profilesURL = source.appendingPathComponent("launcher_profiles.json")
        if let object = try? JSONSerialization.jsonObject(with: Data(contentsOf: profilesURL)) as? [String: Any] {
            if let selected = object["selectedProfile"] as? String,
               let profiles = object["profiles"] as? [String: [String: Any]],
               let version = profiles[selected]?["lastVersionId"] as? String {
                candidates.append(version)
            }
            if let profiles = object["profiles"] as? [String: [String: Any]] {
                candidates.append(contentsOf: profiles.values.compactMap { $0["lastVersionId"] as? String })
            }
        }

        let versionsRoot = source.appendingPathComponent("versions", isDirectory: true)
        if let versionDirectories = try? FileManager.default.contentsOfDirectory(
            at: versionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            let sorted = versionDirectories.sorted {
                let lhs = try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                let rhs = try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return (lhs ?? .distantPast) > (rhs ?? .distantPast)
            }
            candidates.append(contentsOf: sorted.map(\.lastPathComponent))
            for directory in sorted {
                let jsonURL = directory.appendingPathComponent("\(directory.lastPathComponent).json")
                if let object = try? JSONSerialization.jsonObject(with: Data(contentsOf: jsonURL)) as? [String: Any],
                   let inherited = object["inheritsFrom"] as? String {
                    let loaderInfo = loaderFromVersionJSON(object, compositeID: directory.lastPathComponent)
                    if knownVersionIDs.contains(inherited) {
                        return DetectedInstallation(
                            versionID: inherited,
                            loader: loaderInfo.loader,
                            loaderVersion: loaderInfo.version
                        )
                    }
                }
            }
        }

        for candidate in candidates {
            if knownVersionIDs.contains(candidate) {
                return DetectedInstallation(versionID: candidate, loader: .vanilla, loaderVersion: nil)
            }
            if let parsed = parseCompositeVersion(candidate), knownVersionIDs.contains(parsed.versionID) {
                return parsed
            }
        }
        throw LauncherError.unsupported("无法从 launcher_profiles.json 或 versions 目录识别游戏版本")
    }

    private func loaderFromVersionJSON(
        _ object: [String: Any],
        compositeID: String
    ) -> (loader: ModLoader, version: String?) {
        if let parsed = parseCompositeVersion(compositeID) {
            return (parsed.loader, parsed.loaderVersion)
        }
        let libraries = object["libraries"] as? [[String: Any]] ?? []
        for library in libraries {
            guard let name = library["name"] as? String else { continue }
            let pieces = name.split(separator: ":").map(String.init)
            if name.contains("fabric-loader"), let version = pieces.last { return (.fabric, version) }
            if name.contains("quilt-loader"), let version = pieces.last { return (.quilt, version) }
            if name.contains("net.minecraftforge:forge"), let version = pieces.last {
                return (.forge, version.split(separator: "-").last.map(String.init))
            }
            if name.contains("net.neoforged:neoforge"), let version = pieces.last { return (.neoForge, version) }
        }
        return (.vanilla, nil)
    }

    private func parseCompositeVersion(_ value: String) -> DetectedInstallation? {
        let patterns: [(String, ModLoader)] = [
            (#"^fabric-loader-(.+)-([0-9]+\..+)$"#, .fabric),
            (#"^quilt-loader-(.+)-([0-9]+\..+)$"#, .quilt),
            (#"^([0-9]+\.[0-9]+(?:\.[0-9]+)?)-forge-(.+)$"#, .forge),
            (#"^([0-9]+\.[0-9]+(?:\.[0-9]+)?)-neoforge-(.+)$"#, .neoForge)
        ]
        for (pattern, loader) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
                  let first = Range(match.range(at: 1), in: value),
                  let second = Range(match.range(at: 2), in: value) else { continue }
            if loader == .fabric || loader == .quilt {
                return DetectedInstallation(
                    versionID: String(value[second]),
                    loader: loader,
                    loaderVersion: String(value[first])
                )
            }
            return DetectedInstallation(
                versionID: String(value[first]),
                loader: loader,
                loaderVersion: String(value[second])
            )
        }
        return nil
    }

    private func loader(from dependencies: [String: String]) -> (loader: ModLoader, version: String?) {
        if let version = dependencies["fabric-loader"] { return (.fabric, version) }
        if let version = dependencies["quilt-loader"] { return (.quilt, version) }
        if let version = dependencies["forge"] { return (.forge, version) }
        if let version = dependencies["neoforge"] { return (.neoForge, version) }
        return (.vanilla, nil)
    }

    private func prismLoader(from components: [PrismPack.Component]) -> (loader: ModLoader, version: String?) {
        for component in components {
            switch component.uid {
            case "net.fabricmc.fabric-loader": return (.fabric, component.version)
            case "org.quiltmc.quilt-loader": return (.quilt, component.version)
            case "net.minecraftforge": return (.forge, component.version)
            case "net.neoforged": return (.neoForge, component.version)
            default: continue
            }
        }
        return (.vanilla, nil)
    }

    private func parseCurseForgeLoader(_ value: String?) -> (loader: ModLoader, version: String?) {
        guard let value else { return (.vanilla, nil) }
        let lowercased = value.lowercased()
        for (prefix, loader): (String, ModLoader) in [
            ("fabric-", .fabric), ("quilt-", .quilt), ("forge-", .forge), ("neoforge-", .neoForge)
        ] where lowercased.hasPrefix(prefix) {
            return (loader, String(value.dropFirst(prefix.count)))
        }
        return (.vanilla, nil)
    }

    private func makeInstance(
        name: String,
        versionID: String,
        loader: ModLoader,
        loaderVersion: String?,
        accountID: UUID?
    ) -> LauncherInstance {
        LauncherInstance(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "导入的实例" : name,
            versionID: versionID,
            memoryMB: UserDefaults.standard.integer(forKey: "defaultMemoryMB").nonzero ?? 4096,
            loader: loader,
            loaderVersion: loaderVersion,
            isVersionIsolated: true,
            accountID: accountID
        )
    }

    private func prepare(_ instance: LauncherInstance) throws -> URL {
        let root = fileSystem.instanceRoot(instance.id)
        let game = fileSystem.gameDirectory(instance)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: game, withIntermediateDirectories: true)
        return game
    }

    private func downloadModrinthClientFiles(
        _ items: [ModrinthDownloadItem],
        progress: @escaping ProgressHandler
    ) async throws {
        guard !items.isEmpty else {
            try await progress(0.94, "整合包没有需要下载的客户端文件")
            return
        }

        let maxConcurrentDownloads = min(8, items.count)
        var nextIndex = 0
        var completed = 0
        let downloader = downloader

        try await progress(
            0.12,
            "准备下载 \(items.count) 个整合包文件（最多 \(maxConcurrentDownloads) 个并发）"
        )

        try await withThrowingTaskGroup(of: String.self) { group in
            func enqueueNext() {
                let item = items[nextIndex]
                let itemNumber = nextIndex + 1
                let itemStart = 0.12 + 0.82 * Double(nextIndex) / Double(items.count)
                let itemSpan = 0.82 / Double(max(items.count, 1))
                nextIndex += 1
                group.addTask {
                    try await Self.downloadFirstAvailable(
                        item,
                        downloader: downloader,
                        progress: { value in
                            try await progress(
                                itemStart + itemSpan * value,
                                "正在下载 \(item.path)（\(itemNumber)/\(items.count)）"
                            )
                        }
                    )
                    return item.path
                }
            }

            while nextIndex < maxConcurrentDownloads {
                enqueueNext()
            }

            while let finishedPath = try await group.next() {
                completed += 1
                let nextDetail: String
                if nextIndex < items.count {
                    nextDetail = "已下载 \(finishedPath)，继续 \(items[nextIndex].path)（\(completed)/\(items.count)）"
                } else {
                    nextDetail = "已下载 \(finishedPath)（\(completed)/\(items.count)）"
                }
                try await progress(
                    0.12 + 0.82 * Double(completed) / Double(max(items.count, 1)),
                    nextDetail
                )

                if nextIndex < items.count {
                    enqueueNext()
                }
            }
        }
    }

    private static func downloadFirstAvailable(
        _ item: ModrinthDownloadItem,
        downloader: FileDownloadService,
        progress: FileDownloadService.ProgressHandler? = nil
    ) async throws {
        var lastError: Error = LauncherError.missingDownload(item.path)
        for url in item.downloads {
            do {
                try await downloader.download(
                    from: url,
                    to: item.destination,
                    expectedSHA1: item.sha1,
                    expectedSHA512: item.sha512,
                    progress: progress
                )
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func modrinthProjectIconData(for archive: URL) async -> Data? {
        // The .mrpack format itself has no icon field. When the archive came from
        // Modrinth, its SHA-512 can resolve back to the project and its icon.
        guard let hash = try? Hashing.sha512(fileAt: archive) else { return nil }
        var components = URLComponents(
            string: "https://api.modrinth.com/v2/version_file/\(hash)"
        )
        components?.queryItems = [URLQueryItem(name: "algorithm", value: "sha512")]
        guard let versionURL = components?.url,
              let versionData = try? await http.data(from: versionURL, headers: Self.modrinthHeaders),
              let version = try? JSONCoding.makeDecoder().decode(ModrinthVersionLookup.self, from: versionData) else {
            return nil
        }
        let projectURL = URL(string: "https://api.modrinth.com/v2/project/\(version.projectID)")!
        guard let projectData = try? await http.data(from: projectURL, headers: Self.modrinthHeaders),
              let project = try? JSONCoding.makeDecoder().decode(ModrinthProjectLookup.self, from: projectData),
              let iconURL = project.iconURL.flatMap(URL.init(string:)),
              let data = try? await http.data(from: iconURL),
              isValidImage(data) else { return nil }
        return data
    }

    private func firstValidIconData(in roots: [URL]) -> Data? {
        let preferredNames = [
            "icon.png", "pack.png", "logo.png", "instance.png", "modpack.png",
            "icon.jpg", "icon.jpeg", "icon.webp", "logo.jpg", "logo.jpeg", "logo.webp"
        ]
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            for name in preferredNames {
                let url = root.appendingPathComponent(name)
                if let data = try? Data(contentsOf: url), isValidImage(data) { return data }
            }
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in contents {
                let stem = url.deletingPathExtension().lastPathComponent.lowercased()
                guard stem.contains("icon") || stem.contains("logo") else { continue }
                if let data = try? Data(contentsOf: url), isValidImage(data) { return data }
            }
        }
        return nil
    }

    private func applyIconData(_ data: Data?, to instance: inout LauncherInstance) throws {
        guard let data, isValidImage(data) else { return }
        try data.write(to: fileSystem.instanceIcon(instance.id), options: [.atomic])
        instance.iconFileName = "icon.png"
    }

    private func isValidImage(_ data: Data) -> Bool {
        !data.isEmpty && CGImageSourceCreateWithData(data as CFData, nil) != nil
    }

    private func extractArchive(_ source: URL, to destination: URL) async throws {
        try await Task.detached(priority: .utility) {
            _ = try ProcessRunner.run(
                executable: URL(fileURLWithPath: "/usr/bin/ditto"),
                arguments: ["-x", "-k", source.path, destination.path],
                mergeError: true
            )
        }.value
    }

    private func firstFile(named name: String, under root: URL) -> URL? {
        firstItem(named: name, under: root, isDirectory: false)
    }

    private func firstDirectory(named name: String, under root: URL) -> URL? {
        firstItem(named: name, under: root, isDirectory: true)
    }

    private func firstItem(named name: String, under root: URL, isDirectory: Bool) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return nil }
        for case let url as URL in enumerator where url.lastPathComponent == name {
            let value = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
            if value == isDirectory { return url }
        }
        return nil
    }

    private func safeDestination(for relativePath: String, under root: URL) -> URL? {
        let destination = root.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = root.standardizedFileURL.path + "/"
        guard destination.path.hasPrefix(rootPath) else { return nil }
        return destination
    }

    private func copyTreeIfPresent(_ source: URL, to destination: URL, overwrite: Bool) throws {
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else { return }
        if values.isDirectory == true {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            for child in try FileManager.default.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) {
                try copyTreeIfPresent(
                    child,
                    to: destination.appendingPathComponent(child.lastPathComponent),
                    overwrite: overwrite
                )
            }
        } else {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                guard overwrite else { return }
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private static let instanceDataNames = [
        "saves", "mods", "config", "defaultconfigs", "resourcepacks", "shaderpacks",
        "screenshots", "schematics", "journeymap", "kubejs", "options.txt", "optionsof.txt",
        "servers.dat"
    ]

    private static let modrinthHeaders = [
        "User-Agent": "PigeonMuyz/SwiftLauncher (github.com/PigeonMuyz/SwiftLauncher)"
    ]

}

private struct DetectedInstallation {
    let versionID: String
    let loader: ModLoader
    let loaderVersion: String?
}

private struct ModrinthDownloadItem: Sendable {
    let path: String
    let downloads: [URL]
    let sha1: String?
    let sha512: String?
    let destination: URL
}

private struct ModrinthPackIndex: Decodable {
    let game: String
    let name: String
    let files: [File]
    let dependencies: [String: String]

    struct File: Decodable {
        let path: String
        let hashes: [String: String]
        let env: Environment?
        let downloads: [URL]
    }

    struct Environment: Decodable {
        let client: String?
    }
}

private struct ModrinthVersionLookup: Decodable {
    let projectID: String

    private enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
    }
}

private struct ModrinthProjectLookup: Decodable {
    let iconURL: String?

    private enum CodingKeys: String, CodingKey {
        case iconURL = "icon_url"
    }
}

private struct PrismPack: Decodable {
    let components: [Component]

    struct Component: Decodable {
        let uid: String
        let version: String
    }
}

private struct CurseForgeManifest: Decodable {
    let name: String
    let minecraft: Minecraft
    let files: [File]

    struct Minecraft: Decodable {
        let version: String
        let modLoaders: [Loader]
    }

    struct Loader: Decodable {
        let id: String
        let primary: Bool?
    }

    struct File: Decodable {
        let projectID: Int
        let fileID: Int

        private enum CodingKeys: String, CodingKey {
            case projectID = "projectID"
            case fileID = "fileID"
        }
    }
}

private extension Int {
    var nonzero: Int? { self == 0 ? nil : self }
}
