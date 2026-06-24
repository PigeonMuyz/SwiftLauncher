import Foundation

enum MavenCoordinate {
    static func path(for coordinate: String) -> String {
        let coordinateParts = coordinate.split(separator: "@", maxSplits: 1).map(String.init)
        let extensionName = coordinateParts.count == 2 ? coordinateParts[1] : "jar"
        let pieces = coordinateParts[0].split(separator: ":").map(String.init)
        guard pieces.count >= 3 else {
            return coordinate.replacingOccurrences(of: ":", with: "/")
        }

        let group = pieces[0].replacingOccurrences(of: ".", with: "/")
        let artifact = pieces[1]
        let version = pieces[2]
        let classifier = pieces.count > 3 ? "-\(pieces[3])" : ""
        return "\(group)/\(artifact)/\(version)/\(artifact)-\(version)\(classifier).\(extensionName)"
    }
}
