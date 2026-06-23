import AppKit
import SwiftUI

@main
struct HomeRenderer {
    @MainActor
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let output = arguments.first ?? "artifacts/swiftlauncher-home-v2.png"
        let instance = LauncherInstance(
            id: UUID(uuidString: "A7EF3593-74A7-4C35-9F8F-739A761D49AE")!,
            name: "Utopia3.5",
            versionID: "1.20.1",
            javaPath: "/usr/bin/java",
            loader: .forge,
            loaderVersion: "47.3.0",
            isVersionIsolated: true,
            createdAt: Date().addingTimeInterval(-86_400),
            lastPlayedAt: .now
        )

        let fileSystem = LauncherFileSystem.shared
        try await fileSystem.prepare()
        try FileManager.default.createDirectory(
            at: fileSystem.versionDirectory(instance.versionID),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: fileSystem.instanceRoot(instance.id),
            withIntermediateDirectories: true
        )
        try Data().write(to: fileSystem.versionJAR(instance.versionID))
        try Data("{}".utf8).write(to: fileSystem.installationMarker(instance.id))

        let store = LauncherStore()
        store.instances = [instance]
        store.selectedInstanceID = instance.id
        store.javaRuntimes = [
            JavaRuntime(
                path: "/usr/bin/java",
                version: "21.0.7",
                majorVersion: 21,
                architecture: "arm64",
                vendor: "OpenJDK"
            )
        ]

        let width = arguments.dropFirst().first.flatMap(Double.init) ?? 1180
        let height = arguments.dropFirst(2).first.flatMap(Double.init) ?? 780
        let size = CGSize(width: width, height: height)
        let hostingController = NSHostingController(rootView: ContentView(store: store))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.setContentSize(size)
        window.layoutIfNeeded()

        let hostingView = hostingController.view
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw RendererError.failedToCreateBitmap
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw RendererError.failedToEncodePNG
        }
        try png.write(to: URL(fileURLWithPath: output), options: .atomic)
    }
}

private enum RendererError: Error {
    case failedToCreateBitmap
    case failedToEncodePNG
}
