import Foundation

enum LoaderVersionResolver {
    nonisolated static func installerCoordinate(
        gameVersion: String,
        loader: ModLoader,
        loaderVersion: String
    ) -> String {
        switch loader {
        case .forge:
            let prefix = "\(gameVersion)-"
            return loaderVersion.hasPrefix(prefix) ? loaderVersion : "\(prefix)\(loaderVersion)"
        case .vanilla, .fabric, .quilt, .neoForge:
            return loaderVersion
        }
    }
}
