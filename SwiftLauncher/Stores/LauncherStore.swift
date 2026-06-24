import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class LauncherStore {
    var selection: AppSection = .home
    var manifest: VersionManifest?
    var javaRuntimes: [JavaRuntime] = []
    var instances: [LauncherInstance] = []
    var accounts: [PlayerAccount] = []
    var downloads: [DownloadTaskInfo] = []
    var loaderVersions: [ModLoader: [LoaderVersionInfo]] = [:]
    var mods: [UUID: [ModFile]] = [:]
    var resourcePacks: [UUID: [ManagedContentFile]] = [:]
    var shaderPacks: [UUID: [ManagedContentFile]] = [:]
    var modrinthSearchResults: [ModrinthSearchResult] = []
    var modInstallPlan: ModrinthInstallPlan?
    var isSearchingMods = false
    var isLoadingModDetails = false
    var selectedDownloadInstanceID: UUID?
    var isLoadingLoaderVersions = false
    var selectedInstanceID: UUID?
    var selectedAccountID: UUID?
    var lastRefresh: Date?
    var isRefreshing = false
    var isBusy = false
    var isPresentingNewInstance = false
    var newInstanceSuggestedVersionID: String?
    var isPresentingLocalAccount = false
    var microsoftDeviceCode: MicrosoftDeviceCode?
    var isAuthenticatingMicrosoft = false
    var microsoftAuthenticationStatus = "等待授权…"
    var errorMessage: String?
    var errorHelpURL: URL?
    var gameProcessID: Int32?
    var runningInstanceID: UUID?
    var shouldOpenGameLog = false
    var iconRevision = 0
    var logText = "还没有游戏日志。"

    @ObservationIgnored private let fileSystem = LauncherFileSystem.shared
    @ObservationIgnored private let metadataService = MojangMetadataService()
    @ObservationIgnored private let downloader = FileDownloadService()
    @ObservationIgnored private let javaService = JavaRuntimeService()
    @ObservationIgnored private let keychain = KeychainStore()
    @ObservationIgnored private let authenticationService = MicrosoftAuthenticationService()
    @ObservationIgnored private let loaderService = LoaderMetadataService()
    @ObservationIgnored private var microsoftLoginTask: Task<Void, Never>?
    @ObservationIgnored private lazy var modManager = ModManager(fileSystem: fileSystem)
    @ObservationIgnored private lazy var modrinthService = ModrinthService(
        downloader: downloader,
        fileSystem: fileSystem
    )
    @ObservationIgnored private lazy var instanceImportService = InstanceImportService(
        fileSystem: fileSystem,
        downloader: downloader
    )
    @ObservationIgnored
    private lazy var installer = MinecraftInstaller(
        metadataService: metadataService,
        downloader: downloader,
        fileSystem: fileSystem,
        javaService: javaService
    )
    @ObservationIgnored private lazy var launcher = MinecraftLauncher(fileSystem: fileSystem, keychain: keychain)
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored private var userTerminatedProcessIDs: Set<Int32> = []

    var selectedInstance: LauncherInstance? {
        get { instances.first { $0.id == selectedInstanceID } }
        set { selectedInstanceID = newValue?.id }
    }

    var selectedAccount: PlayerAccount? {
        get { accounts.first { $0.id == selectedAccountID } }
        set { selectedAccountID = newValue?.id }
    }

    var latestRelease: MinecraftVersion? {
        guard let id = manifest?.latest.release else { return nil }
        return manifest?.versions.first { $0.id == id }
    }

    var latestSnapshot: MinecraftVersion? {
        guard let id = manifest?.latest.snapshot else { return nil }
        return manifest?.versions.first { $0.id == id }
    }

    var recentInstance: LauncherInstance? {
        instances.max {
            ($0.lastPlayedAt ?? $0.createdAt) < ($1.lastPlayedAt ?? $1.createdAt)
        }
    }

    var activeDownloads: [DownloadTaskInfo] {
        downloads.filter { $0.state == .queued || $0.state == .downloading }
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        do {
            try await fileSystem.prepare()
            instances = try await fileSystem.loadInstances()
            accounts = try await fileSystem.loadAccounts()
            if let cached = try? Data(contentsOf: fileSystem.manifestCacheURL()) {
                manifest = try? JSONCoding.makeDecoder().decode(VersionManifest.self, from: cached)
                lastRefresh = try? fileSystem.manifestCacheURL().resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            }
            selectedInstanceID = recentInstance?.id ?? instances.first?.id
            selectedDownloadInstanceID = instances.first(where: { $0.loader != .vanilla })?.id
            selectedAccountID = accounts.first?.id
            for versionID in Set(instances.map(\.versionID)) {
                try? await fileSystem.ensureMinecraftIcon(for: versionID)
            }
            iconRevision += 1
            loadLog()
        } catch {
            present(error)
        }
        await refreshEnvironment()
    }

    func refreshEnvironment() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        async let manifestResult = metadataService.fetchManifest()
        async let javaResult = javaService.discover(
            additionalPaths: instances.filter { !$0.usesAutomaticJava }.compactMap(\.javaPath)
        )
        do {
            let liveManifest = try await manifestResult
            manifest = liveManifest
            try? JSONCoding.makeEncoder().encode(liveManifest)
                .write(to: fileSystem.manifestCacheURL(), options: [.atomic])
            lastRefresh = .now
        } catch {
            present(error)
        }
        javaRuntimes = await javaResult
    }

    func createInstance(
        name: String,
        versionID: String,
        loader: ModLoader = .vanilla,
        loaderVersion: String? = nil,
        isVersionIsolated: Bool = true,
        installAfterCreation: Bool = false
    ) async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, manifest?.versions.contains(where: { $0.id == versionID }) == true else {
            return
        }
        let instance = LauncherInstance(
            name: trimmedName,
            versionID: versionID,
            javaPath: nil,
            usesAutomaticJava: true,
            memoryMB: UserDefaults.standard.integer(forKey: "defaultMemoryMB").nonzero ?? 4096,
            loader: loader,
            loaderVersion: loaderVersion,
            isVersionIsolated: isVersionIsolated,
            accountID: selectedAccountID
        )
        instances.append(instance)
        selectedInstanceID = instance.id
        selection = .home
        isPresentingNewInstance = false
        newInstanceSuggestedVersionID = nil
        await persistInstances()
        if installAfterCreation {
            await install(instance)
        }
    }

    func presentNewInstance(versionID: String? = nil) {
        newInstanceSuggestedVersionID = versionID
        isPresentingNewInstance = true
    }

    func consumeNewInstanceSuggestedVersionID() -> String? {
        defer { newInstanceSuggestedVersionID = nil }
        return newInstanceSuggestedVersionID
    }

    func importModpack(from url: URL) async {
        guard !isBusy else { return }
        isBusy = true
        var importedInstance: LauncherInstance?
        let taskID = UUID()
        downloads.insert(
            DownloadTaskInfo(id: taskID, title: url.deletingPathExtension().lastPathComponent, detail: "准备导入整合包"),
            at: 0
        )
        selection = .downloads
        do {
            updateDownload(taskID) { $0.state = .downloading }
            let result = try await instanceImportService.importModpack(
                from: url,
                accountID: selectedAccountID,
                knownVersionIDs: Set(manifest?.versions.map(\.id) ?? [])
            ) { [weak self] value, detail in
                self?.updateDownload(taskID) { task in
                    task.progress = value
                    task.detail = detail
                    task.state = .downloading
                }
            }
            instances.append(result.instance)
            selectedInstanceID = result.instance.id
            if selectedDownloadInstanceID == nil, result.instance.loader != .vanilla {
                selectedDownloadInstanceID = result.instance.id
            }
            await persistInstances()
            updateDownload(taskID) { task in
                task.progress = 1
                task.detail = result.detail
                task.state = .completed
            }
            importedInstance = result.instance
        } catch {
            updateDownload(taskID) { task in
                task.state = .failed
                task.errorMessage = error.localizedDescription
            }
            present(error)
        }
        isBusy = false
        if let importedInstance {
            await install(importedInstance)
        }
    }

    func importMinecraftFolder(from url: URL) async {
        guard !isBusy else { return }
        isBusy = true
        var importedInstance: LauncherInstance?
        let taskID = UUID()
        downloads.insert(
            DownloadTaskInfo(id: taskID, title: url.lastPathComponent, detail: "准备导入 .minecraft"),
            at: 0
        )
        selection = .downloads
        do {
            updateDownload(taskID) { $0.state = .downloading }
            let result = try await instanceImportService.importMinecraftFolder(
                from: url,
                accountID: selectedAccountID,
                knownVersionIDs: Set(manifest?.versions.map(\.id) ?? [])
            ) { [weak self] value, detail in
                self?.updateDownload(taskID) { task in
                    task.progress = value
                    task.detail = detail
                    task.state = .downloading
                }
            }
            instances.append(result.instance)
            selectedInstanceID = result.instance.id
            if selectedDownloadInstanceID == nil, result.instance.loader != .vanilla {
                selectedDownloadInstanceID = result.instance.id
            }
            await persistInstances()
            updateDownload(taskID) { task in
                task.progress = 1
                task.detail = result.detail
                task.state = .completed
            }
            importedInstance = result.instance
        } catch {
            updateDownload(taskID) { task in
                task.state = .failed
                task.errorMessage = error.localizedDescription
            }
            present(error)
        }
        isBusy = false
        if let importedInstance {
            await install(importedInstance)
        }
    }

    func searchMods(query: String, for instance: LauncherInstance) async {
        guard !isSearchingMods else { return }
        isSearchingMods = true
        defer { isSearchingMods = false }
        do {
            modrinthSearchResults = try await modrinthService.search(
                query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                gameVersion: instance.versionID,
                loader: instance.loader
            )
        } catch {
            modrinthSearchResults = []
            present(error)
        }
    }

    func showModDetails(
        _ project: ModrinthSearchResult,
        for instance: LauncherInstance,
        selectedVersionID: String? = nil
    ) async {
        guard !isLoadingModDetails else { return }
        isLoadingModDetails = true
        defer { isLoadingModDetails = false }
        do {
            modInstallPlan = try await modrinthService.installPlan(
                project: project,
                selectedVersionID: selectedVersionID,
                for: instance
            )
        } catch {
            present(error)
        }
    }

    func installMod(
        _ project: ModrinthSearchResult,
        for instance: LauncherInstance,
        specificVersionID: String? = nil
    ) async {
        guard !isBusy else { return }
        isBusy = true
        let mode = LauncherExperienceMode(
            rawValue: UserDefaults.standard.string(forKey: LauncherExperienceMode.defaultsKey) ?? ""
        ) ?? .beginner
        let normalAutoDependencies = UserDefaults.standard.object(
            forKey: LauncherExperienceMode.autoDependenciesDefaultsKey
        ) as? Bool ?? true
        let includeRequiredDependencies = mode == .beginner
            || (mode == .normal && normalAutoDependencies)
        let taskID = UUID()
        downloads.insert(
            DownloadTaskInfo(id: taskID, title: project.title, detail: "准备从 Modrinth 安装到 \(instance.name)"),
            at: 0
        )
        do {
            updateDownload(taskID) { $0.state = .downloading }
            let count = try await modrinthService.install(
                project: project,
                specificVersionID: specificVersionID,
                includeRequiredDependencies: includeRequiredDependencies,
                for: instance
            ) { [weak self] value, detail in
                self?.updateDownload(taskID) { task in
                    task.progress = value
                    task.detail = detail
                    task.state = .downloading
                }
            }
            await loadMods(for: instance)
            updateDownload(taskID) { task in
                task.progress = 1
                task.detail = includeRequiredDependencies
                    ? "已安装到 \(instance.name)，包含 \(count) 个模组/必需前置"
                    : "已安装到 \(instance.name)，未自动安装前置模组"
                task.state = .completed
            }
        } catch {
            updateDownload(taskID) { task in
                task.state = .failed
                task.errorMessage = error.localizedDescription
            }
            present(error)
        }
        isBusy = false
    }

    func loadLoaderVersions(gameVersion: String, loader: ModLoader) async {
        guard loader != .vanilla, !gameVersion.isEmpty else { return }
        isLoadingLoaderVersions = true
        defer { isLoadingLoaderVersions = false }
        do {
            loaderVersions[loader] = try await loaderService.versions(
                for: gameVersion,
                loader: loader
            )
        } catch {
            loaderVersions[loader] = []
            present(error)
        }
    }

    func updateInstance(_ updated: LauncherInstance) async {
        guard let index = instances.firstIndex(where: { $0.id == updated.id }) else { return }
        instances[index] = updated
        await persistInstances()
    }

    func deleteInstance(_ instance: LauncherInstance, deleteFiles: Bool = true) async {
        instances.removeAll { $0.id == instance.id }
        if deleteFiles {
            try? FileManager.default.removeItem(at: fileSystem.instanceRoot(instance.id))
        }
        selectedInstanceID = instances.first?.id
        await persistInstances()
    }

    func loadMods(for instance: LauncherInstance) async {
        do { mods[instance.id] = try await modManager.list(for: instance) }
        catch { present(error) }
    }

    func loadManagedContent(_ kind: ManagedContentKind, for instance: LauncherInstance) async {
        do {
            let files = try await modManager.listContent(kind, for: instance)
            switch kind {
            case .resourcePacks:
                resourcePacks[instance.id] = files
            case .shaderPacks:
                shaderPacks[instance.id] = files
            }
        } catch {
            present(error)
        }
    }

    func importMods(_ urls: [URL], for instance: LauncherInstance) async {
        do {
            try await modManager.importFiles(urls, for: instance)
            await loadMods(for: instance)
        } catch {
            present(error)
        }
    }

    func importManagedContent(_ urls: [URL], kind: ManagedContentKind, for instance: LauncherInstance) async {
        do {
            try await modManager.importContent(urls, kind: kind, for: instance)
            await loadManagedContent(kind, for: instance)
        } catch {
            present(error)
        }
    }

    func removeManagedContent(_ file: ManagedContentFile, kind: ManagedContentKind, for instance: LauncherInstance) async {
        do {
            try await modManager.removeContent(file)
            await loadManagedContent(kind, for: instance)
        } catch {
            present(error)
        }
    }

    func setMod(_ mod: ModFile, enabled: Bool, for instance: LauncherInstance) async {
        do {
            try await modManager.setEnabled(mod, enabled: enabled)
            await loadMods(for: instance)
        } catch {
            present(error)
        }
    }

    func removeMod(_ mod: ModFile, for instance: LauncherInstance) async {
        do {
            try await modManager.remove(mod)
            await loadMods(for: instance)
        } catch {
            present(error)
        }
    }

    func install(_ instance: LauncherInstance) async {
        guard !isBusy,
              let version = manifest?.versions.first(where: { $0.id == instance.versionID }) else { return }
        isBusy = true
        let taskID = UUID()
        downloads.insert(
            DownloadTaskInfo(id: taskID, title: instance.name, detail: "准备安装 \(instance.versionID)"),
            at: 0
        )
        selection = .downloads

        do {
            updateDownload(taskID) { task in task.state = .downloading }
            try await installer.install(instance: instance, version: version) { [weak self] value, detail in
                self?.updateDownload(taskID) { task in
                    task.progress = value
                    task.detail = detail
                    task.state = value >= 1 ? .completed : .downloading
                }
            }
            updateDownload(taskID) { task in
                task.progress = 1
                task.detail = "安装完成，SHA-1 校验通过"
                task.state = .completed
            }
            javaRuntimes = await javaService.discover(
                additionalPaths: instances.filter { !$0.usesAutomaticJava }.compactMap(\.javaPath)
            )
            try? await fileSystem.ensureMinecraftIcon(for: instance.versionID)
            iconRevision += 1
            selection = .home
        } catch is CancellationError {
            updateDownload(taskID) { $0.state = .cancelled }
        } catch {
            updateDownload(taskID) { task in
                task.state = .failed
                task.errorMessage = error.localizedDescription
            }
            present(error)
        }
        isBusy = false
    }

    func launchSelectedInstance() async {
        guard !isBusy, let instance = selectedInstance else { return }
        guard var account = account(for: instance) else {
            selection = .accounts
            present(LauncherError.missingAccount)
            return
        }

        if account.kind == .microsoft,
           let expires = account.tokenExpiresAt,
           expires < Date().addingTimeInterval(120) {
            do {
                account = try await refreshMicrosoftAccount(account)
            } catch {
                selection = .accounts
                present(error)
                return
            }
        }

        let version = manifest?.versions.first { $0.id == instance.versionID }
        if let version,
           !(await installer.installationIsComplete(instance: instance, version: version)) {
            await install(instance)
            guard await installer.installationIsComplete(instance: instance, version: version) else { return }
        }

        guard let java = preferredRuntime(for: instance) else {
            present(LauncherError.missingJava)
            return
        }

        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await launcher.launch(instance: instance, account: account, java: java)
            gameProcessID = result.processIdentifier
            runningInstanceID = instance.id
            let launchedProcessID = result.processIdentifier
            Task { [weak self] in
                guard let self else { return }
                let termination = await launcher.waitForTermination(processIdentifier: launchedProcessID)
                let wasStoppedByUser = userTerminatedProcessIDs.remove(launchedProcessID) != nil
                if gameProcessID == launchedProcessID {
                    gameProcessID = nil
                    runningInstanceID = nil
                    loadLog()
                }
                if !wasStoppedByUser, !termination.succeeded {
                    presentGameCrash(termination)
                }
            }
            if let index = instances.firstIndex(where: { $0.id == instance.id }) {
                instances[index].lastPlayedAt = .now
                selectedInstanceID = instance.id
                await persistInstances()
            }
            loadLog()
        } catch {
            present(error)
        }
    }

    func terminateGame() async {
        if let gameProcessID {
            userTerminatedProcessIDs.insert(gameProcessID)
        }
        await launcher.terminate()
    }

    func addLocalAccount(username: String) async {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let account = PlayerAccount(
            username: name,
            profileID: Hashing.offlineUUID(for: name),
            kind: .local
        )
        accounts.append(account)
        selectedAccountID = account.id
        isPresentingLocalAccount = false
        await persistAccounts()
    }

    func beginMicrosoftLogin() {
        guard !isAuthenticatingMicrosoft else { return }
        isAuthenticatingMicrosoft = true
        microsoftAuthenticationStatus = "正在创建 Microsoft 授权会话…"

        microsoftLoginTask = Task { [weak self] in
            guard let self else { return }
            defer {
                isAuthenticatingMicrosoft = false
                microsoftLoginTask = nil
            }

            do {
                let code = try await authenticationService.begin(
                    clientID: MicrosoftOAuthConfiguration.clientID
                )
                try Task.checkCancellation()
                microsoftDeviceCode = code
                microsoftAuthenticationStatus = "等待你在浏览器中完成授权…"
                NSWorkspace.shared.open(code.verificationURI)

                let session = try await authenticationService.complete(
                    clientID: MicrosoftOAuthConfiguration.clientID,
                    deviceCode: code
                ) { [weak self] status in
                    await MainActor.run {
                        self?.microsoftAuthenticationStatus = status
                    }
                }
                try Task.checkCancellation()
                microsoftAuthenticationStatus = "授权成功，正在保存登录凭证…"
                try keychain.set(
                    session.refreshToken,
                    account: "microsoft-refresh-\(session.account.id.uuidString)"
                )
                try keychain.set(
                    session.minecraftAccessToken,
                    account: "minecraft-token-\(session.account.id.uuidString)"
                )
                accounts.removeAll {
                    $0.kind == .microsoft && $0.profileID == session.account.profileID
                }
                accounts.append(session.account)
                selectedAccountID = session.account.id
                microsoftDeviceCode = nil
                await persistAccounts()
            } catch is CancellationError {
                microsoftDeviceCode = nil
                microsoftAuthenticationStatus = "登录已取消"
            } catch {
                // Always close the device-code sheet so the actual error alert is visible.
                microsoftDeviceCode = nil
                microsoftAuthenticationStatus = "登录失败"
                present(error)
            }
        }
    }

    func cancelMicrosoftLogin() {
        microsoftAuthenticationStatus = "正在取消登录…"
        microsoftDeviceCode = nil
        microsoftLoginTask?.cancel()
    }

    func removeAccount(_ account: PlayerAccount) async {
        accounts.removeAll { $0.id == account.id }
        keychain.remove(account: "microsoft-refresh-\(account.id.uuidString)")
        keychain.remove(account: "minecraft-token-\(account.id.uuidString)")
        selectedAccountID = accounts.first?.id
        for index in instances.indices where instances[index].accountID == account.id {
            instances[index].accountID = nil
        }
        await persistAccounts()
        await persistInstances()
    }

    func account(for instance: LauncherInstance) -> PlayerAccount? {
        if let accountID = instance.accountID,
           let account = accounts.first(where: { $0.id == accountID }) {
            return account
        }
        return selectedAccount
    }

    func preferredRuntime(for instance: LauncherInstance) -> JavaRuntime? {
        if !instance.usesAutomaticJava,
           let path = instance.javaPath,
           let runtime = javaRuntimes.first(where: { $0.path == path }) {
            return runtime
        }
        return preferredRuntime(forVersionID: instance.versionID)
    }

    func requiredJavaMajor(for instance: LauncherInstance) -> Int? {
        guard let data = try? Data(contentsOf: fileSystem.versionJSON(instance.versionID)),
              let metadata = try? JSONCoding.makeDecoder().decode(VersionMetadata.self, from: data) else {
            return nil
        }
        return metadata.javaVersion?.majorVersion
    }

    func registerCustomJava(at url: URL) async -> JavaRuntime? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let runtime = try await javaService.runtime(at: url)
            javaRuntimes.removeAll { $0.path == runtime.path }
            javaRuntimes.append(runtime)
            javaRuntimes.sort { $0.majorVersion > $1.majorVersion }
            return runtime
        } catch {
            present(error)
            return nil
        }
    }

    func instanceIconImage(for instance: LauncherInstance) -> NSImage? {
        _ = iconRevision
        if instance.iconFileName != nil,
           let image = NSImage(contentsOf: fileSystem.instanceIcon(instance.id)) {
            return image
        }
        return NSImage(contentsOf: fileSystem.minecraftIcon(instance.versionID))
    }

    func setInstanceIcon(from url: URL, for instance: LauncherInstance) async {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            guard let image = NSImage(contentsOf: url), let data = Self.squarePNGData(from: image) else {
                throw LauncherError.unsupported("无法读取所选图片")
            }
            try FileManager.default.createDirectory(
                at: fileSystem.instanceRoot(instance.id),
                withIntermediateDirectories: true
            )
            try data.write(to: fileSystem.instanceIcon(instance.id), options: [.atomic])
            guard let index = instances.firstIndex(where: { $0.id == instance.id }) else { return }
            instances[index].iconFileName = "icon.png"
            await persistInstances()
        } catch {
            present(error)
        }
    }

    func removeInstanceIcon(_ instance: LauncherInstance) async {
        try? FileManager.default.removeItem(at: fileSystem.instanceIcon(instance.id))
        guard let index = instances.firstIndex(where: { $0.id == instance.id }) else { return }
        instances[index].iconFileName = nil
        await persistInstances()
    }

    func isInstalled(_ instance: LauncherInstance) -> Bool {
        fileSystem.isInstalled(instance)
    }

    func installationStatus(for instance: LauncherInstance) -> String {
        if runningInstanceID == instance.id { return "已启动" }
        if fileSystem.isInstalled(instance) {
            guard instance.loader != .vanilla else { return "原版已安装" }
            let version = instance.loaderVersion.map { " \($0)" } ?? ""
            return "\(instance.loader.title)\(version) 已安装"
        }
        if fileSystem.hasImportedContent(instance) { return "整合包已导入 · 待补全核心" }
        return "未安装"
    }

    func openGameDirectory(_ instance: LauncherInstance) {
        try? FileManager.default.createDirectory(
            at: fileSystem.gameDirectory(instance),
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.activateFileViewerSelecting([fileSystem.gameDirectory(instance)])
    }

    func openApplicationSupport() {
        NSWorkspace.shared.activateFileViewerSelecting([fileSystem.root])
    }

    func loadLog() {
        let url = fileSystem.latestLogURL()
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            logText = "还没有游戏日志。"
            return
        }
        logText = String(text.suffix(200_000))
    }

    func isRunning(_ instance: LauncherInstance) -> Bool {
        runningInstanceID == instance.id && gameProcessID != nil
    }

    func launchButtonTitle(for instance: LauncherInstance) -> String {
        if isRunning(instance) { return "游戏运行中" }
        return isInstalled(instance) ? "启动游戏" : "安装并启动"
    }

    private func presentGameCrash(_ termination: GameTermination) {
        loadLog()
        let exitReason = termination.wasSignaled
            ? "被系统信号 \(termination.status) 终止"
            : "退出码为 \(termination.status)"
        let renderingHint = logText.contains("MTLDebugRenderCommandEncoder")
            || logText.localizedCaseInsensitiveContains("MoltenVK")
            ? "检测到 Vulkan/MoltenVK 与 Metal 渲染错误，请先恢复默认图形 API。"
            : ""
        errorMessage = "Minecraft 异常退出（\(exitReason)）。\(renderingHint)游戏日志已自动打开。"
        errorHelpURL = nil
        shouldOpenGameLog = true
    }

    func clearCompletedDownloads() {
        downloads.removeAll { $0.state == .completed || $0.state == .cancelled }
    }

    private func preferredRuntime(forVersionID versionID: String) -> JavaRuntime? {
        if let data = try? Data(contentsOf: fileSystem.versionJSON(versionID)),
           let metadata = try? JSONCoding.makeDecoder().decode(VersionMetadata.self, from: data),
           let requirement = metadata.javaVersion {
            return javaRuntimes.first(where: { $0.majorVersion == requirement.majorVersion })
        }
        return javaRuntimes.first
    }

    private static func squarePNGData(from image: NSImage) -> Data? {
        let side = min(image.size.width, image.size.height)
        guard side > 0 else { return nil }
        let source = NSRect(
            x: (image.size.width - side) / 2,
            y: (image.size.height - side) / 2,
            width: side,
            height: side
        )
        let target = NSImage(size: NSSize(width: 256, height: 256))
        target.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(x: 0, y: 0, width: 256, height: 256),
            from: source,
            operation: .copy,
            fraction: 1
        )
        target.unlockFocus()
        guard let tiff = target.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff) else { return nil }
        return representation.representation(using: .png, properties: [:])
    }

    private func refreshMicrosoftAccount(_ account: PlayerAccount) async throws -> PlayerAccount {
        guard let refreshToken = keychain.string(account: "microsoft-refresh-\(account.id.uuidString)") else {
            throw LauncherError.authentication("Microsoft 登录已过期，请重新登录")
        }
        let session = try await authenticationService.refresh(
            clientID: MicrosoftOAuthConfiguration.clientID,
            refreshToken: refreshToken
        )
        let refreshed = PlayerAccount(
            id: account.id,
            username: session.account.username,
            profileID: session.account.profileID,
            kind: .microsoft,
            tokenExpiresAt: session.account.tokenExpiresAt
        )
        try keychain.set(session.refreshToken, account: "microsoft-refresh-\(account.id.uuidString)")
        try keychain.set(session.minecraftAccessToken, account: "minecraft-token-\(account.id.uuidString)")
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = refreshed
            await persistAccounts()
        }
        return refreshed
    }

    private func updateDownload(_ id: UUID, mutation: (inout DownloadTaskInfo) -> Void) {
        guard let index = downloads.firstIndex(where: { $0.id == id }) else { return }
        mutation(&downloads[index])
    }

    private func persistInstances() async {
        do { try await fileSystem.saveInstances(instances) }
        catch { present(error) }
    }

    private func persistAccounts() async {
        do { try await fileSystem.saveAccounts(accounts) }
        catch { present(error) }
    }

    private func present(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if let launcherError = error as? LauncherError,
           case .minecraftAppRegistrationRequired = launcherError {
            errorHelpURL = URL(string: "https://aka.ms/mce-reviewappid")
        } else {
            errorHelpURL = nil
        }
    }
}

private extension Int {
    var nonzero: Int? { self == 0 ? nil : self }
}
