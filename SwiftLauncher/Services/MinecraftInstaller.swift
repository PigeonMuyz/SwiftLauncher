import Foundation

private enum LocalArtifactValidation {
    case checksum
    case sizeOnly
}

enum InstallationCheckResult: Sendable {
    case complete
    case incomplete(InstallationIssue)

    var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }

    var issue: InstallationIssue? {
        if case .incomplete(let issue) = self { return issue }
        return nil
    }
}

enum InstallationIssue: LocalizedError, Sendable {
    case missingFile(String, String)
    case unreadableFile(String, String)
    case invalidJSON(String, String)
    case mismatch(String)
    case missingDownload(String)
    case sizeMismatch(String, String)
    case checksumUnreadable(String, String)
    case checksumMismatch(String, String)
    case incomplete(String)

    var errorDescription: String? {
        switch self {
        case .missingFile(let name, let path):
            "安装不完整：缺少\(name)（\(path)）。"
        case .unreadableFile(let name, let reason):
            "安装不完整：无法读取\(name)。原因：\(reason)"
        case .invalidJSON(let name, let reason):
            "安装不完整：\(name) 已损坏或格式不正确。原因：\(reason)"
        case .mismatch(let message):
            "安装不完整：\(message)。"
        case .missingDownload(let name):
            "安装不完整：版本元数据缺少下载项 \(name)。"
        case .sizeMismatch(let name, let path):
            "安装不完整：\(name) 文件大小不匹配（\(path)）。"
        case .checksumUnreadable(let name, let reason):
            "安装不完整：无法校验\(name)。原因：\(reason)"
        case .checksumMismatch(let name, let path):
            "安装不完整：\(name) 校验失败（\(path)）。"
        case .incomplete(let message):
            "安装不完整：\(message)。"
        }
    }

    var repairDetail: String {
        switch self {
        case .missingFile(let name, _): "\(name) 缺失"
        case .unreadableFile(let name, _): "\(name) 无法读取"
        case .invalidJSON(let name, _): "\(name) 已损坏"
        case .mismatch(let message): message
        case .missingDownload(let name): "缺少下载项 \(name)"
        case .sizeMismatch(let name, _): "\(name) 大小不匹配"
        case .checksumUnreadable(let name, _): "\(name) 无法校验"
        case .checksumMismatch(let name, _): "\(name) 校验失败"
        case .incomplete(let message): message
        }
    }
}

actor MinecraftInstaller {
    typealias ProgressHandler = @MainActor @Sendable (Double, String) -> Void

    private let metadataService: MojangMetadataService
    private let downloader: FileDownloadService
    private let fileSystem: LauncherFileSystem
    private let loaderService: LoaderMetadataService
    private let javaService: JavaRuntimeService

    init(
        metadataService: MojangMetadataService,
        downloader: FileDownloadService,
        fileSystem: LauncherFileSystem,
        loaderService: LoaderMetadataService = LoaderMetadataService(),
        javaService: JavaRuntimeService = JavaRuntimeService()
    ) {
        self.metadataService = metadataService
        self.downloader = downloader
        self.fileSystem = fileSystem
        self.loaderService = loaderService
        self.javaService = javaService
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
        let metadata = try await loadMetadata(for: version)
        let metadataData = try JSONCoding.makeEncoder().encode(metadata)
        try metadataData.write(to: fileSystem.versionJSON(version.id), options: [.atomic])

        let requiredJava = metadata.javaVersion?.majorVersion ?? 8
        let java = try await javaService.ensureRuntime(
            majorVersion: requiredJava,
            customPath: instance.usesAutomaticJava ? nil : instance.javaPath,
            allowsDownload: UserDefaults.standard.object(forKey: "autoDownloadJava") as? Bool ?? true,
            progress: progress
        )

        let evaluator = RuleEvaluator()
        let allowedLibraries = metadata.libraries.filter { evaluator.allows($0.rules) }
        let baseCheck = checkBaseInstallation(
            version: version,
            metadata: metadata,
            libraries: allowedLibraries
        )

        if let issue = baseCheck.issue {
            await progress(0.08, "正在修复官方基础版本：\(issue.repairDetail)")
            try await installBaseVersion(
                version: version,
                metadata: metadata,
                metadataData: metadataData,
                libraries: allowedLibraries,
                progress: progress
            )
        } else {
            await progress(0.45, "官方基础版本 \(version.id) 已存在，正在复用")
        }

        // Use the game's own pack.png as the default instance artwork. This is
        // extracted from the locally downloaded Mojang client instead of
        // bundling or imitating Minecraft artwork in the launcher.
        try? await fileSystem.ensureMinecraftIcon(for: version.id)

        if requiresExtractedNatives(allowedLibraries), !nativesAreReady(at: nativesDirectory) {
            try await installNatives(
                libraries: allowedLibraries,
                destination: nativesDirectory,
                progress: progress
            )
        }

        if let assetIndexReference = metadata.assetIndex {
            let indexURL = assetIndexURL(assetIndexReference.id)
            let assetIndex = try JSONCoding.makeDecoder().decode(AssetIndex.self, from: Data(contentsOf: indexURL))
            try materializeLegacyAssets(index: assetIndex, indexID: assetIndexReference.id, gameDirectory: gameDirectory)
        }

        if instance.loader != .vanilla, !loaderInstallationIsComplete(instance) {
            switch instance.loader {
            case .fabric, .quilt:
                try await installMetadataLoader(for: instance, progress: progress)
            case .forge, .neoForge:
                try await installInstallerLoader(for: instance, java: java, progress: progress)
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
            loader: instance.loader,
            loaderVersion: instance.loaderVersion,
            installedAt: .now,
            source: "Mojang 官方"
        )
        try JSONCoding.makeEncoder().encode(marker)
            .write(to: fileSystem.installationMarker(instance.id), options: [.atomic])
        await progress(1, "安装完成，所有文件已校验")
    }

    func installationIsComplete(
        instance: LauncherInstance,
        version: MinecraftVersion
    ) -> Bool {
        checkInstallation(instance: instance, version: version).isComplete
    }

    func checkInstallation(
        instance: LauncherInstance,
        version: MinecraftVersion
    ) -> InstallationCheckResult {
        let metadataURL = fileSystem.versionJSON(version.id)
        guard FileManager.default.fileExists(atPath: metadataURL.path) else {
            return .incomplete(.missingFile("版本元数据", metadataURL.path))
        }
        let metadataData: Data
        do {
            metadataData = try Data(contentsOf: metadataURL)
        } catch {
            return .incomplete(.unreadableFile("版本元数据", error.localizedDescription))
        }

        let metadata: VersionMetadata
        do {
            metadata = try JSONCoding.makeDecoder().decode(VersionMetadata.self, from: metadataData)
        } catch {
            return .incomplete(.invalidJSON("版本元数据", error.localizedDescription))
        }

        let allowedLibraries = metadata.libraries.filter { RuleEvaluator().allows($0.rules) }
        let baseCheck = checkBaseInstallation(
            version: version,
            metadata: metadata,
            libraries: allowedLibraries
        )
        guard baseCheck.isComplete else { return baseCheck }

        let markerURL = fileSystem.installationMarker(instance.id)
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            return .incomplete(.missingFile("实例安装标记", markerURL.path))
        }
        let markerData: Data
        do {
            markerData = try Data(contentsOf: markerURL)
        } catch {
            return .incomplete(.unreadableFile("实例安装标记", error.localizedDescription))
        }

        let marker: InstallationMarker
        do {
            marker = try JSONCoding.makeDecoder().decode(InstallationMarker.self, from: markerData)
        } catch {
            return .incomplete(.invalidJSON("实例安装标记", error.localizedDescription))
        }

        guard marker.versionID == instance.versionID else {
            return .incomplete(.mismatch("实例安装标记指向 \(marker.versionID)，不是 \(instance.versionID)"))
        }
        guard marker.loader == instance.loader,
              marker.loaderVersion == instance.loaderVersion else {
            return .incomplete(.mismatch("实例安装标记中的加载器配置已过期"))
        }
        guard nativesInstallationIsComplete(
            libraries: allowedLibraries,
            directory: fileSystem.nativesDirectory(instance.id)
        ) else {
            return .incomplete(.incomplete("原生库尚未解压完成"))
        }
        guard loaderInstallationIsComplete(instance) else {
            return .incomplete(.incomplete("加载器安装不完整或配置损坏"))
        }
        return .complete
    }

    private func loadMetadata(for version: MinecraftVersion) async throws -> VersionMetadata {
        let localURL = fileSystem.versionJSON(version.id)
        if let data = try? Data(contentsOf: localURL),
           let metadata = try? JSONCoding.makeDecoder().decode(VersionMetadata.self, from: data),
           metadata.id == version.id {
            return metadata
        }
        return try await metadataService.fetchMetadata(for: version)
    }

    private func installBaseVersion(
        version: MinecraftVersion,
        metadata: VersionMetadata,
        metadataData: Data,
        libraries: [MinecraftLibrary],
        progress: @escaping ProgressHandler
    ) async throws {
        guard let client = metadata.downloads?["client"] else {
            throw LauncherError.missingDownload("client")
        }
        await progress(0.10, "正在补全官方游戏核心")
        try await downloader.download(
            from: client.url,
            to: fileSystem.versionJAR(version.id),
            expectedSHA1: client.sha1
        )

        let libraryArtifacts = libraries.compactMap { library -> (DownloadArtifact, URL)? in
            guard let artifact = library.downloads?.artifact else { return nil }
            let relativePath = artifact.path ?? MavenCoordinate.path(for: library.name)
            return (artifact, fileSystem.librariesRoot.appendingPathComponent(relativePath))
        }
        try await downloadInBatches(
            libraryArtifacts,
            baseProgress: 0.14,
            span: 0.30,
            label: "正在补全官方依赖库",
            progress: progress
        )

        if let assetIndexReference = metadata.assetIndex {
            await progress(0.48, "正在读取官方资源索引")
            let indexData = try await downloader.data(
                from: assetIndexReference.url,
                expectedSHA1: assetIndexReference.sha1
            )
            try indexData.write(to: assetIndexURL(assetIndexReference.id), options: [.atomic])

            let assetIndex = try JSONCoding.makeDecoder().decode(AssetIndex.self, from: indexData)
            let objects = assetIndex.objects.values.map { object -> (DownloadArtifact, URL) in
                let prefix = String(object.hash.prefix(2))
                let remote = URL(string: "https://resources.download.minecraft.net/\(prefix)/\(object.hash)")!
                return (
                    DownloadArtifact(sha1: object.hash, size: object.size, url: remote, path: nil),
                    assetObjectURL(hash: object.hash)
                )
            }
            await progress(0.50, "正在检查本地官方资源")
            let assetPlan = reusableDownloadPlan(objects, validation: .sizeOnly)
            try await downloadInBatches(
                assetPlan.items,
                baseProgress: 0.50,
                span: 0.40,
                label: "正在补全官方资源",
                reusedCount: assetPlan.reused,
                concurrency: 48,
                existingFileValidation: .sizeOnly,
                progress: progress
            )
        }

        if let clientLogging = metadata.logging?["client"], let file = clientLogging.file {
            let destination = loggingConfigurationURL(file)
            try await downloader.download(from: file.url, to: destination, expectedSHA1: file.sha1)
        }

        let marker = BaseInstallationMarker(
            formatVersion: 1,
            versionID: version.id,
            manifestMetadataSHA1: version.sha1,
            localMetadataSHA1: Hashing.sha1(metadataData),
            installedAt: .now
        )
        try JSONCoding.makeEncoder().encode(marker)
            .write(to: fileSystem.baseInstallationMarker(version.id), options: [.atomic])
    }

    private func checkBaseInstallation(
        version: MinecraftVersion,
        metadata: VersionMetadata,
        libraries: [MinecraftLibrary]
    ) -> InstallationCheckResult {
        let markerURL = fileSystem.baseInstallationMarker(version.id)
        guard FileManager.default.fileExists(atPath: markerURL.path) else {
            return .incomplete(.missingFile("基础安装标记", markerURL.path))
        }
        let markerData: Data
        do {
            markerData = try Data(contentsOf: markerURL)
        } catch {
            return .incomplete(.unreadableFile("基础安装标记", error.localizedDescription))
        }

        let marker: BaseInstallationMarker
        do {
            marker = try JSONCoding.makeDecoder().decode(BaseInstallationMarker.self, from: markerData)
        } catch {
            return .incomplete(.invalidJSON("基础安装标记", error.localizedDescription))
        }

        guard marker.formatVersion == 1 else {
            return .incomplete(.mismatch("基础安装标记格式不兼容"))
        }
        guard marker.versionID == version.id else {
            return .incomplete(.mismatch("基础安装标记指向 \(marker.versionID)，不是 \(version.id)"))
        }
        guard marker.manifestMetadataSHA1 == version.sha1 else {
            return .incomplete(.mismatch("基础安装标记与版本清单不匹配"))
        }

        let metadataURL = fileSystem.versionJSON(version.id)
        let metadataFileSHA1: String
        do {
            metadataFileSHA1 = try Hashing.sha1(fileAt: metadataURL)
        } catch {
            return .incomplete(.checksumUnreadable("版本元数据", error.localizedDescription))
        }
        guard metadataFileSHA1 == marker.localMetadataSHA1 else {
            return .incomplete(.checksumMismatch("版本元数据", metadataURL.path))
        }

        guard let client = metadata.downloads?["client"] else {
            return .incomplete(.missingDownload("client"))
        }
        if let issue = fileMatchIssue(client, at: fileSystem.versionJAR(version.id), name: "游戏核心 Jar") {
            return .incomplete(issue)
        }

        for library in libraries {
            guard let artifact = library.downloads?.artifact else { continue }
            let relativePath = artifact.path ?? MavenCoordinate.path(for: library.name)
            let url = fileSystem.librariesRoot.appendingPathComponent(relativePath)
            guard fileHasSize(artifact.size, at: url) else {
                return .incomplete(.sizeMismatch("依赖库 \(library.name)", url.path))
            }
        }

        if let reference = metadata.assetIndex {
            let indexURL = assetIndexURL(reference.id)
            if let issue = fileMatchIssue(
                DownloadArtifact(sha1: reference.sha1, size: reference.size, url: reference.url, path: nil),
                at: indexURL,
                name: "资源索引 \(reference.id)"
            ) {
                return .incomplete(issue)
            }

            let indexData: Data
            do {
                indexData = try Data(contentsOf: indexURL)
            } catch {
                return .incomplete(.unreadableFile("资源索引 \(reference.id)", error.localizedDescription))
            }

            let index: AssetIndex
            do {
                index = try JSONCoding.makeDecoder().decode(AssetIndex.self, from: indexData)
            } catch {
                return .incomplete(.invalidJSON("资源索引 \(reference.id)", error.localizedDescription))
            }
            for object in index.objects.values {
                let url = assetObjectURL(hash: object.hash)
                guard fileHasSize(object.size, at: url) else {
                    return .incomplete(.sizeMismatch("资源对象 \(object.hash)", url.path))
                }
            }
        }

        if let file = metadata.logging?["client"]?.file,
           let issue = fileMatchIssue(file, at: loggingConfigurationURL(file), name: "日志配置") {
            return .incomplete(issue)
        }
        return .complete
    }

    private func loaderInstallationIsComplete(_ instance: LauncherInstance) -> Bool {
        guard instance.loader != .vanilla else { return true }
        let url = fileSystem.loaderProfile(instance.id)
        guard let data = try? Data(contentsOf: url) else { return false }

        switch instance.loader {
        case .fabric, .quilt:
            guard let profile = try? JSONCoding.makeDecoder().decode(LoaderProfile.self, from: data) else {
                return false
            }
            return profile.libraries.allSatisfy { library in
                let path = MavenCoordinate.path(for: library.name)
                return fileHasSize(library.size, at: fileSystem.librariesRoot.appendingPathComponent(path))
            }
        case .forge, .neoForge:
            guard let metadata = try? JSONCoding.makeDecoder().decode(VersionMetadata.self, from: data) else {
                return false
            }
            return metadata.libraries.allSatisfy { library in
                guard let artifact = library.downloads?.artifact else { return true }
                let path = artifact.path ?? MavenCoordinate.path(for: library.name)
                return fileHasSize(artifact.size, at: fileSystem.librariesRoot.appendingPathComponent(path))
            }
        case .vanilla:
            return true
        }
    }

    private func nativesAreReady(at directory: URL) -> Bool {
        guard let contents = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        while let fileURL = contents.nextObject() as? URL {
            let fileExtension = fileURL.pathExtension.lowercased()
            if fileExtension == "dylib" || fileExtension == "jnilib" {
                return true
            }
        }
        return false
    }

    private func requiresExtractedNatives(_ libraries: [MinecraftLibrary]) -> Bool {
        libraries.contains { library in
            guard let classifier = library.natives?["osx"] else { return false }
            let architecture = ProcessInfo.processInfo.machineArchitecture
            let resolved = classifier.replacingOccurrences(
                of: "${arch}",
                with: architecture == "arm64" ? "arm64" : "64"
            )
            return library.downloads?.classifiers?[resolved] != nil
        }
    }

    private func nativesInstallationIsComplete(
        libraries: [MinecraftLibrary],
        directory: URL
    ) -> Bool {
        !requiresExtractedNatives(libraries) || nativesAreReady(at: directory)
    }

    private func fileMatches(_ artifact: DownloadArtifact, at url: URL) -> Bool {
        fileMatchIssue(artifact, at: url, name: url.lastPathComponent) == nil
    }

    private func fileMatchIssue(_ artifact: DownloadArtifact, at url: URL, name: String) -> InstallationIssue? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return .missingFile(name, url.path)
        }
        if let size = artifact.size, !fileHasSize(size, at: url) {
            return .sizeMismatch(name, url.path)
        }
        if let sha1 = artifact.sha1, !sha1.isEmpty {
            do {
                let actual = try Hashing.sha1(fileAt: url)
                if actual != sha1.lowercased() {
                    return .checksumMismatch(name, url.path)
                }
            } catch {
                return .checksumUnreadable(name, error.localizedDescription)
            }
        }
        return nil
    }

    private func fileHasSize(_ expectedSize: Int64?, at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let expectedSize else { return true }
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        return Int64(size ?? -1) == expectedSize
    }

    private func assetIndexURL(_ id: String) -> URL {
        fileSystem.assetsRoot
            .appendingPathComponent("indexes", isDirectory: true)
            .appendingPathComponent("\(id).json")
    }

    private func assetObjectURL(hash: String) -> URL {
        fileSystem.assetsRoot
            .appendingPathComponent("objects", isDirectory: true)
            .appendingPathComponent(String(hash.prefix(2)), isDirectory: true)
            .appendingPathComponent(hash)
    }

    private func loggingConfigurationURL(_ file: DownloadArtifact) -> URL {
        fileSystem.assetsRoot
            .appendingPathComponent("log_configs", isDirectory: true)
            .appendingPathComponent(file.path ?? file.url.lastPathComponent)
    }

    private func downloadInBatches(
        _ items: [(DownloadArtifact, URL)],
        baseProgress: Double,
        span: Double,
        label: String,
        reusedCount: Int = 0,
        concurrency: Int = 16,
        existingFileValidation: FileDownloadService.ExistingFileValidation = .checksum,
        progress: @escaping ProgressHandler
    ) async throws {
        guard !items.isEmpty else {
            let reusedText = reusedCount > 0 ? "，复用 \(reusedCount) 个" : ""
            await progress(baseProgress + span, "\(label)（无需下载\(reusedText)）")
            return
        }
        let maxConcurrentDownloads = max(1, min(concurrency, items.count))
        var completed = 0
        var nextIndex = 0

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<maxConcurrentDownloads {
                let item = items[nextIndex]
                nextIndex += 1
                group.addTask { [downloader] in
                    try await downloader.download(
                        from: item.0.url,
                        to: item.1,
                        expectedSize: item.0.size,
                        expectedSHA1: item.0.sha1,
                        existingFileValidation: existingFileValidation
                    )
                }
            }

            while try await group.next() != nil {
                completed += 1
                let fraction = Double(completed) / Double(items.count)
                let reusedText = reusedCount > 0 ? "，复用 \(reusedCount) 个" : ""
                await progress(
                    baseProgress + span * fraction,
                    "\(label)（\(completed)/\(items.count)\(reusedText)）"
                )

                if nextIndex < items.count {
                    let item = items[nextIndex]
                    nextIndex += 1
                    group.addTask { [downloader] in
                        try await downloader.download(
                            from: item.0.url,
                            to: item.1,
                            expectedSize: item.0.size,
                            expectedSHA1: item.0.sha1,
                            existingFileValidation: existingFileValidation
                        )
                    }
                }
            }
        }
    }

    private func reusableDownloadPlan(
        _ items: [(DownloadArtifact, URL)],
        validation: LocalArtifactValidation
    ) -> (items: [(DownloadArtifact, URL)], reused: Int) {
        var missing: [(DownloadArtifact, URL)] = []
        var reused = 0
        for item in items {
            if localArtifactMatches(item.0, at: item.1, validation: validation) {
                reused += 1
            } else {
                missing.append(item)
            }
        }
        return (missing, reused)
    }

    private func localArtifactMatches(
        _ artifact: DownloadArtifact,
        at url: URL,
        validation: LocalArtifactValidation
    ) -> Bool {
        switch validation {
        case .checksum:
            fileMatches(artifact, at: url)
        case .sizeOnly:
            fileHasSize(artifact.size, at: url)
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

        // 将 .dylib 文件从子目录移动到根目录
        // LWJGL 3.x 的 natives 被打包在 macos/arm64/org/lwjgl/ 等嵌套结构中
        // 但是 LWJGL 期望它们在 natives 目录的根目录下
        let enumerator = FileManager.default.enumerator(
            at: destination,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension == "dylib" || fileURL.pathExtension == "jnilib" || fileURL.pathExtension == "so" {
                let targetURL = destination.appendingPathComponent(fileURL.lastPathComponent)
                if fileURL.standardizedFileURL == targetURL.standardizedFileURL {
                    continue
                }
                if FileManager.default.fileExists(atPath: targetURL.path) {
                    try? FileManager.default.removeItem(at: targetURL)
                }
                try FileManager.default.moveItem(at: fileURL, to: targetURL)
            }
        }

        // 清理 META-INF 和其他子目录
        let metaInf = destination.appendingPathComponent("META-INF", isDirectory: true)
        try? FileManager.default.removeItem(at: metaInf)

        // 清理 macos 子目录（已经移动了 dylib）
        let macosDir = destination.appendingPathComponent("macos", isDirectory: true)
        try? FileManager.default.removeItem(at: macosDir)
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
            let relativePath = MavenCoordinate.path(for: library.name)
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
        java: JavaRuntime,
        progress: @escaping ProgressHandler
    ) async throws {
        guard let loaderVersion = instance.loaderVersion else {
            throw LauncherError.unsupported("没有选择 \(instance.loader.title) 版本")
        }
        let installerCoordinate = LoaderVersionResolver.installerCoordinate(
            gameVersion: instance.versionID,
            loader: instance.loader,
            loaderVersion: loaderVersion
        )
        let installerURL: URL
        switch instance.loader {
        case .forge:
            installerURL = URL(
                string: "https://maven.minecraftforge.net/net/minecraftforge/forge/\(installerCoordinate)/forge-\(installerCoordinate)-installer.jar"
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

        await progress(0.96, "正在运行 \(instance.loader.title) 官方安装器")
        try ensureLauncherProfilesExist()
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: fileSystem.versionsRoot.path)) ?? [])
        let mirrorCandidates = installerMirrors(for: instance.loader)
        var installerLogs: [String] = []
        var installed = false
        for mirror in mirrorCandidates {
            let result = try runLoaderInstaller(
                javaPath: java.path,
                installer: installer,
                destination: fileSystem.minecraftRoot,
                mirror: mirror
            )
            installerLogs.append(result.output)
            if result.status == 0 {
                installed = true
                break
            }
        }
        guard installed else {
            throw LauncherError.processFailed(installerLogs.joined(separator: "\n\n--- 重试下载源 ---\n\n"))
        }

        let after = Set((try? FileManager.default.contentsOfDirectory(atPath: fileSystem.versionsRoot.path)) ?? [])
        let expectedVersionDirectory: String
        switch instance.loader {
        case .forge:
            let build = installerCoordinate.split(separator: "-").last.map(String.init) ?? loaderVersion
            expectedVersionDirectory = "\(instance.versionID)-forge-\(build)"
        case .neoForge:
            expectedVersionDirectory = "neoforge-\(loaderVersion)"
        default:
            expectedVersionDirectory = ""
        }
        let candidates = after.subtracting(before).filter {
            $0.localizedCaseInsensitiveContains(instance.loader == .forge ? "forge" : "neoforge")
        }
        let versionDirectory = after.contains(expectedVersionDirectory) ? expectedVersionDirectory
            : candidates.sorted().last
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

    private func installerMirrors(for loader: ModLoader) -> [URL?] {
        guard loader == .forge else { return [nil] }
        // Forge concatenates the Maven path directly, so the trailing slash is required.
        let bmcl = URL(string: "https://bmclapi2.bangbang93.com/maven/")!
        switch DownloadEndpointResolver.selectedSource {
        case .automatic: return [nil, bmcl]
        case .official: return [nil]
        case .bmclapi: return [bmcl, nil]
        }
    }

    private func runLoaderInstaller(
        javaPath: String,
        installer: URL,
        destination: URL,
        mirror: URL?
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: javaPath)
        // Forge/NeoForge write installer.log relative to the process working directory.
        // A GUI app can inherit "/" as its working directory, which is read-only on macOS.
        let workingDirectory = installer.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        process.currentDirectoryURL = workingDirectory
        var arguments = ["-jar", installer.path, "--installClient", destination.path]
        if let mirror {
            arguments += ["--mirror", mirror.absoluteString]
        }
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let logData = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let source = mirror?.absoluteString ?? "Forge 官方源"
        return (
            process.terminationStatus,
            "下载源：\(source)\n工作目录：\(workingDirectory.path)\n\(String(decoding: logData, as: UTF8.self))"
        )
    }

    private func ensureLauncherProfilesExist() throws {
        let profilesURL = fileSystem.minecraftRoot.appendingPathComponent("launcher_profiles.json")
        guard !FileManager.default.fileExists(atPath: profilesURL.path) else { return }

        // Forge's client installer refuses a valid Minecraft directory when this
        // launcher-owned compatibility file is absent, even if the base version
        // and all assets have already been installed.
        let document: [String: Any] = [
            "profiles": [String: Any](),
            "settings": [String: Any](),
            "version": 3
        ]
        let data = try JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: profilesURL, options: [.atomic])
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

}

private struct InstallationMarker: Codable {
    let instanceID: UUID
    let versionID: String
    let loader: ModLoader
    let loaderVersion: String?
    let installedAt: Date
    let source: String
}

private struct BaseInstallationMarker: Codable {
    let formatVersion: Int
    let versionID: String
    let manifestMetadataSHA1: String
    let localMetadataSHA1: String
    let installedAt: Date
}
