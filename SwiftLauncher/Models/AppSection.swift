import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case home
    case instances
    case downloads
    case accounts

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "首页"
        case .instances: "游戏实例"
        case .downloads: "下载"
        case .accounts: "账户"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .instances: "shippingbox"
        case .downloads: "arrow.down.circle"
        case .accounts: "person.crop.circle"
        }
    }
}
