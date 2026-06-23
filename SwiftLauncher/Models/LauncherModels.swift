import Foundation

struct LauncherInstance: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var versionID: String
    var javaPath: String?
    var memoryMB: Int
    var resolutionWidth: Int?
    var resolutionHeight: Int?
    var additionalJVMArguments: [String]
    var loader: ModLoader
    var loaderVersion: String?
    var isVersionIsolated: Bool
    var accountID: UUID?
    let createdAt: Date
    var lastPlayedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        versionID: String,
        javaPath: String? = nil,
        memoryMB: Int = 4096,
        resolutionWidth: Int? = nil,
        resolutionHeight: Int? = nil,
        additionalJVMArguments: [String] = [],
        loader: ModLoader = .vanilla,
        loaderVersion: String? = nil,
        isVersionIsolated: Bool = true,
        accountID: UUID? = nil,
        createdAt: Date = .now,
        lastPlayedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.versionID = versionID
        self.javaPath = javaPath
        self.memoryMB = memoryMB
        self.resolutionWidth = resolutionWidth
        self.resolutionHeight = resolutionHeight
        self.additionalJVMArguments = additionalJVMArguments
        self.loader = loader
        self.loaderVersion = loaderVersion
        self.isVersionIsolated = isVersionIsolated
        self.accountID = accountID
        self.createdAt = createdAt
        self.lastPlayedAt = lastPlayedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, versionID, javaPath, memoryMB, resolutionWidth, resolutionHeight
        case additionalJVMArguments, loader, loaderVersion, isVersionIsolated
        case accountID, createdAt, lastPlayedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        versionID = try container.decode(String.self, forKey: .versionID)
        javaPath = try container.decodeIfPresent(String.self, forKey: .javaPath)
        memoryMB = try container.decodeIfPresent(Int.self, forKey: .memoryMB) ?? 4096
        resolutionWidth = try container.decodeIfPresent(Int.self, forKey: .resolutionWidth)
        resolutionHeight = try container.decodeIfPresent(Int.self, forKey: .resolutionHeight)
        additionalJVMArguments = try container.decodeIfPresent([String].self, forKey: .additionalJVMArguments) ?? []
        loader = try container.decodeIfPresent(ModLoader.self, forKey: .loader) ?? .vanilla
        loaderVersion = try container.decodeIfPresent(String.self, forKey: .loaderVersion)
        isVersionIsolated = try container.decodeIfPresent(Bool.self, forKey: .isVersionIsolated) ?? true
        accountID = try container.decodeIfPresent(UUID.self, forKey: .accountID)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
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

    var id: String { url.path }
    var displayName: String {
        fileName.replacingOccurrences(of: ".disabled", with: "")
    }
}
