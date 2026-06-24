import Foundation

actor ModManager {
    private let fileSystem: LauncherFileSystem

    init(fileSystem: LauncherFileSystem) {
        self.fileSystem = fileSystem
    }

    func list(for instance: LauncherInstance) throws -> [ModFile] {
        let directory = try modsDirectory(for: instance)
        let index = ModrinthInstalledModsIndexStore.load(from: directory)
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
            let record = index.records[url.lastPathComponent]
            return ModFile(
                url: url,
                fileName: url.lastPathComponent,
                size: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate,
                isEnabled: url.pathExtension.lowercased() == "jar",
                modrinthProjectID: record?.projectID,
                modrinthVersionID: record?.versionID,
                modrinthTitle: record?.title,
                modrinthVersionNumber: record?.versionNumber,
                iconURL: record?.iconURL
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
        var index = ModrinthInstalledModsIndexStore.load(from: mod.url.deletingLastPathComponent())
        if let record = index.records.removeValue(forKey: mod.url.lastPathComponent) {
            index.records[destination.lastPathComponent] = record
            try ModrinthInstalledModsIndexStore.save(index, to: destination.deletingLastPathComponent())
        }
    }

    func remove(_ mod: ModFile) throws {
        try FileManager.default.removeItem(at: mod.url)
        var index = ModrinthInstalledModsIndexStore.load(from: mod.url.deletingLastPathComponent())
        if index.records.removeValue(forKey: mod.url.lastPathComponent) != nil {
            try ModrinthInstalledModsIndexStore.save(index, to: mod.url.deletingLastPathComponent())
        }
    }

    func listContent(_ kind: ManagedContentKind, for instance: LauncherInstance) throws -> [ManagedContentFile] {
        let directory = try contentDirectory(kind, for: instance)
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey, .isDirectoryKey]
        return try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        .compactMap { url in
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true || values?.isDirectory == true else { return nil }
            return ManagedContentFile(
                url: url,
                fileName: url.lastPathComponent,
                size: Int64(values?.fileSize ?? 0),
                modifiedAt: values?.contentModificationDate,
                isDirectory: values?.isDirectory == true
            )
        }
        .sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
    }

    func importContent(_ sourceURLs: [URL], kind: ManagedContentKind, for instance: LauncherInstance) throws {
        let directory = try contentDirectory(kind, for: instance)
        for source in sourceURLs {
            let accessed = source.startAccessingSecurityScopedResource()
            defer { if accessed { source.stopAccessingSecurityScopedResource() } }
            guard source.hasDirectoryPath || source.pathExtension.lowercased() == "zip" else { continue }
            var destination = directory.appendingPathComponent(source.lastPathComponent)
            var suffix = 2
            while FileManager.default.fileExists(atPath: destination.path) {
                let stem = source.deletingPathExtension().lastPathComponent
                let extensionName = source.pathExtension
                let candidate = extensionName.isEmpty ? "\(stem)-\(suffix)" : "\(stem)-\(suffix).\(extensionName)"
                destination = directory.appendingPathComponent(candidate)
                suffix += 1
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    func removeContent(_ file: ManagedContentFile) throws {
        try FileManager.default.removeItem(at: file.url)
    }

    private func modsDirectory(for instance: LauncherInstance) throws -> URL {
        let directory = fileSystem.gameDirectory(instance).appendingPathComponent("mods", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func contentDirectory(_ kind: ManagedContentKind, for instance: LauncherInstance) throws -> URL {
        let directory = fileSystem.gameDirectory(instance).appendingPathComponent(kind.directoryName, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
