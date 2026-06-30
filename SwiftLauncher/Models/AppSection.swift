import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case mods
    case resourcePacks
    case shaders
    case downloads
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .mods: "模组管理"
        case .resourcePacks: "资源包"
        case .shaders: "光影包"
        case .downloads: "下载"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .mods: "cube.box"
        case .resourcePacks: "photo.stack"
        case .shaders: "sparkles"
        case .downloads: "arrow.down.circle"
        case .settings: "gearshape"
        }
    }
}
