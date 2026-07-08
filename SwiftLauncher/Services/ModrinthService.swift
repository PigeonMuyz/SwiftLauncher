import Foundation

struct ModrinthSearchResult: Decodable, Identifiable, Hashable, Sendable {
    let projectID: String
    let slug: String
    let title: String
    let description: String
    let author: String
    let downloads: Int
    let follows: Int
    let categories: [String]
    let iconURL: URL?

    var id: String { projectID }

    private enum CodingKeys: String, CodingKey {
        case projectID = "project_id"
        case slug, title, description, author, downloads, follows, categories
        case iconURL = "icon_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        projectID = try container.decode(String.self, forKey: .projectID)
        slug = try container.decode(String.self, forKey: .slug)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)
        author = try container.decode(String.self, forKey: .author)
        downloads = try container.decode(Int.self, forKey: .downloads)
        follows = try container.decodeIfPresent(Int.self, forKey: .follows) ?? 0
        categories = try container.decodeIfPresent([String].self, forKey: .categories) ?? []
        iconURL = try container.decodeIfPresent(String.self, forKey: .iconURL)
            .flatMap(URL.init(string:))
    }
}

private struct ModrinthSearchEnvelope: Decodable, Sendable {
    let hits: [ModrinthSearchResult]
}

struct ModrinthInstallPlan: Identifiable, Sendable {
    let kind: ModrinthContentKind
    let project: ModrinthSearchResult
    let versions: [ModrinthVersionOption]
    let selectedVersionID: String
    let versionID: String
    let versionName: String
    let versionNumber: String
    let requiredDependencies: [ModrinthDependencyPlan]
    let compatibilityNotices: [ModrinthCompatibilityNotice]

    var id: String { project.projectID }

    var compatibilityConfirmationMessage: String {
        let details = compatibilityNotices.prefix(4).map(\.detail).joined(separator: "\n")
        let overflow = compatibilityNotices.count > 4 ? "\n另有 \(compatibilityNotices.count - 4) 条提示未列出。" : ""
        return "\(details)\(overflow)\n\n是否仍要下载？"
    }
}

struct ModrinthDependencyPlan: Identifiable, Sendable {
    let projectID: String
    let slug: String
    let title: String
    let versionID: String
    let versionName: String
    let versionNumber: String
    let iconURL: URL?
    let depth: Int

    var id: String { "\(projectID):\(versionID)" }
    var projectURL: URL { URL(string: "https://modrinth.com/mod/\(slug)")! }
}

struct ModrinthCompatibilityDependency: Identifiable, Hashable, Sendable {
    let projectID: String
    let versionID: String?
    let slug: String
    let title: String
    let versionNumber: String?

    var id: String { versionID ?? projectID }
    var displayName: String {
        [title, versionNumber].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        .joined(separator: " ")
    }
}

struct ModrinthInstalledModReference: Identifiable, Hashable, Sendable {
    let projectID: String
    let versionID: String
    let title: String
    let versionNumber: String

    var id: String { "\(projectID):\(versionID)" }
    var displayName: String {
        [title, versionNumber].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct ModrinthCompatibilityNotice: Identifiable, Hashable, Sendable {
    let dependency: ModrinthCompatibilityDependency
    let installedMod: ModrinthInstalledModReference

    var id: String { "\(dependency.id):\(installedMod.id)" }

    var detail: String {
        if dependency.versionNumber == nil && installedMod.title == dependency.title {
            return "当前已安装的 \(installedMod.displayName) 根据版本信息可能不兼容。"
        }
        return "当前已安装的 \(installedMod.displayName) 与 \(dependency.displayName) 根据版本信息可能不兼容。"
    }

    static func incompatibilityNotices(
        dependencies: [ModrinthCompatibilityDependency],
        installedMods: [ModrinthInstalledModReference]
    ) -> [ModrinthCompatibilityNotice] {
        dependencies.flatMap { dependency in
            installedMods.compactMap { installedMod in
                if let versionID = dependency.versionID {
                    guard installedMod.versionID == versionID else { return nil }
                } else {
                    guard installedMod.projectID == dependency.projectID else { return nil }
                }
                return ModrinthCompatibilityNotice(dependency: dependency, installedMod: installedMod)
            }
        }
    }
}

struct ModrinthVersionOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let versionNumber: String
    let gameVersions: [String]
    let loaders: [String]
    let versionType: String?
    let datePublished: Date?
    let primaryFileName: String?

    var supportedMinecraftVersionsText: String {
        gameVersions.prefix(6).joined(separator: ", ")
            + (gameVersions.count > 6 ? " 等 \(gameVersions.count) 个版本" : "")
    }

    var loadersText: String {
        loaders.joined(separator: ", ")
    }
}

private struct ModrinthProject: Decodable, Sendable {
    let id: String
    let slug: String
    let title: String
    let iconURL: URL?

    private enum CodingKeys: String, CodingKey {
        case id, slug, title
        case iconURL = "icon_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        slug = try container.decode(String.self, forKey: .slug)
        title = try container.decode(String.self, forKey: .title)
        iconURL = try container.decodeIfPresent(String.self, forKey: .iconURL).flatMap(URL.init(string:))
    }
}

private struct ModrinthVersion: Decodable, Sendable {
    let id: String
    let projectID: String
    let name: String
    let versionNumber: String
    let gameVersions: [String]
    let loaders: [String]
    let versionType: String?
    let datePublished: Date?
    let dependencies: [Dependency]
    let files: [File]

    struct Dependency: Decodable, Sendable {
        let versionID: String?
        let projectID: String?
        let dependencyType: String

        private enum CodingKeys: String, CodingKey {
            case versionID = "version_id"
            case projectID = "project_id"
            case dependencyType = "dependency_type"
        }
    }

    struct File: Decodable, Sendable {
        let hashes: [String: String]
        let url: URL
        let filename: String
        let primary: Bool?
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, dependencies, files, loaders
        case projectID = "project_id"
        case versionNumber = "version_number"
        case gameVersions = "game_versions"
        case versionType = "version_type"
        case datePublished = "date_published"
    }

    var option: ModrinthVersionOption {
        ModrinthVersionOption(
            id: id,
            name: name,
            versionNumber: versionNumber,
            gameVersions: gameVersions,
            loaders: loaders,
            versionType: versionType,
            datePublished: datePublished,
            primaryFileName: primaryFile?.filename
        )
    }

    var primaryFile: File? {
        files.first(where: { $0.primary == true })
            ?? files.first(where: { $0.filename.lowercased().hasSuffix(".jar") })
            ?? files.first
    }
}

actor ModrinthService {
    typealias ProgressHandler = @MainActor @Sendable (Double, String) -> Void
    typealias CheckpointHandler = FileDownloadService.CheckpointHandler

    private static let apiRoot = URL(string: "https://api.modrinth.com/v2")!
    private static let headers = [
        "User-Agent": "PigeonMuyz/SwiftLauncher (github.com/PigeonMuyz/SwiftLauncher)"
    ]

    private let http: PublicHTTPClient
    private let downloader: FileDownloadService
    private let fileSystem: LauncherFileSystem

    init(
        http: PublicHTTPClient = .shared,
        downloader: FileDownloadService = FileDownloadService(),
        fileSystem: LauncherFileSystem = .shared
    ) {
        self.http = http
        self.downloader = downloader
        self.fileSystem = fileSystem
    }

    func search(
        query: String,
        kind: ModrinthContentKind,
        gameVersion: String?,
        loader: ModLoader,
        categoryGroups: [[String]] = []
    ) async throws -> [ModrinthSearchResult] {
        var facets = [["project_type:\(kind.modrinthProjectType)"]]
        if let gameVersion {
            facets.append(["versions:\(gameVersion)"])
        }
        if gameVersion != nil, kind.requiresModLoader, loader != .vanilla {
            facets.append(["categories:\(loader.modrinthName)"])
        }
        for group in categoryGroups where !group.isEmpty {
            facets.append(group.map { "categories:\($0)" })
        }
        var components = URLComponents(
            url: Self.apiRoot.appendingPathComponent("search"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "facets", value: try jsonString(facets)),
            URLQueryItem(name: "index", value: "downloads"),
            URLQueryItem(name: "limit", value: "30")
        ]
        guard let url = components.url else { throw LauncherError.invalidResponse }
        let data = try await http.data(from: url, headers: Self.headers)
        return try JSONCoding.makeDecoder().decode(ModrinthSearchEnvelope.self, from: data).hits
    }

    func install(
        project: ModrinthSearchResult,
        kind: ModrinthContentKind,
        specificVersionID: String? = nil,
        includeRequiredDependencies: Bool,
        for instance: LauncherInstance,
        progress: @escaping ProgressHandler,
        checkpoint: CheckpointHandler? = nil
    ) async throws -> Int {
        guard kind.supportsDirectInstall else {
            throw LauncherError.unsupported(kind.detail)
        }
        guard !kind.requiresModLoader || instance.loader != .vanilla else {
            throw LauncherError.unsupported("请先为实例安装 Fabric、Quilt、Forge 或 NeoForge")
        }
        let result = try await installProject(
            projectID: project.projectID,
            kind: kind,
            specificVersionID: specificVersionID,
            instance: instance,
            installedProjects: [],
            includeRequiredDependencies: kind == .mods && includeRequiredDependencies,
            progress: progress,
            checkpoint: checkpoint
        )
        return result.count
    }

    func installPlan(
        project: ModrinthSearchResult,
        kind: ModrinthContentKind,
        selectedVersionID: String? = nil,
        for instance: LauncherInstance
    ) async throws -> ModrinthInstallPlan {
        let versions = try await compatibleVersions(
            projectID: project.projectID,
            kind: kind,
            gameVersion: kind == .modpacks ? nil : instance.versionID,
            loader: instance.loader
        )
        guard !versions.isEmpty else {
            if kind == .modpacks {
                throw LauncherError.unsupported("Modrinth 上没有可用的整合包文件")
            }
            throw LauncherError.unsupported(
                "Modrinth 上没有适配 \(kind.title) / MC \(instance.versionID) 的文件"
            )
        }
        let version = if let selectedVersionID,
                         let selected = versions.first(where: { $0.id == selectedVersionID }) {
            selected
        } else {
            versions[0]
        }

        var visited: Set<String> = [project.projectID]
        var dependencies: [ModrinthDependencyPlan] = []
        var compatibilityDependencies: [ModrinthCompatibilityDependency] = []
        let installedMods = kind == .mods ? installedModReferences(for: instance) : []
        if kind == .mods {
            try await collectRequiredDependencies(
                of: version,
                kind: kind,
                instance: instance,
                depth: 0,
                visited: &visited,
                output: &dependencies
            )
            compatibilityDependencies = await collectIncompatibleDependencies(of: version)
        }
        return ModrinthInstallPlan(
            kind: kind,
            project: project,
            versions: versions.map(\.option),
            selectedVersionID: version.id,
            versionID: version.id,
            versionName: version.name,
            versionNumber: version.versionNumber,
            requiredDependencies: dependencies,
            compatibilityNotices: ModrinthCompatibilityNotice.incompatibilityNotices(
                dependencies: compatibilityDependencies,
                installedMods: installedMods
            )
        )
    }

    func downloadModpackArchive(
        project: ModrinthSearchResult,
        specificVersionID: String?,
        instance: LauncherInstance,
        progress: @escaping ProgressHandler,
        checkpoint: CheckpointHandler? = nil
    ) async throws -> URL {
        try await checkpoint?()
        let version: ModrinthVersion
        if let specificVersionID {
            version = try await fetchVersion(id: specificVersionID)
        } else {
            guard let compatible = try await compatibleVersions(
                projectID: project.projectID,
                kind: .modpacks,
                gameVersion: nil,
                loader: instance.loader
            ).first else {
                throw LauncherError.unsupported("Modrinth 上没有可用的整合包文件")
            }
            version = compatible
        }

        guard let file = version.primaryFile else {
            throw LauncherError.missingDownload(version.name)
        }

        let fileName = URL(fileURLWithPath: file.filename).lastPathComponent
        let fallbackExtension = fileName.contains(".") ? "" : ".mrpack"
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftLauncher-\(UUID().uuidString)-\(fileName)\(fallbackExtension)")

        await progress(0.18, "正在下载 \(version.name) \(version.versionNumber)")
        try await checkpoint?()
        try await downloader.download(
            from: file.url,
            to: destination,
            expectedSHA1: file.hashes["sha1"],
            expectedSHA512: file.hashes["sha512"],
            progress: { value in
                progress(
                    0.18 + 0.82 * value,
                    "正在下载 \(version.name) \(version.versionNumber)"
                )
            },
            checkpoint: checkpoint
        )
        return destination
    }

    private func installProject(
        projectID: String,
        kind: ModrinthContentKind,
        specificVersionID: String?,
        instance: LauncherInstance,
        installedProjects: Set<String>,
        includeRequiredDependencies: Bool,
        progress: @escaping ProgressHandler,
        checkpoint: CheckpointHandler?
    ) async throws -> (count: Int, projects: Set<String>) {
        var installedProjects = installedProjects
        guard installedProjects.insert(projectID).inserted else { return (0, installedProjects) }
        try await checkpoint?()
        let version: ModrinthVersion
        if let specificVersionID {
            version = try await fetchVersion(id: specificVersionID)
        } else {
            guard let compatible = try await compatibleVersions(
                projectID: projectID,
                kind: kind,
                gameVersion: instance.versionID,
                loader: instance.loader
            ).first else {
                throw LauncherError.unsupported("Modrinth 上没有适配 \(kind.title) / MC \(instance.versionID) 的文件")
            }
            version = compatible
        }
        let project = try await fetchProject(id: projectID)

        var installedCount = 0
        for dependency in version.dependencies where includeRequiredDependencies && dependency.dependencyType == "required" {
            let dependencyProject: String
            if let projectID = dependency.projectID {
                dependencyProject = projectID
            } else if let versionID = dependency.versionID {
                dependencyProject = try await fetchVersion(id: versionID).projectID
            } else {
                continue
            }
            let dependencyResult = try await installProject(
                projectID: dependencyProject,
                kind: kind,
                specificVersionID: dependency.versionID,
                instance: instance,
                installedProjects: installedProjects,
                includeRequiredDependencies: true,
                progress: progress,
                checkpoint: checkpoint
            )
            installedCount += dependencyResult.count
            installedProjects = dependencyResult.projects
        }

        guard let file = version.primaryFile else {
            throw LauncherError.missingDownload(version.name)
        }
        let contentDirectory = contentDirectory(for: kind, instance: instance)
        try FileManager.default.createDirectory(at: contentDirectory, withIntermediateDirectories: true)
        let destination = contentDirectory.appendingPathComponent(URL(fileURLWithPath: file.filename).lastPathComponent)
        let temporaryDestination = contentDirectory
            .appendingPathComponent(".swiftlauncher-download-\(UUID().uuidString).\(fileExtension(for: kind))")
        await progress(
            min(0.15 + Double(installedProjects.count) * 0.12, 0.9),
            "正在安装 \(version.name) \(version.versionNumber)"
        )
        try await checkpoint?()
        let baseProgress = min(0.15 + Double(installedProjects.count) * 0.12, 0.9)
        let span = min(0.08, max(0, 0.96 - baseProgress))
        try await downloader.download(
            from: file.url,
            to: temporaryDestination,
            expectedSHA1: file.hashes["sha1"],
            expectedSHA512: file.hashes["sha512"],
            progress: { value in
                progress(
                    baseProgress + span * value,
                    "正在下载 \(version.name) \(version.versionNumber)"
                )
            },
            checkpoint: checkpoint
        )
        try await checkpoint?()
        if kind == .mods {
            try await removeInstalledVersions(
                of: projectID,
                in: contentDirectory,
                excluding: temporaryDestination
            )
        }
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryDestination, to: destination)
        if kind == .mods {
            try recordInstalledMod(
                fileName: destination.lastPathComponent,
                project: project,
                version: version,
                in: contentDirectory
            )
        }
        installedCount += 1
        return (installedCount, installedProjects)
    }

    private func collectRequiredDependencies(
        of version: ModrinthVersion,
        kind: ModrinthContentKind,
        instance: LauncherInstance,
        depth: Int,
        visited: inout Set<String>,
        output: inout [ModrinthDependencyPlan]
    ) async throws {
        for dependency in version.dependencies where dependency.dependencyType == "required" {
            let dependencyVersion: ModrinthVersion
            if let versionID = dependency.versionID {
                dependencyVersion = try await fetchVersion(id: versionID)
            } else if let projectID = dependency.projectID,
                      let compatible = try await compatibleVersions(
                        projectID: projectID,
                        kind: kind,
                        gameVersion: instance.versionID,
                        loader: instance.loader
                      ).first {
                dependencyVersion = compatible
            } else {
                continue
            }

            let projectID = dependency.projectID ?? dependencyVersion.projectID
            guard visited.insert(projectID).inserted else { continue }
            let project = try await fetchProject(id: projectID)
            output.append(
                ModrinthDependencyPlan(
                    projectID: projectID,
                    slug: project.slug,
                    title: project.title,
                    versionID: dependencyVersion.id,
                    versionName: dependencyVersion.name,
                    versionNumber: dependencyVersion.versionNumber,
                    iconURL: project.iconURL,
                    depth: depth
                )
            )
            try await collectRequiredDependencies(
                of: dependencyVersion,
                kind: kind,
                instance: instance,
                depth: depth + 1,
                visited: &visited,
                output: &output
            )
        }
    }

    private func collectIncompatibleDependencies(
        of version: ModrinthVersion
    ) async -> [ModrinthCompatibilityDependency] {
        var output: [ModrinthCompatibilityDependency] = []
        for dependency in version.dependencies where dependency.dependencyType == "incompatible" {
            if let versionID = dependency.versionID,
               let dependencyVersion = try? await fetchVersion(id: versionID) {
                let projectID = dependency.projectID ?? dependencyVersion.projectID
                let project = try? await fetchProject(id: projectID)
                output.append(
                    ModrinthCompatibilityDependency(
                        projectID: projectID,
                        versionID: versionID,
                        slug: project?.slug ?? projectID,
                        title: project?.title ?? projectID,
                        versionNumber: dependencyVersion.versionNumber
                    )
                )
            } else if let projectID = dependency.projectID {
                let project = try? await fetchProject(id: projectID)
                output.append(
                    ModrinthCompatibilityDependency(
                        projectID: projectID,
                        versionID: nil,
                        slug: project?.slug ?? projectID,
                        title: project?.title ?? projectID,
                        versionNumber: nil
                    )
                )
            }
        }
        return output
    }

    private func installedModReferences(for instance: LauncherInstance) -> [ModrinthInstalledModReference] {
        let modsDirectory = contentDirectory(for: .mods, instance: instance)
        let index = ModrinthInstalledModsIndexStore.load(from: modsDirectory)
        return index.records.values.map { record in
            ModrinthInstalledModReference(
                projectID: record.projectID,
                versionID: record.versionID,
                title: record.title,
                versionNumber: record.versionNumber
            )
        }
    }

    private func removeInstalledVersions(
        of projectID: String,
        in modsDirectory: URL,
        excluding excludedURL: URL
    ) async throws {
        var index = ModrinthInstalledModsIndexStore.load(from: modsDirectory)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: modsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for url in contents where url != excludedURL {
            guard url.pathExtension.lowercased() == "jar" || url.pathExtension.lowercased() == "disabled" else {
                continue
            }
            if index.records[url.lastPathComponent]?.projectID == projectID {
                try? FileManager.default.removeItem(at: url)
                index.records.removeValue(forKey: url.lastPathComponent)
                continue
            }

            guard let resolvedProjectID = try? await resolveProjectID(forModFile: url),
                  resolvedProjectID == projectID else {
                continue
            }
            try? FileManager.default.removeItem(at: url)
            index.records.removeValue(forKey: url.lastPathComponent)
        }

        try ModrinthInstalledModsIndexStore.save(index, to: modsDirectory)
    }

    private func recordInstalledMod(
        fileName: String,
        project: ModrinthProject,
        version: ModrinthVersion,
        in modsDirectory: URL
    ) throws {
        var index = ModrinthInstalledModsIndexStore.load(from: modsDirectory)
        index.records[fileName] = ModrinthInstalledModRecord(
            projectID: project.id,
            versionID: version.id,
            title: project.title,
            versionNumber: version.versionNumber,
            iconURLString: project.iconURL?.absoluteString
        )
        try ModrinthInstalledModsIndexStore.save(index, to: modsDirectory)
    }

    private func resolveProjectID(forModFile url: URL) async throws -> String? {
        let hash = try Hashing.sha512(fileAt: url)
        var components = URLComponents(
            url: Self.apiRoot.appendingPathComponent("version_file").appendingPathComponent(hash),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "algorithm", value: "sha512")]
        guard let lookupURL = components.url else { throw LauncherError.invalidResponse }
        let data = try await http.data(from: lookupURL, headers: Self.headers)
        return try JSONCoding.makeDecoder().decode(ModrinthVersion.self, from: data).projectID
    }

    private func compatibleVersions(
        projectID: String,
        kind: ModrinthContentKind,
        gameVersion: String?,
        loader: ModLoader
    ) async throws -> [ModrinthVersion] {
        var components = URLComponents(
            url: Self.apiRoot
                .appendingPathComponent("project")
                .appendingPathComponent(projectID)
                .appendingPathComponent("version"),
            resolvingAgainstBaseURL: false
        )!
        var queryItems = [
            URLQueryItem(name: "include_changelog", value: "false")
        ]
        if let gameVersion {
            queryItems.append(URLQueryItem(name: "game_versions", value: try jsonString([gameVersion])))
        }
        if kind.requiresModLoader {
            queryItems.append(URLQueryItem(name: "loaders", value: try jsonString([loader.modrinthName])))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw LauncherError.invalidResponse }
        let data = try await http.data(from: url, headers: Self.headers)
        return try JSONCoding.makeDecoder().decode([ModrinthVersion].self, from: data)
    }

    private func fetchVersion(id: String) async throws -> ModrinthVersion {
        let url = Self.apiRoot.appendingPathComponent("version").appendingPathComponent(id)
        return try JSONCoding.makeDecoder().decode(
            ModrinthVersion.self,
            from: try await http.data(from: url, headers: Self.headers)
        )
    }

    private func fetchProject(id: String) async throws -> ModrinthProject {
        let url = Self.apiRoot.appendingPathComponent("project").appendingPathComponent(id)
        return try JSONCoding.makeDecoder().decode(
            ModrinthProject.self,
            from: try await http.data(from: url, headers: Self.headers)
        )
    }

    private func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw LauncherError.invalidResponse
        }
        return string
    }

    private func contentDirectory(for kind: ModrinthContentKind, instance: LauncherInstance) -> URL {
        let gameDirectory = fileSystem.gameDirectory(instance)
        switch kind {
        case .mods:
            return gameDirectory.appendingPathComponent("mods", isDirectory: true)
        case .resourcePacks:
            return gameDirectory.appendingPathComponent("resourcepacks", isDirectory: true)
        case .shaderPacks:
            return gameDirectory.appendingPathComponent("shaderpacks", isDirectory: true)
        case .dataPacks:
            return gameDirectory.appendingPathComponent("datapacks", isDirectory: true)
        case .modpacks:
            return gameDirectory.appendingPathComponent("modpacks", isDirectory: true)
        }
    }

    private func fileExtension(for kind: ModrinthContentKind) -> String {
        switch kind {
        case .mods: "jar"
        case .resourcePacks, .shaderPacks: "zip"
        case .dataPacks, .modpacks: "zip"
        }
    }
}

private extension ModLoader {
    nonisolated var modrinthName: String {
        switch self {
        case .vanilla: "minecraft"
        case .fabric: "fabric"
        case .quilt: "quilt"
        case .forge: "forge"
        case .neoForge: "neoforge"
        }
    }
}
