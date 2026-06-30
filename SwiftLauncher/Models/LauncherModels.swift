import Foundation

struct LauncherInstance: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var versionID: String
    var javaPath: String?
    var usesAutomaticJava: Bool
    var memoryMB: Int
    var resolutionWidth: Int?
    var resolutionHeight: Int?
    var additionalJVMArguments: [String]
    var loader: ModLoader
    var loaderVersion: String?
    var isVersionIsolated: Bool
    var accountID: UUID?
    var iconFileName: String?
    var launchTitle: String?
    var autoJoinServer: Bool
    var serverHost: String
    var serverPort: Int?
    let createdAt: Date
    var lastPlayedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        versionID: String,
        javaPath: String? = nil,
        usesAutomaticJava: Bool = true,
        memoryMB: Int = 4096,
        resolutionWidth: Int? = nil,
        resolutionHeight: Int? = nil,
        additionalJVMArguments: [String] = [],
        loader: ModLoader = .vanilla,
        loaderVersion: String? = nil,
        isVersionIsolated: Bool = true,
        accountID: UUID? = nil,
        iconFileName: String? = nil,
        launchTitle: String? = nil,
        autoJoinServer: Bool = false,
        serverHost: String = "",
        serverPort: Int? = nil,
        createdAt: Date = .now,
        lastPlayedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.versionID = versionID
        self.javaPath = javaPath
        self.usesAutomaticJava = usesAutomaticJava
        self.memoryMB = memoryMB
        self.resolutionWidth = resolutionWidth
        self.resolutionHeight = resolutionHeight
        self.additionalJVMArguments = additionalJVMArguments
        self.loader = loader
        self.loaderVersion = loaderVersion
        self.isVersionIsolated = isVersionIsolated
        self.accountID = accountID
        self.iconFileName = iconFileName
        self.launchTitle = launchTitle
        self.autoJoinServer = autoJoinServer
        self.serverHost = serverHost
        self.serverPort = serverPort
        self.createdAt = createdAt
        self.lastPlayedAt = lastPlayedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, versionID, javaPath, usesAutomaticJava, memoryMB, resolutionWidth, resolutionHeight
        case additionalJVMArguments, loader, loaderVersion, isVersionIsolated
        case accountID, iconFileName, launchTitle, autoJoinServer, serverHost, serverPort
        case createdAt, lastPlayedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        versionID = try container.decode(String.self, forKey: .versionID)
        if let automatic = try container.decodeIfPresent(Bool.self, forKey: .usesAutomaticJava) {
            usesAutomaticJava = automatic
            javaPath = try container.decodeIfPresent(String.self, forKey: .javaPath)
        } else {
            // Older builds populated javaPath automatically, so migrate those instances to real automatic mode.
            usesAutomaticJava = true
            javaPath = nil
        }
        memoryMB = try container.decodeIfPresent(Int.self, forKey: .memoryMB) ?? 4096
        resolutionWidth = try container.decodeIfPresent(Int.self, forKey: .resolutionWidth)
        resolutionHeight = try container.decodeIfPresent(Int.self, forKey: .resolutionHeight)
        additionalJVMArguments = try container.decodeIfPresent([String].self, forKey: .additionalJVMArguments) ?? []
        loader = try container.decodeIfPresent(ModLoader.self, forKey: .loader) ?? .vanilla
        loaderVersion = try container.decodeIfPresent(String.self, forKey: .loaderVersion)
        isVersionIsolated = try container.decodeIfPresent(Bool.self, forKey: .isVersionIsolated) ?? true
        accountID = try container.decodeIfPresent(UUID.self, forKey: .accountID)
        iconFileName = try container.decodeIfPresent(String.self, forKey: .iconFileName)
        launchTitle = try container.decodeIfPresent(String.self, forKey: .launchTitle)
        autoJoinServer = try container.decodeIfPresent(Bool.self, forKey: .autoJoinServer) ?? false
        serverHost = try container.decodeIfPresent(String.self, forKey: .serverHost) ?? ""
        serverPort = try container.decodeIfPresent(Int.self, forKey: .serverPort)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
    }

    var effectiveLaunchTitle: String {
        let trimmed = launchTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? name : trimmed
    }

    func hasShaderSupport(mods: [ModFile]) -> Bool {
        let shaderModIdentifiers = ["iris", "oculus", "optifine"]
        return mods.contains { mod in
            let lowerFileName = mod.fileName.lowercased()
            return shaderModIdentifiers.contains { lowerFileName.contains($0) }
        }
    }
}

enum ModLoader: String, Codable, CaseIterable, Identifiable, Sendable {
    case vanilla
    case fabric
    case quilt
    case forge
    case neoForge

    var id: Self { self }

    var title: String {
        switch self {
        case .vanilla: "原版"
        case .fabric: "Fabric"
        case .quilt: "Quilt"
        case .forge: "Forge"
        case .neoForge: "NeoForge"
        }
    }
}

enum LauncherExperienceMode: String, CaseIterable, Identifiable, Sendable {
    static let defaultsKey = "launcherExperienceMode"
    static let autoDependenciesDefaultsKey = "autoInstallRequiredMods"

    case beginner
    case normal
    case expert

    var id: Self { self }

    var title: String {
        switch self {
        case .beginner: "新手模式"
        case .normal: "普通模式"
        case .expert: "专家模式"
        }
    }

    var detail: String {
        switch self {
        case .beginner: "自动安装 Modrinth 声明的全部必需前置模组。"
        case .normal: "可以在下载时决定是否自动补全必需前置模组。"
        case .expert: "安装前展示兼容版本与前置模组详情，并提供 Modrinth 页面链接。"
        }
    }
}

enum GameLoadingWindowPreference {
    static let defaultsKey = "showGameLoadingWindow"
}

struct LoaderVersionInfo: Codable, Identifiable, Hashable, Sendable {
    let version: String
    let stable: Bool?

    var id: String { version }
}

struct LoaderProfile: Codable, Sendable {
    let id: String
    let inheritsFrom: String?
    let mainClass: String
    let arguments: MinecraftArguments?
    let libraries: [LoaderLibrary]
}

struct LoaderLibrary: Codable, Sendable {
    let name: String
    let url: String
    let sha1: String?
    let size: Int64?
}

enum AccountKind: String, Codable, Sendable {
    case local
    case microsoft

    var title: String {
        switch self {
        case .local: "本地账户"
        case .microsoft: "Microsoft 账户"
        }
    }
}

struct PlayerAccount: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var username: String
    var profileID: String
    var kind: AccountKind
    var tokenExpiresAt: Date?
    var skinURL: URL?

    init(
        id: UUID = UUID(),
        username: String,
        profileID: String,
        kind: AccountKind,
        tokenExpiresAt: Date? = nil,
        skinURL: URL? = nil
    ) {
        self.id = id
        self.username = username
        self.profileID = profileID
        self.kind = kind
        self.tokenExpiresAt = tokenExpiresAt
        self.skinURL = skinURL
    }

    var offlineSkinName: String {
        Self.offlineSkinName(for: profileID)
    }

    private static func offlineSkinName(for profileID: String) -> String {
        let names = ["alex", "ari", "efe", "kai", "makena", "noor", "steve", "sunny", "zuri"]
        let cleanID = profileID.replacingOccurrences(of: "-", with: "")
        guard cleanID.count >= 32 else { return "steve" }
        let first = String(cleanID.prefix(16))
        let second = String(cleanID.dropFirst(16).prefix(16))
        guard let left = UInt64(first, radix: 16),
              let right = UInt64(second, radix: 16) else { return "steve" }
        let mixed = (left ^ right) ^ ((left ^ right) >> 32)
        return names[Int(mixed % UInt64(names.count))]
    }
}

struct JavaRuntime: Identifiable, Hashable, Sendable {
    let path: String
    let version: String
    let majorVersion: Int
    let architecture: String
    let vendor: String

    var id: String { path }
    var displayName: String { "Java \(majorVersion) · \(architecture)" }
}

enum DownloadState: String, Sendable {
    case queued
    case downloading
    case completed
    case failed
    case cancelled

    var title: String {
        switch self {
        case .queued: "等待中"
        case .downloading: "下载中"
        case .completed: "已完成"
        case .failed: "失败"
        case .cancelled: "已取消"
        }
    }
}

enum DownloadJobKind: String, CaseIterable, Identifiable, Sendable {
    case gameInstall
    case modpackImport
    case minecraftFolderImport
    case modInstall
    case resourcePackInstall
    case shaderPackInstall
    case dataPackInstall
    case modpackInstall
    case javaRuntime

    var id: Self { self }

    var title: String {
        switch self {
        case .gameInstall: "游戏安装"
        case .modpackImport: "整合包导入"
        case .minecraftFolderImport: ".minecraft 导入"
        case .modInstall: "模组安装"
        case .resourcePackInstall: "资源包安装"
        case .shaderPackInstall: "光影包安装"
        case .dataPackInstall: "数据包安装"
        case .modpackInstall: "整合包安装"
        case .javaRuntime: "Java 运行时"
        }
    }

    var systemImage: String {
        switch self {
        case .gameInstall: "shippingbox"
        case .modpackImport: "archivebox"
        case .minecraftFolderImport: "folder.badge.plus"
        case .modInstall: "puzzlepiece.extension"
        case .resourcePackInstall: "photo.stack"
        case .shaderPackInstall: "sparkles"
        case .dataPackInstall: "doc.text"
        case .modpackInstall: "archivebox"
        case .javaRuntime: "cup.and.saucer"
        }
    }
}

enum DownloadJobPhase: String, Sendable {
    case preparing
    case resolving
    case importing
    case downloading
    case installing
    case verifying
    case finalizing

    var title: String {
        switch self {
        case .preparing: "准备"
        case .resolving: "解析"
        case .importing: "导入"
        case .downloading: "下载"
        case .installing: "安装"
        case .verifying: "校验"
        case .finalizing: "收尾"
        }
    }
}

struct DownloadTaskInfo: Identifiable, Sendable {
    let id: UUID
    var kind: DownloadJobKind
    var phase: DownloadJobPhase
    var instanceID: UUID?
    var title: String
    var detail: String
    var progress: Double
    var state: DownloadState
    var errorMessage: String?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: DownloadJobKind = .gameInstall,
        phase: DownloadJobPhase = .preparing,
        instanceID: UUID? = nil,
        title: String,
        detail: String = "",
        progress: Double = 0,
        state: DownloadState = .queued,
        errorMessage: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.kind = kind
        self.phase = phase
        self.instanceID = instanceID
        self.title = title
        self.detail = detail
        self.progress = progress
        self.state = state
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isActive: Bool {
        state == .queued || state == .downloading
    }
}

enum DownloadSource: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case official
    case bmclapi

    var id: Self { self }

    var title: String {
        switch self {
        case .automatic: "自动（官方优先）"
        case .official: "Mojang 官方"
        case .bmclapi: "BMCLAPI 镜像"
        }
    }

    var detail: String {
        switch self {
        case .automatic: "优先连接官方源，网络失败时自动切换到 BMCLAPI。"
        case .official: "始终使用 Mojang、Forge 等项目的官方地址。"
        case .bmclapi: "Minecraft 核心、资源与依赖优先使用中国大陆镜像。"
        }
    }
}

struct MicrosoftDeviceCode: Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURI: URL
    let expiresIn: Int
    let interval: Int
    let message: String
}

struct ModFile: Identifiable, Hashable, Sendable {
    let url: URL
    let fileName: String
    let size: Int64
    let modifiedAt: Date?
    let isEnabled: Bool
    let modrinthProjectID: String?
    let modrinthVersionID: String?
    let modrinthTitle: String?
    let modrinthVersionNumber: String?
    let iconURL: URL?

    var id: String { url.path }
    var displayName: String {
        modrinthTitle ?? fileName.replacingOccurrences(of: ".disabled", with: "")
    }

    var detailText: String {
        var pieces: [String] = []
        if let modrinthVersionNumber, !modrinthVersionNumber.isEmpty {
            pieces.append(modrinthVersionNumber)
        }
        pieces.append(size.formatted(.byteCount(style: .file)))
        return pieces.joined(separator: " · ")
    }
}

enum ManagedContentKind: String, CaseIterable, Identifiable, Sendable {
    case resourcePacks
    case shaderPacks

    var id: Self { self }

    var directoryName: String {
        switch self {
        case .resourcePacks: "resourcepacks"
        case .shaderPacks: "shaderpacks"
        }
    }

    var title: String {
        switch self {
        case .resourcePacks: "资源包"
        case .shaderPacks: "光影包"
        }
    }
}

enum ModrinthContentKind: String, CaseIterable, Identifiable, Sendable {
    case mods
    case resourcePacks
    case shaderPacks
    case dataPacks
    case modpacks

    var id: Self { self }

    var title: String {
        switch self {
        case .mods: "模组"
        case .resourcePacks: "资源包"
        case .shaderPacks: "光影"
        case .dataPacks: "数据包"
        case .modpacks: "整合包"
        }
    }

    var detail: String {
        switch self {
        case .mods: "按实例的 Minecraft 版本和加载器过滤，并可自动补全必需前置。"
        case .resourcePacks: "按 Minecraft 版本过滤，安装到所选实例的资源包目录。"
        case .shaderPacks: "按 Minecraft 版本过滤，安装到所选实例的光影包目录。"
        case .dataPacks: "按 Minecraft 版本过滤；数据包安装需要选择具体世界。"
        case .modpacks: "整合包会创建或导入完整实例，不安装到当前实例目录。"
        }
    }

    var systemImage: String {
        switch self {
        case .mods: "puzzlepiece.extension"
        case .resourcePacks: "photo.stack"
        case .shaderPacks: "sparkles"
        case .dataPacks: "doc.text"
        case .modpacks: "archivebox"
        }
    }

    var modrinthProjectType: String {
        switch self {
        case .mods: "mod"
        case .resourcePacks: "resourcepack"
        case .shaderPacks: "shader"
        case .dataPacks: "datapack"
        case .modpacks: "modpack"
        }
    }

    var downloadJobKind: DownloadJobKind {
        switch self {
        case .mods: .modInstall
        case .resourcePacks: .resourcePackInstall
        case .shaderPacks: .shaderPackInstall
        case .dataPacks: .dataPackInstall
        case .modpacks: .modpackInstall
        }
    }

    var managedContentKind: ManagedContentKind? {
        switch self {
        case .mods: nil
        case .resourcePacks: .resourcePacks
        case .shaderPacks: .shaderPacks
        case .dataPacks, .modpacks: nil
        }
    }

    var requiresModLoader: Bool {
        self == .mods
    }

    var supportsDirectInstall: Bool {
        switch self {
        case .mods, .resourcePacks, .shaderPacks:
            true
        case .dataPacks, .modpacks:
            false
        }
    }

    var supportsCurrentInstanceVersionFilter: Bool {
        switch self {
        case .mods, .resourcePacks, .shaderPacks, .dataPacks:
            true
        case .modpacks:
            false
        }
    }
}

struct ManagedContentFile: Identifiable, Hashable, Sendable {
    let url: URL
    let fileName: String
    let size: Int64
    let modifiedAt: Date?
    let isDirectory: Bool

    var id: String { url.path }
    var displayName: String { fileName }

    var detailText: String {
        if isDirectory { return "文件夹" }
        return size.formatted(.byteCount(style: .file))
    }
}
