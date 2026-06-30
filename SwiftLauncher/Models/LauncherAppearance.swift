import SwiftUI

enum LauncherAppearancePreference {
    static let accentColorDefaultsKey = "launcherAccentColor"
}

enum LauncherAccentColor: String, CaseIterable, Identifiable {
    case green
    case blue
    case cyan
    case purple
    case pink
    case orange

    var id: Self { self }

    var title: String {
        switch self {
        case .green: "草绿色"
        case .blue: "蓝色"
        case .cyan: "青色"
        case .purple: "紫色"
        case .pink: "粉色"
        case .orange: "橙色"
        }
    }

    var color: Color {
        switch self {
        case .green: Color(red: 0.62, green: 0.76, blue: 0.36)
        case .blue: .blue
        case .cyan: .cyan
        case .purple: .purple
        case .pink: .pink
        case .orange: .orange
        }
    }
}
