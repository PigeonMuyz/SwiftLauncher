import Foundation

struct VersionManifest: Codable, Sendable {
    let latest: LatestVersions
    let versions: [MinecraftVersion]
}

struct LatestVersions: Codable, Sendable {
    let release: String
    let snapshot: String
}

struct MinecraftVersion: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let type: VersionType
    let url: URL
    let time: Date
    let releaseTime: Date
    let sha1: String
    let complianceLevel: Int?
}

enum VersionType: String, Codable, CaseIterable, Sendable {
    case release
    case snapshot
    case oldBeta = "old_beta"
    case oldAlpha = "old_alpha"

    var title: String {
        switch self {
        case .release: "正式版"
        case .snapshot: "快照"
        case .oldBeta: "远古测试版"
        case .oldAlpha: "远古开发版"
        }
    }

    var colorName: String {
        switch self {
        case .release: "green"
        case .snapshot: "blue"
        case .oldBeta, .oldAlpha: "orange"
        }
    }
}

struct VersionMetadata: Codable, Sendable {
    let id: String
    let type: VersionType?
    let mainClass: String
    let assets: String?
    let assetIndex: AssetIndexReference?
    let downloads: [String: DownloadArtifact]?
    let libraries: [MinecraftLibrary]
    let arguments: MinecraftArguments?
    let minecraftArguments: String?
    let javaVersion: JavaVersionRequirement?
    let logging: [String: LoggingConfiguration]?
    let inheritsFrom: String?
}

struct JavaVersionRequirement: Codable, Sendable {
    let component: String?
    let majorVersion: Int
}

struct DownloadArtifact: Codable, Sendable {
    let sha1: String?
    let size: Int64?
    let url: URL
    let path: String?
}

struct AssetIndexReference: Codable, Sendable {
    let id: String
    let sha1: String?
    let size: Int64?
    let totalSize: Int64?
    let url: URL
}

struct AssetIndex: Codable, Sendable {
    let objects: [String: AssetObject]
    let virtual: Bool?
    let mapToResources: Bool?

    enum CodingKeys: String, CodingKey {
        case objects
        case virtual
        case mapToResources = "map_to_resources"
    }
}

struct AssetObject: Codable, Sendable {
    let hash: String
    let size: Int64
}

struct MinecraftLibrary: Codable, Sendable {
    let name: String
    let url: String?
    let sha1: String?
    let downloads: LibraryDownloads?
    let natives: [String: String]?
    let rules: [MinecraftRule]?
    let extract: ExtractRules?
}

struct LibraryDownloads: Codable, Sendable {
    let artifact: DownloadArtifact?
    let classifiers: [String: DownloadArtifact]?
}

struct ExtractRules: Codable, Sendable {
    let exclude: [String]?
}

struct MinecraftRule: Codable, Sendable {
    let action: RuleAction
    let os: RuleOS?
    let features: [String: Bool]?
}

enum RuleAction: String, Codable, Sendable {
    case allow
    case disallow
}

struct RuleOS: Codable, Sendable {
    let name: String?
    let version: String?
    let arch: String?
}

struct MinecraftArguments: Codable, Sendable {
    let game: [MinecraftArgument]?
    let jvm: [MinecraftArgument]?
}

enum MinecraftArgument: Codable, Sendable {
    case literal(String)
    case conditional(rules: [MinecraftRule], values: [String])

    private enum CodingKeys: String, CodingKey {
        case rules
        case value
    }

    init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(String.self) {
            self = .literal(value)
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rules = try container.decode([MinecraftRule].self, forKey: .rules)
        if let value = try? container.decode(String.self, forKey: .value) {
            self = .conditional(rules: rules, values: [value])
        } else {
            self = .conditional(rules: rules, values: try container.decode([String].self, forKey: .value))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .literal(let value):
            var container = encoder.singleValueContainer()
            try container.encode(value)
        case .conditional(let rules, let values):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(rules, forKey: .rules)
            if values.count == 1 {
                try container.encode(values[0], forKey: .value)
            } else {
                try container.encode(values, forKey: .value)
            }
        }
    }
}

struct LoggingConfiguration: Codable, Sendable {
    let argument: String?
    let file: DownloadArtifact?
    let type: String?
}
