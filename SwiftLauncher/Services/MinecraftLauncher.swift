import Foundation

struct LaunchResult: Sendable {
    let processIdentifier: Int32
    let logURL: URL
}

actor MinecraftLauncher {
    private let fileSystem: LauncherFileSystem
    private let keychain: KeychainStore
    private var process: Process?

    init(fileSystem: LauncherFileSystem, keychain: KeychainStore) {
        self.fileSystem = fileSystem
        self.keychain = keychain
    }

    func launch(
        instance: LauncherInstance,
        account: PlayerAccount,
        java: JavaRuntime
    ) async throws -> LaunchResult {
        guard fileSystem.isInstalled(instance) else { throw LauncherError.instanceNotInstalled }
        let data = try Data(contentsOf: fileSystem.versionJSON(instance.versionID))
        let metadata = try JSONCoding.makeDecoder().decode(VersionMetadata.self, from: data)
        let loaderProfile: LoaderProfile?
        let installerLoaderMetadata: VersionMetadata?
        if instance.loader == .fabric || instance.loader == .quilt {
            let loaderData = try Data(contentsOf: fileSystem.loaderProfile(instance.id))
            loaderProfile = try JSONCoding.makeDecoder().decode(LoaderProfile.self, from: loaderData)
            installerLoaderMetadata = nil
        } else if instance.loader == .forge || instance.loader == .neoForge {
            let loaderData = try Data(contentsOf: fileSystem.loaderProfile(instance.id))
            installerLoaderMetadata = try JSONCoding.makeDecoder().decode(VersionMetadata.self, from: loaderData)
            loaderProfile = nil
        } else {
            loaderProfile = nil
            installerLoaderMetadata = nil
        }
        let command = try buildCommand(
            metadata: metadata,
            loaderProfile: loaderProfile,
            installerLoaderMetadata: installerLoaderMetadata,
            instance: instance,
            account: account,
            java: java
        )

        let logURL = fileSystem.latestLogURL()
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: java.path)
        process.arguments = command
        process.currentDirectoryURL = fileSystem.gameDirectory(instance)
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = logHandle
        process.standardError = logHandle
        try process.run()
        self.process = process
        return LaunchResult(processIdentifier: process.processIdentifier, logURL: logURL)
    }

    func terminate() {
        process?.terminate()
        process = nil
    }

    private func buildCommand(
        metadata: VersionMetadata,
        loaderProfile: LoaderProfile?,
        installerLoaderMetadata: VersionMetadata?,
        instance: LauncherInstance,
        account: PlayerAccount,
        java: JavaRuntime
    ) throws -> [String] {
        let gameDirectory = fileSystem.gameDirectory(instance)
        let nativesDirectory = fileSystem.nativesDirectory(instance.id)
        let evaluator = RuleEvaluator(features: [
            "has_custom_resolution": instance.resolutionWidth != nil && instance.resolutionHeight != nil,
            "is_demo_user": false
        ])
        var classpath = metadata.libraries
            .filter { evaluator.allows($0.rules) }
            .compactMap { library -> String? in
                guard let artifact = library.downloads?.artifact else { return nil }
                let relative = artifact.path ?? Self.mavenPath(for: library.name)
                let url = fileSystem.librariesRoot.appendingPathComponent(relative)
                return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
            }
        if let loaderProfile {
            classpath += loaderProfile.libraries.compactMap { library in
                let url = fileSystem.librariesRoot.appendingPathComponent(Self.mavenPath(for: library.name))
                return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
            }
        }
        if let installerLoaderMetadata {
            classpath += installerLoaderMetadata.libraries.compactMap { library in
                let relative = library.downloads?.artifact?.path ?? Self.mavenPath(for: library.name)
                let url = fileSystem.librariesRoot.appendingPathComponent(relative)
                return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
            }
        }
        classpath.append(fileSystem.versionJAR(instance.versionID).path)

        let accessToken: String
        if account.kind == .microsoft {
            guard let token = keychain.string(account: "minecraft-token-\(account.id.uuidString)") else {
                throw LauncherError.authentication("Microsoft 登录已过期，请重新登录")
            }
            accessToken = token
        } else {
            accessToken = "0"
        }

        let replacements: [String: String] = [
            "${auth_player_name}": account.username,
            "${version_name}": metadata.id,
            "${game_directory}": gameDirectory.path,
            "${assets_root}": fileSystem.assetsRoot.path,
            "${assets_index_name}": metadata.assetIndex?.id ?? metadata.assets ?? "legacy",
            "${auth_uuid}": account.profileID.replacingOccurrences(of: "-", with: ""),
            "${auth_access_token}": accessToken,
            "${auth_session}": accessToken,
            "${user_type}": account.kind == .microsoft ? "msa" : "legacy",
            "${version_type}": metadata.type?.rawValue ?? "release",
            "${natives_directory}": nativesDirectory.path,
            "${launcher_name}": "SwiftLauncher",
            "${launcher_version}": "1.0",
            "${classpath_separator}": ":",
            "${library_directory}": fileSystem.librariesRoot.path,
            "${classpath}": classpath.joined(separator: ":"),
            "${clientid}": "",
            "${xuid}": ""
        ]

        var jvm: [String] = ["-Xms512m", "-Xmx\(instance.memoryMB)m"]
        if let arguments = metadata.arguments?.jvm {
            jvm += resolve(arguments, evaluator: evaluator, replacements: replacements)
        } else {
            jvm += ["-Djava.library.path=\(nativesDirectory.path)", "-cp", classpath.joined(separator: ":")]
        }
        if let loaderArguments = loaderProfile?.arguments?.jvm {
            jvm += resolve(loaderArguments, evaluator: evaluator, replacements: replacements)
        }
        if let loaderArguments = installerLoaderMetadata?.arguments?.jvm {
            jvm += resolve(loaderArguments, evaluator: evaluator, replacements: replacements)
        }
        jvm += instance.additionalJVMArguments

        if let logging = metadata.logging?["client"],
           let argument = logging.argument,
           let file = logging.file {
            let config = fileSystem.assetsRoot
                .appendingPathComponent("log_configs", isDirectory: true)
                .appendingPathComponent(file.path ?? file.url.lastPathComponent)
            jvm.append(argument.replacingOccurrences(of: "${path}", with: config.path))
        }

        var game: [String]
        if let arguments = metadata.arguments?.game {
            game = resolve(arguments, evaluator: evaluator, replacements: replacements)
        } else {
            game = Self.shellSplit(metadata.minecraftArguments ?? "")
                .map { Self.replace($0, using: replacements) }
        }
        if let loaderArguments = loaderProfile?.arguments?.game {
            game += resolve(loaderArguments, evaluator: evaluator, replacements: replacements)
        }
        if let loaderArguments = installerLoaderMetadata?.arguments?.game {
            game += resolve(loaderArguments, evaluator: evaluator, replacements: replacements)
        }

        if let width = instance.resolutionWidth, let height = instance.resolutionHeight {
            game += ["--width", String(width), "--height", String(height)]
        }
        let mainClass = loaderProfile?.mainClass ?? installerLoaderMetadata?.mainClass ?? metadata.mainClass
        return jvm + [mainClass] + game
    }

    private func resolve(
        _ arguments: [MinecraftArgument],
        evaluator: RuleEvaluator,
        replacements: [String: String]
    ) -> [String] {
        arguments.flatMap { argument -> [String] in
            switch argument {
            case .literal(let value):
                [Self.replace(value, using: replacements)]
            case .conditional(let rules, let values):
                evaluator.allows(rules) ? values.map { Self.replace($0, using: replacements) } : []
            }
        }
    }

    private static func replace(_ value: String, using replacements: [String: String]) -> String {
        replacements.reduce(value) { result, pair in
            result.replacingOccurrences(of: pair.key, with: pair.value)
        }
    }

    private static func shellSplit(_ input: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        for character in input {
            if escaped {
                current.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" || character == "'" {
                if quote == character { quote = nil }
                else if quote == nil { quote = character }
                else { current.append(character) }
            } else if character.isWhitespace && quote == nil {
                if !current.isEmpty { result.append(current); current = "" }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func mavenPath(for coordinate: String) -> String {
        let pieces = coordinate.split(separator: ":").map(String.init)
        guard pieces.count >= 3 else { return coordinate.replacingOccurrences(of: ":", with: "/") }
        let group = pieces[0].replacingOccurrences(of: ".", with: "/")
        return "\(group)/\(pieces[1])/\(pieces[2])/\(pieces[1])-\(pieces[2]).jar"
    }
}
