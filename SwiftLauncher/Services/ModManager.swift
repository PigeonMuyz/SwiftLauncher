import Foundation

actor ModManager {
    private let fileSystem: LauncherFileSystem

    init(fileSystem: LauncherFileSystem) {
        self.fileSystem = fileSystem
    }

    func list(for instance: LauncherInstance) throws -> [ModFile] {
        let directory = try modsDirectory(for: instance)
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        .compactMap { url in
            guard url.pathExtension.lowercased() == "jar" || url.pathExtension.lowercased() == "disabled" else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true else { return nil }
            return ModFile(
                url: url,
                fileName: url.lastPathComponent,
                size: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate,
                isEnabled: url.pathExtension.lowercased() == "jar"
            )
        }
        .sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
    }

    func importFiles(_ sourceURLs: [URL], for instance: LauncherInstance) throws {
        let directory = try modsDirectory(for: instance)
        for source in sourceURLs {
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            guard source.pathExtension.lowercased() == "jar" else { continue }
            var destination = directory.appendingPathComponent(source.lastPathComponent)
            var suffix = 2
            while FileManager.default.fileExists(atPath: destination.path) {
                let stem = source.deletingPathExtension().lastPathComponent
                destination = directory.appendingPathComponent("\(stem)-\(suffix).jar")
                suffix += 1
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    func setEnabled(_ mod: ModFile, enabled: Bool) throws {
        guard mod.isEnabled != enabled else { return }
        let destination: URL
        if enabled {
            destination = mod.url.deletingPathExtension()
        } else {
            destination = mod.url.appendingPathExtension("disabled")
        }
        try FileManager.default.moveItem(at: mod.url, to: destination)
    }

    func remove(_ mod: ModFile) throws {
        try FileManager.default.removeItem(at: mod.url)
    }

    private func modsDirectory(for instance: LauncherInstance) throws -> URL {
        let directory = fileSystem.gameDirectory(instance).appendingPathComponent("mods", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
