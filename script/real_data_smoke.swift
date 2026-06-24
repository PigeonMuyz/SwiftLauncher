import Foundation

@main
struct RealDataSmoke {
    static func main() async throws {
        let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/real-data-smoke", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let metadataService = MojangMetadataService()
        let downloader = FileDownloadService()
        let manifest = try await metadataService.fetchManifest()
        let mirrorManifestURL = URL(
            string: "https://bmclapi2.bangbang93.com/mc/game/version_manifest_v2.json"
        )!
        let mirrorManifestData = try await PublicHTTPClient.shared.data(from: mirrorManifestURL)
        let mirrorManifest = try JSONCoding.makeDecoder().decode(VersionManifest.self, from: mirrorManifestData)
        guard mirrorManifest.versions.contains(where: { $0.id == manifest.latest.release }) else {
            throw LauncherError.unsupported("BMCLAPI 版本清单未同步官方最新正式版")
        }
        guard let version = manifest.versions.first(where: { $0.id == "rd-132211" }) else {
            throw LauncherError.unsupported("官方清单中没有 rd-132211")
        }
        let metadata = try await metadataService.fetchMetadata(for: version)
        guard let client = metadata.downloads?["client"] else {
            throw LauncherError.missingDownload("client")
        }

        let clientURL = output.appendingPathComponent("client.jar")
        try await downloader.download(from: client.url, to: clientURL, expectedSHA1: client.sha1)

        guard let indexReference = metadata.assetIndex else {
            throw LauncherError.missingDownload("assetIndex")
        }
        let indexData = try await downloader.data(from: indexReference.url, expectedSHA1: indexReference.sha1)
        let index = try JSONCoding.makeDecoder().decode(AssetIndex.self, from: indexData)
        guard let object = index.objects.sorted(by: { $0.key < $1.key }).first?.value else {
            throw LauncherError.invalidResponse
        }
        let prefix = String(object.hash.prefix(2))
        let objectURL = URL(string: "https://resources.download.minecraft.net/\(prefix)/\(object.hash)")!
        let objectDestination = output.appendingPathComponent(object.hash)
        try await downloader.download(from: objectURL, to: objectDestination, expectedSHA1: object.hash)

        let loaderService = LoaderMetadataService()
        let fabricVersions = try await loaderService.versions(for: "1.21.11", loader: .fabric)
        guard let fabricVersion = fabricVersions.first else {
            throw LauncherError.unsupported("Fabric 没有返回 1.21.11 的加载器")
        }
        let profile = try await loaderService.profile(
            for: "1.21.11",
            loader: .fabric,
            loaderVersion: fabricVersion.version
        )
        guard let loaderLibrary = profile.libraries.first,
              let base = URL(string: loaderLibrary.url) else {
            throw LauncherError.invalidResponse
        }
        let pieces = loaderLibrary.name.split(separator: ":").map(String.init)
        let loaderPath = "\(pieces[0].replacingOccurrences(of: ".", with: "/"))/\(pieces[1])/\(pieces[2])/\(pieces[1])-\(pieces[2]).jar"
        let loaderURL = URL(string: loaderPath, relativeTo: base)!.absoluteURL
        let loaderDestination = output.appendingPathComponent("fabric-library.jar")
        try await downloader.download(
            from: loaderURL,
            to: loaderDestination,
            expectedSHA1: loaderLibrary.sha1
        )
        let forgeVersions = try await loaderService.versions(for: "1.21.11", loader: .forge)
        let neoForgeVersions = try await loaderService.versions(for: "1.21.11", loader: .neoForge)
        guard let forgeVersion = forgeVersions.first, let neoForgeVersion = neoForgeVersions.first else {
            throw LauncherError.unsupported("Forge/NeoForge Maven 元数据为空")
        }
        let importedForgeCoordinate = LoaderVersionResolver.installerCoordinate(
            gameVersion: "1.20.1",
            loader: .forge,
            loaderVersion: "47.3.33"
        )
        let importedForgeSHAURL = URL(
            string: "https://maven.minecraftforge.net/net/minecraftforge/forge/\(importedForgeCoordinate)/forge-\(importedForgeCoordinate)-installer.jar.sha1"
        )!
        let importedForgeSHA = String(
            decoding: try await downloader.data(from: importedForgeSHAURL),
            as: UTF8.self
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard importedForgeSHA.count == 40 else {
            throw LauncherError.unsupported("Forge 整合包版本归一化后的安装器地址不可用")
        }

        guard let latestVersion = manifest.versions.first(where: { $0.id == manifest.latest.release }) else {
            throw LauncherError.invalidResponse
        }
        let latestMetadata = try await metadataService.fetchMetadata(for: latestVersion)
        guard let javaMajor = latestMetadata.javaVersion?.majorVersion else {
            throw LauncherError.missingJava
        }
        let architecture = ProcessInfo.processInfo.machineArchitecture == "arm64" ? "aarch64" : "x64"
        let javaAssetsURL = URL(
            string: "https://api.adoptium.net/v3/assets/latest/\(javaMajor)/hotspot?architecture=\(architecture)&image_type=jre&os=mac&vendor=eclipse"
        )!
        let javaAssetsData = try await PublicHTTPClient.shared.data(from: javaAssetsURL)
        let javaAssets = try JSONSerialization.jsonObject(with: javaAssetsData) as? [[String: Any]]
        guard javaAssets?.isEmpty == false else {
            throw LauncherError.unsupported("Adoptium 没有返回 Java \(javaMajor) macOS 运行时")
        }

        let modrinth = ModrinthService(downloader: downloader, fileSystem: .shared)
        let modResults = try await modrinth.search(
            query: "sodium",
            gameVersion: "1.21.11",
            loader: .fabric
        )
        guard modResults.contains(where: { $0.slug == "sodium" }) else {
            throw LauncherError.unsupported("Modrinth 没有返回 Sodium 搜索结果")
        }
        let irisResults = try await modrinth.search(
            query: "iris",
            gameVersion: "1.21.11",
            loader: .fabric
        )
        guard let iris = irisResults.first(where: { $0.slug == "iris" }) else {
            throw LauncherError.unsupported("Modrinth 没有返回 Iris 搜索结果")
        }
        let irisPlan = try await modrinth.installPlan(
            project: iris,
            for: LauncherInstance(
                name: "Dependency Smoke",
                versionID: "1.21.11",
                loader: .fabric,
                loaderVersion: fabricVersion.version
            )
        )
        guard irisPlan.versions.count > 1,
              irisPlan.versions.allSatisfy({
                  $0.gameVersions.contains("1.21.11") && $0.loaders.contains("fabric")
              }) else {
            throw LauncherError.unsupported("Modrinth 兼容版本列表没有保留实际 MC 版本/加载器信息")
        }
        guard irisPlan.requiredDependencies.contains(where: {
            !$0.title.isEmpty && !$0.versionNumber.isEmpty && $0.projectURL.host == "modrinth.com"
        }) else {
            throw LauncherError.unsupported("Modrinth 前置模组解析没有返回项目和版本信息")
        }
        guard let sodium = modResults.first(where: { $0.slug == "sodium" }) else {
            throw LauncherError.unsupported("Modrinth 没有返回 Sodium 项目")
        }
        let modInstallRoot = output.appendingPathComponent("mod-install-smoke", isDirectory: true)
        try? FileManager.default.removeItem(at: modInstallRoot)
        let modInstallFileSystem = LauncherFileSystem(root: modInstallRoot)
        try await modInstallFileSystem.prepare()
        let modInstallService = ModrinthService(
            downloader: downloader,
            fileSystem: modInstallFileSystem
        )
        let modInstallInstance = LauncherInstance(
            name: "Mod Install Smoke",
            versionID: "1.21.11",
            loader: .fabric,
            loaderVersion: fabricVersion.version
        )
        let sodiumPlan = try await modInstallService.installPlan(
            project: sodium,
            for: modInstallInstance
        )
        guard sodiumPlan.versions.count >= 2 else {
            throw LauncherError.unsupported("Sodium 没有足够的兼容版本用于替换测试")
        }
        _ = try await modInstallService.install(
            project: sodium,
            specificVersionID: sodiumPlan.versions[0].id,
            includeRequiredDependencies: false,
            for: modInstallInstance
        ) { _, _ in }
        _ = try await modInstallService.install(
            project: sodium,
            specificVersionID: sodiumPlan.versions[1].id,
            includeRequiredDependencies: false,
            for: modInstallInstance
        ) { _, _ in }
        let installedModsDirectory = modInstallFileSystem.gameDirectory(modInstallInstance)
            .appendingPathComponent("mods", isDirectory: true)
        let installedJARs = try FileManager.default.contentsOfDirectory(
            at: installedModsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "jar" }
        let installedIndex = ModrinthInstalledModsIndexStore.load(from: installedModsDirectory)
        guard installedJARs.count == 1,
              installedIndex.records.count == 1,
              installedIndex.records.values.first?.versionID == sodiumPlan.versions[1].id else {
            throw LauncherError.unsupported("同一 Modrinth 项目安装新版本后仍残留多个版本")
        }

        let importFixture = output.appendingPathComponent("import-fixture", isDirectory: true)
        try? FileManager.default.removeItem(at: importFixture)
        try FileManager.default.createDirectory(at: importFixture, withIntermediateDirectories: true)
        let packRoot = importFixture.appendingPathComponent("pack", isDirectory: true)
        try FileManager.default.createDirectory(at: packRoot, withIntermediateDirectories: true)
        let packIndex: [String: Any] = [
            "formatVersion": 1,
            "game": "minecraft",
            "versionId": "fixture",
            "name": "Smoke Pack",
            "dependencies": ["minecraft": "26.2"],
            "files": [[
                "path": "mods/verified-fixture.bin",
                "hashes": [
                    "sha1": object.hash,
                    "sha512": try Hashing.sha512(fileAt: objectDestination)
                ],
                "env": ["client": "required", "server": "unsupported"],
                "downloads": [objectURL.absoluteString]
            ]]
        ]
        try JSONSerialization.data(withJSONObject: packIndex)
            .write(to: packRoot.appendingPathComponent("modrinth.index.json"))
        let fixtureIcon = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=")!
        try fixtureIcon.write(to: packRoot.appendingPathComponent("icon.png"))
        let packArchive = importFixture.appendingPathComponent("smoke.mrpack")
        _ = try ProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-c", "-k", packRoot.path, packArchive.path],
            mergeError: true
        )
        let importFileSystem = LauncherFileSystem(
            root: importFixture.appendingPathComponent("app-data", isDirectory: true)
        )
        let importService = InstanceImportService(fileSystem: importFileSystem, downloader: downloader)
        let packResult = try await importService.importModpack(
            from: packArchive,
            accountID: nil,
            knownVersionIDs: Set(manifest.versions.map(\.id))
        ) { _, _ in }
        let importedPackFile = importFileSystem.gameDirectory(packResult.instance)
            .appendingPathComponent("mods/verified-fixture.bin")
        guard packResult.instance.name == "Smoke Pack",
              packResult.instance.versionID == "26.2",
              packResult.instance.iconFileName == "icon.png",
              FileManager.default.fileExists(atPath: importFileSystem.instanceIcon(packResult.instance.id).path),
              (try? Hashing.sha1(fileAt: importedPackFile)) == object.hash else {
            throw LauncherError.unsupported("Modrinth 整合包导入结果不正确")
        }

        let launcherRoot = importFixture.appendingPathComponent("other-launcher", isDirectory: true)
        let dotMinecraft = launcherRoot.appendingPathComponent(".minecraft", isDirectory: true)
        try FileManager.default.createDirectory(at: dotMinecraft, withIntermediateDirectories: true)
        let profiles = #"{"selectedProfile":"smoke","profiles":{"smoke":{"lastVersionId":"26.2"}}}"#
        try Data(profiles.utf8).write(to: dotMinecraft.appendingPathComponent("launcher_profiles.json"))
        try Data("fixture=true".utf8).write(to: dotMinecraft.appendingPathComponent("options.txt"))
        let folderResult = try await importService.importMinecraftFolder(
            from: launcherRoot,
            accountID: nil,
            knownVersionIDs: Set(manifest.versions.map(\.id))
        ) { _, _ in }
        let copiedOptions = importFileSystem.gameDirectory(folderResult.instance)
            .appendingPathComponent("options.txt")
        guard folderResult.instance.versionID == "26.2",
              FileManager.default.fileExists(atPath: copiedOptions.path) else {
            throw LauncherError.unsupported(".minecraft 文件夹导入结果不正确")
        }

        print("latest.release=\(manifest.latest.release)")
        print("versions=\(manifest.versions.count)")
        print("smoke.version=\(metadata.id)")
        print("client.sha1=\(try Hashing.sha1(fileAt: clientURL))")
        print("asset.sha1=\(try Hashing.sha1(fileAt: objectDestination))")
        print("fabric.version=\(fabricVersion.version)")
        print("fabric.mainClass=\(profile.mainClass)")
        print("fabric.library.sha1=\(try Hashing.sha1(fileAt: loaderDestination))")
        print("forge.version=\(forgeVersion.version)")
        print("forge.imported.coordinate=\(importedForgeCoordinate)")
        print("neoforge.version=\(neoForgeVersion.version)")
        print("latest.java.major=\(javaMajor)")
        print("adoptium.runtime.available=true")
        print("bmclapi.versions=\(mirrorManifest.versions.count)")
        print("modrinth.results=\(modResults.count)")
        print("modrinth.iris.versions=\(irisPlan.versions.count)")
        print("modrinth.iris.dependencies=\(irisPlan.requiredDependencies.count)")
        print("modrinth.sodium.replacement=passed")
        print("modpack.import=passed")
        print("minecraft-folder.import=passed")
        print("result=passed")
    }
}
