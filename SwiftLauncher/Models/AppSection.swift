import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case downloadVersions
    case downloadTasks
    case libraryMods
    case libraryShaders
    case libraryResourcePacks
    case libraryDataPacks
    case libraryModpacks
    case instanceResources
    case instanceSettings
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .downloadVersions: "游戏版本"
        case .downloadTasks: "下载任务"
        case .libraryMods: "模组"
        case .libraryShaders: "光影包"
        case .libraryResourcePacks: "资源包"
        case .libraryDataPacks: "数据包"
        case .libraryModpacks: "整合包"
        case .instanceResources: "资源管理"
        case .instanceSettings: "实例设置"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .downloadVersions: "shippingbox"
        case .downloadTasks: "list.bullet.rectangle"
        case .libraryMods: "puzzlepiece.extension"
        case .libraryShaders: "sparkles"
        case .libraryResourcePacks: "photo.stack"
        case .libraryDataPacks: "doc.text"
        case .libraryModpacks: "archivebox"
        case .instanceResources: "folder.badge.gearshape"
        case .instanceSettings: "slider.horizontal.3"
        case .settings: "gearshape"
        }
    }
}
