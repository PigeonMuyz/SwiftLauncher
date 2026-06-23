import Foundation

struct JavaRuntimeService: Sendable {
    func discover() async -> [JavaRuntime] {
        await Task.detached(priority: .utility) {
            var homes = Set<String>()

            if let output = try? ProcessRunner.run(
                executable: URL(fileURLWithPath: "/usr/libexec/java_home"),
                arguments: ["-V"],
                mergeError: true
            ) {
                for line in output.split(separator: "\n") {
                    if let range = line.range(of: "/Library/Java/JavaVirtualMachines/") {
                        let path = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                        homes.insert(path)
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
                    homes.insert(URL(fileURLWithPath: root)
                        .appendingPathComponent(entry)
                        .appendingPathComponent("Contents/Home").path)
                }
            }

            if let environmentHome = ProcessInfo.processInfo.environment["JAVA_HOME"] {
                homes.insert(environmentHome)
            }

            return homes.compactMap(Self.inspect(home:))
                .sorted {
                    if $0.majorVersion == $1.majorVersion { return $0.path < $1.path }
                    return $0.majorVersion > $1.majorVersion
                }
        }.value
    }

    private static func inspect(home: String) -> JavaRuntime? {
        let javaURL = URL(fileURLWithPath: home).appendingPathComponent("bin/java")
        guard FileManager.default.isExecutableFile(atPath: javaURL.path) else { return nil }
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
        let major = parseMajorVersion(version)
        return JavaRuntime(
            path: javaURL.path,
            version: version,
            majorVersion: major,
            architecture: properties["os.arch"] ?? "未知",
            vendor: properties["java.vendor"] ?? "未知"
        )
    }

    private static func parseMajorVersion(_ version: String) -> Int {
        let pieces = version.split(separator: ".")
        if pieces.first == "1", pieces.count > 1 { return Int(pieces[1]) ?? 0 }
        return Int(pieces.first?.prefix { $0.isNumber } ?? "0") ?? 0
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
