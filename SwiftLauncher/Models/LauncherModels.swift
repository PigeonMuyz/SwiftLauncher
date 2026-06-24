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
        self.createdAt = createdAt
        self.lastPlayedAt = lastPlayedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, versionID, javaPath, usesAutomaticJava, memoryMB, resolutionWidth, resolutionHeight
        case additionalJVMArguments, loader, loaderVersion, isVersionIsolated
        case accountID, iconFileName, createdAt, lastPlayedAt
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
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
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

    init(
        id: UUID = UUID(),
        username: String,
        profileID: String,
        kind: AccountKind,
        tokenExpiresAt: Date? = nil
    ) {
        self.id = id
        self.username = username
        self.profileID = profileID
        self.kind = kind
        self.tokenExpiresAt = tokenExpiresAt
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

struct DownloadTaskInfo: Identifiable, Sendable {
    let id: UUID
    var title: String
    var detail: String
    var progress: Double
    var state: DownloadState
    var errorMessage: String?

    init(
        id: UUID = UUID(),
        title: String,
        detail: String = "",
        progress: Double = 0,
        state: DownloadState = .queued,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.progress = progress
        self.state = state
        self.errorMessage = errorMessage
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
