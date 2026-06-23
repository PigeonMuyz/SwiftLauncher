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

        print("latest.release=\(manifest.latest.release)")
        print("versions=\(manifest.versions.count)")
        print("smoke.version=\(metadata.id)")
        print("client.sha1=\(try Hashing.sha1(fileAt: clientURL))")
        print("asset.sha1=\(try Hashing.sha1(fileAt: objectDestination))")
        print("fabric.version=\(fabricVersion.version)")
        print("fabric.mainClass=\(profile.mainClass)")
        print("fabric.library.sha1=\(try Hashing.sha1(fileAt: loaderDestination))")
        print("forge.version=\(forgeVersion.version)")
        print("neoforge.version=\(neoForgeVersion.version)")
        print("result=passed")
    }
}
