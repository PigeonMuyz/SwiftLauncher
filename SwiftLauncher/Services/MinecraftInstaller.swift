import Foundation

actor MinecraftInstaller {
    typealias ProgressHandler = @MainActor @Sendable (Double, String) -> Void

    private let metadataService: MojangMetadataService
    private let downloader: FileDownloadService
    private let fileSystem: LauncherFileSystem
    private let loaderService: LoaderMetadataService

    init(
        metadataService: MojangMetadataService,
        downloader: FileDownloadService,
        fileSystem: LauncherFileSystem,
        loaderService: LoaderMetadataService = LoaderMetadataService()
    ) {
        self.metadataService = metadataService
        self.downloader = downloader
        self.fileSystem = fileSystem
        self.loaderService = loaderService
    }

    func install(
        instance: LauncherInstance,
        version: MinecraftVersion,
        progress: @escaping ProgressHandler
    ) async throws {
        try await fileSystem.prepare()
        let instanceRoot = fileSystem.instanceRoot(instance.id)
        let gameDirectory = fileSystem.gameDirectory(instance)
        let nativesDirectory = fileSystem.nativesDirectory(instance.id)
        let versionDirectory = fileSystem.versionDirectory(version.id)

        for directory in [instanceRoot, gameDirectory, nativesDirectory, versionDirectory] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        await progress(0.01, "正在读取 \(version.id) 元数据")
        let metadata = try await metadataService.fetchMetadata(for: version)
        let metadataData = try JSONCoding.makeEncoder().encode(metadata)
        try metadataData.write(to: fileSystem.versionJSON(version.id), options: [.atomic])

        guard let client = metadata.downloads?["client"] else {
            throw LauncherError.missingDownload("client")
        }
        await progress(0.05, "正在下载游戏核心")
        try await downloader.download(
            from: client.url,
            to: fileSystem.versionJAR(version.id),
            expectedSHA1: client.sha1
        )

        let evaluator = RuleEvaluator()
        let allowedLibraries = metadata.libraries.filter { evaluator.allows($0.rules) }
        let libraryArtifacts = allowedLibraries.compactMap { library -> (DownloadArtifact, URL)? in
            guard let artifact = library.downloads?.artifact else { return nil }
            let relativePath = artifact.path ?? Self.mavenPath(for: library.name)
            return (artifact, fileSystem.librariesRoot.appendingPathComponent(relativePath))
        }

        try await downloadInBatches(
            libraryArtifacts,
            baseProgress: 0.10,
            span: 0.30,
            label: "正在下载依赖库",
            progress: progress
        )

        try await installNatives(
            libraries: allowedLibraries,
            destination: nativesDirectory,
            progress: progress
        )

        if let assetIndexReference = metadata.assetIndex {
            await progress(0.48, "正在读取资源索引")
            let indexData = try await downloader.data(
                from: assetIndexReference.url,
                expectedSHA1: assetIndexReference.sha1
            )
            let indexURL = fileSystem.assetsRoot
                .appendingPathComponent("indexes", isDirectory: true)
                .appendingPathComponent("\(assetIndexReference.id).json")
            try indexData.write(to: indexURL, options: [.atomic])

            let assetIndex = try JSONCoding.makeDecoder().decode(AssetIndex.self, from: indexData)
            let objects = assetIndex.objects.values.map { object -> (DownloadArtifact, URL) in
                let prefix = String(object.hash.prefix(2))
                let remote = URL(string: "https://resources.download.minecraft.net/\(prefix)/\(object.hash)")!
                let destination = fileSystem.assetsRoot
                    .appendingPathComponent("objects", isDirectory: true)
                    .appendingPathComponent(prefix, isDirectory: true)
                    .appendingPathComponent(object.hash)
                return (
                    DownloadArtifact(sha1: object.hash, size: object.size, url: remote, path: nil),
                    destination
                )
            }
            try await downloadInBatches(
                objects,
                baseProgress: 0.50,
                span: 0.42,
                label: "正在下载游戏资源",
                progress: progress
            )
            try materializeLegacyAssets(
                index: assetIndex,
                indexID: assetIndexReference.id,
                gameDirectory: gameDirectory
            )
        }

        if let clientLogging = metadata.logging?["client"], let file = clientLogging.file {
            let destination = fileSystem.assetsRoot
                .appendingPathComponent("log_configs", isDirectory: true)
                .appendingPathComponent(file.path ?? file.url.lastPathComponent)
            try await downloader.download(from: file.url, to: destination, expectedSHA1: file.sha1)
        }

        if instance.loader != .vanilla {
            switch instance.loader {
            case .fabric, .quilt:
                try await installMetadataLoader(for: instance, progress: progress)
            case .forge, .neoForge:
                try await installInstallerLoader(for: instance, progress: progress)
            case .vanilla:
                break
            }
        }

        try FileManager.default.createDirectory(
            at: gameDirectory.appendingPathComponent("mods", isDirectory: true),
            withIntermediateDirectories: true
        )

        let marker = InstallationMarker(
            instanceID: instance.id,
            versionID: instance.versionID,
            installedAt: .now,
            source: "Mojang 官方"
        )
        try JSONCoding.makeEncoder().encode(marker)
            .write(to: fileSystem.installationMarker(instance.id), options: [.atomic])
        await progress(1, "安装完成，所有文件已校验")
    }

    private func downloadInBatches(
        _ items: [(DownloadArtifact, URL)],
        baseProgress: Double,
        span: Double,
        label: String,
        progress: @escaping ProgressHandler
    ) async throws {
        guard !items.isEmpty else { return }
        let batchSize = 12
        var completed = 0

        for start in stride(from: 0, to: items.count, by: batchSize) {
            let end = min(start + batchSize, items.count)
            let batch = Array(items[start..<end])
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (artifact, destination) in batch {
                    group.addTask { [downloader] in
                        try await downloader.download(
                            from: artifact.url,
                            to: destination,
                            expectedSHA1: artifact.sha1
                        )
                    }
                }
                try await group.waitForAll()
            }
            completed = end
            let fraction = Double(completed) / Double(items.count)
            await progress(
                baseProgress + span * fraction,
                "\(label)（\(completed)/\(items.count)）"
            )
        }
    }

    private func installNatives(
        libraries: [MinecraftLibrary],
        destination: URL,
        progress: @escaping ProgressHandler
    ) async throws {
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let architecture = ProcessInfo.processInfo.machineArchitecture

        var nativeArtifacts: [(DownloadArtifact, URL)] = []
        for library in libraries {
            guard var classifier = library.natives?["osx"] else { continue }
            classifier = classifier.replacingOccurrences(of: "${arch}", with: architecture == "arm64" ? "arm64" : "64")
            guard let artifact = library.downloads?.classifiers?[classifier] else { continue }
            let relative = artifact.path ?? "natives/\(artifact.url.lastPathComponent)"
            nativeArtifacts.append((artifact, fileSystem.librariesRoot.appendingPathComponent(relative)))
        }

        for (index, item) in nativeArtifacts.enumerated() {
            await progress(0.41 + (Double(index) / Double(max(nativeArtifacts.count, 1))) * 0.06, "正在准备原生库")
            try await downloader.download(from: item.0.url, to: item.1, expectedSHA1: item.0.sha1)
            try extractArchive(item.1, to: destination)
        }

        let metaInf = destination.appendingPathComponent("META-INF", isDirectory: true)
        try? FileManager.default.removeItem(at: metaInf)
    }

    private func installMetadataLoader(
        for instance: LauncherInstance,
        progress: @escaping ProgressHandler
    ) async throws {
        guard let loaderVersion = instance.loaderVersion else {
            throw LauncherError.unsupported("没有选择 \(instance.loader.title) 版本")
        }
        await progress(0.93, "正在读取 \(instance.loader.title) \(loaderVersion)")
        let profile = try await loaderService.profile(
            for: instance.versionID,
            loader: instance.loader,
            loaderVersion: loaderVersion
        )

        var artifacts: [(DownloadArtifact, URL)] = []
        for library in profile.libraries {
            let relativePath = Self.mavenPath(for: library.name)
            guard let base = URL(string: library.url),
                  let remote = URL(string: relativePath, relativeTo: base)?.absoluteURL else {
                continue
            }
            artifacts.append((
                DownloadArtifact(
                    sha1: library.sha1,
                    size: library.size,
                    url: remote,
                    path: relativePath
                ),
                fileSystem.librariesRoot.appendingPathComponent(relativePath)
            ))
        }
        try await downloadInBatches(
            artifacts,
            baseProgress: 0.94,
            span: 0.05,
            label: "正在下载 \(instance.loader.title) 依赖",
            progress: progress
        )
        try JSONCoding.makeEncoder().encode(profile)
            .write(to: fileSystem.loaderProfile(instance.id), options: [.atomic])
    }

    private func installInstallerLoader(
        for instance: LauncherInstance,
        progress: @escaping ProgressHandler
    ) async throws {
        guard let loaderVersion = instance.loaderVersion else {
            throw LauncherError.unsupported("没有选择 \(instance.loader.title) 版本")
        }
        let installerURL: URL
        switch instance.loader {
        case .forge:
            installerURL = URL(
                string: "https://maven.minecraftforge.net/net/minecraftforge/forge/\(loaderVersion)/forge-\(loaderVersion)-installer.jar"
            )!
        case .neoForge:
            installerURL = URL(
                string: "https://maven.neoforged.net/releases/net/neoforged/neoforge/\(loaderVersion)/neoforge-\(loaderVersion)-installer.jar"
            )!
        default:
            throw LauncherError.unsupported("\(instance.loader.title) 不使用安装器流程")
        }

        await progress(0.93, "正在下载 \(instance.loader.title) 安装器")
        let checksumData = try await downloader.data(from: installerURL.appendingPathExtension("sha1"))
        let checksum = String(decoding: checksumData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let installer = fileSystem.instanceRoot(instance.id)
            .appendingPathComponent("\(instance.loader.rawValue)-installer.jar")
        try await downloader.download(from: installerURL, to: installer, expectedSHA1: checksum)

        guard let javaPath = instance.javaPath ?? defaultJavaPath() else {
            throw LauncherError.missingJava
        }
        await progress(0.96, "正在运行 \(instance.loader.title) 官方安装器")
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: fileSystem.versionsRoot.path)) ?? [])
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: javaPath)
        process.arguments = ["-jar", installer.path, "--installClient", fileSystem.minecraftRoot.path]
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let logData = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw LauncherError.processFailed(String(decoding: logData, as: UTF8.self))
        }

        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: fileSystem.versionsRoot.path)) ?? [])
        let candidates = after.subtracting(before).filter {
            $0.localizedCaseInsensitiveContains(instance.loader == .forge ? "forge" : "neoforge")
        }
        let versionDirectory = candidates.sorted().last
            ?? after.filter { $0.localizedCaseInsensitiveContains(instance.loader == .forge ? "forge" : "neoforge") }.sorted().last
        guard let versionDirectory else {
            throw LauncherError.processFailed("安装器完成，但没有找到生成的版本 JSON")
        }
        let sourceJSON = fileSystem.versionsRoot
            .appendingPathComponent(versionDirectory, isDirectory: true)
            .appendingPathComponent("\(versionDirectory).json")
        let loaderMetadata = try Data(contentsOf: sourceJSON)
        _ = try JSONCoding.makeDecoder().decode(VersionMetadata.self, from: loaderMetadata)
        try loaderMetadata.write(to: fileSystem.loaderProfile(instance.id), options: [.atomic])
        await progress(0.99, "\(instance.loader.title) 安装完成")
    }

    private func defaultJavaPath() -> String? {
        let candidates = [
            ProcessInfo.processInfo.environment["JAVA_HOME"].map { URL(fileURLWithPath: $0).appendingPathComponent("bin/java").path },
            "/usr/bin/java"
        ].compactMap { $0 }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func extractArchive(_ archive: URL, to destination: URL) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, destination.path]
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            throw LauncherError.processFailed(String(data: data, encoding: .utf8) ?? "原生库解压失败")
        }
    }

    private func materializeLegacyAssets(
        index: AssetIndex,
        indexID: String,
        gameDirectory: URL
    ) throws {
        guard index.virtual == true || index.mapToResources == true else { return }
        let virtualRoot = fileSystem.assetsRoot
            .appendingPathComponent("virtual", isDirectory: true)
            .appendingPathComponent(indexID, isDirectory: true)
        let resourcesRoot = gameDirectory.appendingPathComponent("resources", isDirectory: true)

        for (logicalPath, object) in index.objects {
            let source = fileSystem.assetsRoot
                .appendingPathComponent("objects", isDirectory: true)
                .appendingPathComponent(String(object.hash.prefix(2)), isDirectory: true)
                .appendingPathComponent(object.hash)
            if index.virtual == true {
                try linkOrCopy(source: source, destination: virtualRoot.appendingPathComponent(logicalPath))
            }
            if index.mapToResources == true {
                try linkOrCopy(source: source, destination: resourcesRoot.appendingPathComponent(logicalPath))
            }
        }
    }

    private func linkOrCopy(source: URL, destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) { return }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            try FileManager.default.linkItem(at: source, to: destination)
        } catch {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private nonisolated static func mavenPath(for coordinate: String) -> String {
        let pieces = coordinate.split(separator: ":").map(String.init)
        guard pieces.count >= 3 else { return coordinate.replacingOccurrences(of: ":", with: "/") }
        let group = pieces[0].replacingOccurrences(of: ".", with: "/")
        let artifact = pieces[1]
        let version = pieces[2]
        return "\(group)/\(artifact)/\(version)/\(artifact)-\(version).jar"
    }
}

private struct InstallationMarker: Codable {
    let instanceID: UUID
    let versionID: String
    let installedAt: Date
    let source: String
}
