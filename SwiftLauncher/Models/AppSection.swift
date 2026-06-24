import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case home
    case mods
    case resourcePacks
    case shaders
    case downloads
    case accounts
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "首页"
        case .mods: "模组管理"
        case .resourcePacks: "资源包"
        case .shaders: "光影包"
        case .downloads: "下载"
        case .accounts: "账户"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .mods: "cube.box"
        case .resourcePacks: "photo.stack"
        case .shaders: "sparkles"
        case .downloads: "arrow.down.circle"
        case .accounts: "person.crop.circle"
        case .settings: "gearshape"
        }
    }
}
