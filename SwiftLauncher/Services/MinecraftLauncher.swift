import Foundation

struct LaunchResult: Sendable {
    let processIdentifier: Int32
    let logURL: URL
}

struct GameTermination: Sendable {
    let status: Int32
    let wasSignaled: Bool

    var succeeded: Bool { !wasSignaled && status == 0 }
}

actor MinecraftLauncher {
    private let fileSystem: LauncherFileSystem
    private let keychain: KeychainStore
    private var process: Process?
    private var terminations: [Int32: GameTermination] = [:]
    private var terminationWaiters: [Int32: [CheckedContinuation<GameTermination, Never>]] = [:]

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
        let launchHeader = """
        [SwiftLauncher] 游戏版本名称：\(instance.effectiveLaunchTitle)
        [SwiftLauncher] 启动器品牌：SwiftLauncher/\(launcherVersion)

        """
        FileManager.default.createFile(
            atPath: logURL.path,
            contents: Data(launchHeader.utf8)
        )
        let logHandle = try FileHandle(forWritingTo: logURL)
        try logHandle.seekToEnd()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: java.path)
        process.arguments = command
        process.currentDirectoryURL = fileSystem.gameDirectory(instance)
        process.environment = Self.sanitizedProcessEnvironment(ProcessInfo.processInfo.environment)
        process.standardOutput = logHandle
        process.standardError = logHandle
        process.terminationHandler = { [weak self] terminated in
            let identifier = terminated.processIdentifier
            let status = terminated.terminationStatus
            let wasSignaled = terminated.terminationReason == .uncaughtSignal
            try? logHandle.close()
            Task {
                await self?.recordTermination(
                    identifier: identifier,
                    termination: GameTermination(status: status, wasSignaled: wasSignaled)
                )
            }
        }
        try process.run()
        self.process = process
        return LaunchResult(processIdentifier: process.processIdentifier, logURL: logURL)
    }

    func terminate() {
        process?.terminate()
    }

    func waitForTermination(processIdentifier: Int32) async -> GameTermination {
        if let termination = terminations.removeValue(forKey: processIdentifier) {
            return termination
        }
        return await withCheckedContinuation { continuation in
            terminationWaiters[processIdentifier, default: []].append(continuation)
        }
    }

    private func recordTermination(identifier: Int32, termination: GameTermination) {
        if process?.processIdentifier == identifier {
            process = nil
        }
        let waiters = terminationWaiters.removeValue(forKey: identifier) ?? []
        if waiters.isEmpty {
            terminations[identifier] = termination
        } else {
            for waiter in waiters { waiter.resume(returning: termination) }
        }
    }

    static func sanitizedProcessEnvironment(_ environment: [String: String]) -> [String: String] {
        environment.filter { key, _ in
            !key.hasPrefix("MTL_DEBUG")
                && !key.hasPrefix("MTL_SHADER_VALIDATION")
                && key != "METAL_DEVICE_WRAPPER_TYPE"
                && key != "MTLCaptureEnabled"
        }
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

        // 收集所有库的路径
        var allLibraryPaths: [String] = []

        allLibraryPaths += metadata.libraries
            .filter { evaluator.allows($0.rules) }
            .compactMap { library -> String? in
                guard let artifact = library.downloads?.artifact else { return nil }
                let relative = artifact.path ?? MavenCoordinate.path(for: library.name)
                let url = fileSystem.librariesRoot.appendingPathComponent(relative)
                return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
            }
        if let loaderProfile {
            allLibraryPaths += loaderProfile.libraries.compactMap { library in
                let url = fileSystem.librariesRoot.appendingPathComponent(MavenCoordinate.path(for: library.name))
                return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
            }
        }
        if let installerLoaderMetadata {
            allLibraryPaths += installerLoaderMetadata.libraries.compactMap { library in
                let relative = library.downloads?.artifact?.path ?? MavenCoordinate.path(for: library.name)
                let url = fileSystem.librariesRoot.appendingPathComponent(relative)
                return FileManager.default.fileExists(atPath: url.path) ? url.path : nil
            }
        }

        // 去重：对于同一个库的多个版本，只保留最高版本
        var classpath = uniqueLibraryPaths(allLibraryPaths)
        if installerLoaderMetadata == nil {
            classpath.append(fileSystem.versionJAR(instance.versionID).path)
        }

        let accessToken: String
        if account.kind == .microsoft {
            guard let token = keychain.string(account: "minecraft-token-\(account.id.uuidString)") else {
                throw LauncherError.authentication("Microsoft 登录已过期，请重新登录")
            }
            accessToken = token
        } else {
            accessToken = "0"
        }
        let launcherIdentity = "SwiftLauncher/\(launcherVersion)"

        let replacements: [String: String] = [
            "${auth_player_name}": account.username,
            "${version_name}": instance.effectiveLaunchTitle,
            "${game_directory}": gameDirectory.path,
            "${assets_root}": fileSystem.assetsRoot.path,
            "${assets_index_name}": metadata.assetIndex?.id ?? metadata.assets ?? "legacy",
            "${auth_uuid}": account.profileID.replacingOccurrences(of: "-", with: ""),
            "${auth_access_token}": accessToken,
            "${auth_session}": accessToken,
            "${user_type}": account.kind == .microsoft ? "msa" : "legacy",
            "${version_type}": launcherIdentity,
            "${natives_directory}": nativesDirectory.path,
            "${launcher_name}": "SwiftLauncher",
            "${launcher_version}": launcherVersion,
            "${classpath_separator}": ":",
            "${library_directory}": fileSystem.librariesRoot.path,
            "${classpath}": classpath.joined(separator: ":"),
            "${clientid}": "",
            "${xuid}": "",
            "${auth_client_id}": "",
            "${auth_xuid}": "",
            "${user_properties}": "{}"
        ]

        var jvm: [String] = ["-Xms512m", "-Xmx\(instance.memoryMB)m"]

        // 支持 Sinytra Connector：在最开始添加模块系统参数
        if instance.loader == .forge || instance.loader == .neoForge {
            jvm += [
                "--add-opens", "java.base/java.lang=ALL-UNNAMED",
                "--add-opens", "java.base/java.util=ALL-UNNAMED",
                "--add-opens", "java.base/java.lang.reflect=ALL-UNNAMED",
                "--add-opens", "java.base/java.text=ALL-UNNAMED",
                "--add-opens", "java.base/java.net=ALL-UNNAMED",
                "--add-opens", "java.base/java.lang.module=ALL-UNNAMED",
                "--add-opens", "java.base/jdk.internal.loader=ALL-UNNAMED",
                "--add-opens", "java.base/jdk.internal.misc=ALL-UNNAMED",
                "--add-opens", "java.base/jdk.internal.reflect=ALL-UNNAMED",
                "--add-exports", "java.base/sun.security.util=ALL-UNNAMED",
                "--add-exports", "jdk.naming.dns/com.sun.jndi.dns=ALL-UNNAMED,java.naming",
                "-Dconnector.disableModuleSafetyChecks=true"
            ]
        }

        if let arguments = metadata.arguments?.jvm {
            jvm += resolve(arguments, evaluator: evaluator, replacements: replacements)
        } else {
            jvm += ["-Djava.library.path=\(nativesDirectory.path)", "-cp", classpath.joined(separator: ":")]
        }
        jvm += [
            "-Djava.library.path=\(nativesDirectory.path)",
            "-Dorg.lwjgl.librarypath=\(nativesDirectory.path)"
        ]
        if let loaderArguments = loaderProfile?.arguments?.jvm {
            jvm += resolve(loaderArguments, evaluator: evaluator, replacements: replacements)
        }
        if let loaderArguments = installerLoaderMetadata?.arguments?.jvm {
            jvm += resolve(loaderArguments, evaluator: evaluator, replacements: replacements)
        }
        jvm += [
            "-Dminecraft.launcher.brand=SwiftLauncher",
            "-Dminecraft.launcher.version=\(launcherVersion)"
        ]
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
        game = Self.replacingOption("--version", with: instance.effectiveLaunchTitle, in: game)
        game = Self.replacingOption("--versionType", with: launcherIdentity, in: game)

        if let width = instance.resolutionWidth, let height = instance.resolutionHeight {
            game += ["--width", String(width), "--height", String(height)]
        }
        let serverHost = instance.serverHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if instance.autoJoinServer, !serverHost.isEmpty {
            game += ["--server", serverHost]
            if let port = instance.serverPort, port > 0 {
                game += ["--port", String(port)]
            }
        }
        let mainClass = loaderProfile?.mainClass ?? installerLoaderMetadata?.mainClass ?? metadata.mainClass
        return jvm + [mainClass] + game
    }

    private var launcherVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
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

    private static func replacingOption(_ option: String, with value: String, in arguments: [String]) -> [String] {
        var sanitized: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            if arguments[index] == option {
                index += 1
                if index < arguments.endIndex { index += 1 }
                continue
            }
            sanitized.append(arguments[index])
            index += 1
        }
        sanitized += [option, value]
        return sanitized
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

    private func uniqueLibraryPaths(_ libraries: [String]) -> [String] {
        var seen: Set<String> = []
        return libraries.filter { seen.insert($0).inserted }
    }

}
