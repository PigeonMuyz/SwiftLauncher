import Foundation

actor JavaRuntimeService {
    typealias ProgressHandler = @MainActor @Sendable (Double, String) -> Void

    private let fileSystem: LauncherFileSystem
    private let http: PublicHTTPClient

    init(
        fileSystem: LauncherFileSystem = .shared,
        http: PublicHTTPClient = .shared
    ) {
        self.fileSystem = fileSystem
        self.http = http
    }

    func discover(additionalPaths: [String] = []) async -> [JavaRuntime] {
        let managedRoot = fileSystem.runtimesRoot
        return await Task.detached(priority: .utility) {
            var candidates = Set(additionalPaths)

            if let output = try? ProcessRunner.run(
                executable: URL(fileURLWithPath: "/usr/libexec/java_home"),
                arguments: ["-V"],
                mergeError: true
            ) {
                for line in output.split(separator: "\n") {
                    if let range = line.range(of: "/Library/Java/JavaVirtualMachines/") {
                        candidates.insert(String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces))
                    }
                }
            }

            let commonRoots = [
                "/Library/Java/JavaVirtualMachines",
                NSString(string: "~/Library/Java/JavaVirtualMachines").expandingTildeInPath
            ]
            for root in commonRoots {
                guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
                for entry in entries {
                    candidates.insert(URL(fileURLWithPath: root)
                        .appendingPathComponent(entry)
                        .appendingPathComponent("Contents/Home").path)
                }
            }

            if let environmentHome = ProcessInfo.processInfo.environment["JAVA_HOME"] {
                candidates.insert(environmentHome)
            }

            candidates.formUnion(Self.managedJavaCandidates(in: managedRoot))

            return candidates.compactMap(Self.inspect(path:))
                .uniqued(by: \JavaRuntime.path)
                .sorted {
                    if $0.majorVersion == $1.majorVersion {
                        return Self.runtimePriority($0) > Self.runtimePriority($1)
                    }
                    return $0.majorVersion > $1.majorVersion
                }
        }.value
    }

    func runtime(at selectedURL: URL) async throws -> JavaRuntime {
        let path = selectedURL.path
        return try await Task.detached(priority: .userInitiated) {
            guard let runtime = Self.inspect(path: path) else {
                throw LauncherError.invalidJava("请选择 Java Home 文件夹或 bin/java 可执行文件")
            }
            return runtime
        }.value
    }

    func ensureRuntime(
        majorVersion: Int,
        customPath: String?,
        allowsDownload: Bool,
        progress: ProgressHandler? = nil
    ) async throws -> JavaRuntime {
        if let customPath {
            guard let runtime = Self.inspect(path: customPath) else {
                throw LauncherError.invalidJava(customPath)
            }
            return runtime
        }

        let installed = await discover()
        if let exact = installed.first(where: { $0.majorVersion == majorVersion }) {
            return exact
        }
        guard allowsDownload else { throw LauncherError.missingJava }

        await progress?(0.02, "正在查找 Java \(majorVersion) 运行时")
        let asset = try await releaseAsset(majorVersion: majorVersion)
        await progress?(0.04, "正在下载 Java \(majorVersion) · \(asset.architecture)")
        let archiveData = try await http.data(from: asset.package.link)
        guard Hashing.sha256(archiveData) == asset.package.checksum.lowercased() else {
            throw LauncherError.checksumMismatch(asset.package.name)
        }

        try await fileSystem.prepare()
        let downloads = fileSystem.runtimesRoot.appendingPathComponent("downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        let archive = downloads.appendingPathComponent(asset.package.name)
        try archiveData.write(to: archive, options: [.atomic])

        let destination = fileSystem.runtimesRoot.appendingPathComponent(
            "temurin-\(majorVersion)-\(asset.architecture)",
            isDirectory: true
        )
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        await progress?(0.07, "正在安装 Java \(majorVersion) 运行时")
        _ = try await Task.detached(priority: .utility) {
            try ProcessRunner.runData(
                executable: URL(fileURLWithPath: "/usr/bin/tar"),
                arguments: ["-xzf", archive.path, "-C", destination.path]
            )
        }.value
        try? FileManager.default.removeItem(at: archive)

        guard let runtime = Self.managedJavaCandidates(in: destination)
            .compactMap(Self.inspect(path:))
            .first(where: { $0.majorVersion == majorVersion }) else {
            throw LauncherError.invalidJava("下载完成，但未找到 Java \(majorVersion) 可执行文件")
        }
        await progress?(0.09, "Java \(majorVersion) 已准备完成")
        return runtime
    }

    private func releaseAsset(majorVersion: Int) async throws -> ManagedJavaAsset {
        let machine = ProcessInfo.processInfo.machineArchitecture
        let nativeArchitecture = machine == "arm64" ? "aarch64" : "x64"
        var requests = [
            (architecture: nativeArchitecture, imageType: "jre"),
            (architecture: nativeArchitecture, imageType: "jdk")
        ]
        if nativeArchitecture == "aarch64" {
            // Temurin 8 currently has no macOS aarch64 build; the x64 runtime can run through Rosetta.
            requests += [
                (architecture: "x64", imageType: "jre"),
                (architecture: "x64", imageType: "jdk")
            ]
        }

        for request in requests {
            var components = URLComponents(
                string: "https://api.adoptium.net/v3/assets/latest/\(majorVersion)/hotspot"
            )!
            components.queryItems = [
                URLQueryItem(name: "architecture", value: request.architecture),
                URLQueryItem(name: "image_type", value: request.imageType),
                URLQueryItem(name: "os", value: "mac"),
                URLQueryItem(name: "vendor", value: "eclipse")
            ]
            let data = try await http.data(from: components.url!)
            if let release = try JSONCoding.makeDecoder().decode([AdoptiumRelease].self, from: data).first {
                return ManagedJavaAsset(
                    architecture: request.architecture,
                    package: release.binary.package
                )
            }
        }
        throw LauncherError.unsupported("Adoptium 暂无适用于此 Mac 的 Java \(majorVersion) 运行时")
    }

    private nonisolated static func inspect(path: String) -> JavaRuntime? {
        let selected = URL(fileURLWithPath: path)
        let candidates = [
            selected,
            selected.appendingPathComponent("bin/java"),
            selected.appendingPathComponent("Contents/Home/bin/java")
        ]
        guard let javaURL = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path) && $0.lastPathComponent == "java"
        }) else { return nil }

        guard let output = try? ProcessRunner.run(
            executable: javaURL,
            arguments: ["-XshowSettings:properties", "-version"],
            mergeError: true
        ) else { return nil }

        let properties = Dictionary(
            uniqueKeysWithValues: output.split(separator: "\n").compactMap { line -> (String, String)? in
                let pieces = line.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard pieces.count == 2 else { return nil }
                return (pieces[0], pieces[1])
            }
        )

        let version = properties["java.version"] ?? "未知"
        return JavaRuntime(
            path: javaURL.path,
            version: version,
            majorVersion: parseMajorVersion(version),
            architecture: properties["os.arch"] ?? "未知",
            vendor: properties["java.vendor"] ?? "未知"
        )
    }

    private nonisolated static func managedJavaCandidates(in root: URL) -> Set<String> {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }

        var result = Set<String>()
        for case let url as URL in enumerator where url.lastPathComponent == "java" {
            if url.path.hasSuffix("/bin/java"), FileManager.default.isExecutableFile(atPath: url.path) {
                result.insert(url.path)
            }
        }
        return result
    }

    private nonisolated static func parseMajorVersion(_ version: String) -> Int {
        let pieces = version.split(separator: ".")
        if pieces.first == "1", pieces.count > 1 { return Int(pieces[1]) ?? 0 }
        return Int(pieces.first?.prefix { $0.isNumber } ?? "0") ?? 0
    }

    private nonisolated static func runtimePriority(_ runtime: JavaRuntime) -> Int {
        let current = ProcessInfo.processInfo.machineArchitecture
        if current == "arm64", runtime.architecture == "aarch64" || runtime.architecture == "arm64" { return 2 }
        if current.contains("x86"), runtime.architecture.contains("64") { return 2 }
        return 1
    }
}

enum ProcessRunner {
    static func run(
        executable: URL,
        arguments: [String],
        mergeError: Bool = false
    ) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = mergeError ? pipe : Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            throw LauncherError.processFailed(String(data: data, encoding: .utf8) ?? "未知错误")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func runData(executable: URL, arguments: [String]) throws -> Data {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            throw LauncherError.processFailed(
                String(data: errorData, encoding: .utf8) ?? "命令执行失败"
            )
        }
        return data
    }
}

private struct AdoptiumRelease: Decodable {
    let binary: Binary

    struct Binary: Decodable {
        let package: Package
    }

    struct Package: Decodable {
        let checksum: String
        let link: URL
        let name: String
        let size: Int64
    }
}

private struct ManagedJavaAsset {
    let architecture: String
    let package: AdoptiumRelease.Package
}

private extension Sequence {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
