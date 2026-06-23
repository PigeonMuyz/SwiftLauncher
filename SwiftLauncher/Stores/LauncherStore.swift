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
    var isLoadingLoaderVersions = false
    var selectedInstanceID: UUID?
    var selectedAccountID: UUID?
    var lastRefresh: Date?
    var isRefreshing = false
    var isBusy = false
    var isPresentingNewInstance = false
    var isPresentingLocalAccount = false
    var microsoftDeviceCode: MicrosoftDeviceCode?
    var isAuthenticatingMicrosoft = false
    var microsoftAuthenticationStatus = "等待授权…"
    var errorMessage: String?
    var errorHelpURL: URL?
    var gameProcessID: Int32?
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
    @ObservationIgnored
    private lazy var installer = MinecraftInstaller(
        metadataService: metadataService,
        downloader: downloader,
        fileSystem: fileSystem
    )
    @ObservationIgnored private lazy var launcher = MinecraftLauncher(fileSystem: fileSystem, keychain: keychain)
    @ObservationIgnored private var didBootstrap = false

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
            selectedInstanceID = instances.first?.id
            selectedAccountID = accounts.first?.id
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
        async let javaResult = javaService.discover()
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
            javaPath: preferredRuntime(forVersionID: versionID)?.path,
            memoryMB: UserDefaults.standard.integer(forKey: "defaultMemoryMB").nonzero ?? 4096,
            loader: loader,
            loaderVersion: loaderVersion,
            isVersionIsolated: isVersionIsolated,
            accountID: selectedAccountID
        )
        instances.append(instance)
        selectedInstanceID = instance.id
        selection = .instances
        isPresentingNewInstance = false
        await persistInstances()
        if installAfterCreation {
            await install(instance)
        }
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

    func importMods(_ urls: [URL], for instance: LauncherInstance) async {
        do {
            try await modManager.importFiles(urls, for: instance)
            await loadMods(for: instance)
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
            selection = .instances
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

        if !fileSystem.isInstalled(instance) {
            await install(instance)
            guard fileSystem.isInstalled(instance) else { return }
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
            if let index = instances.firstIndex(where: { $0.id == instance.id }) {
                instances[index].lastPlayedAt = .now
                await persistInstances()
            }
            loadLog()
        } catch {
            present(error)
        }
    }

    func terminateGame() async {
        await launcher.terminate()
        gameProcessID = nil
        loadLog()
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
        if let path = instance.javaPath,
           let runtime = javaRuntimes.first(where: { $0.path == path }) {
            return runtime
        }
        return preferredRuntime(forVersionID: instance.versionID)
    }

    func isInstalled(_ instance: LauncherInstance) -> Bool {
        fileSystem.isInstalled(instance)
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

    func clearCompletedDownloads() {
        downloads.removeAll { $0.state == .completed || $0.state == .cancelled }
    }

    private func preferredRuntime(forVersionID versionID: String) -> JavaRuntime? {
        if let data = try? Data(contentsOf: fileSystem.versionJSON(versionID)),
           let metadata = try? JSONCoding.makeDecoder().decode(VersionMetadata.self, from: data),
           let requirement = metadata.javaVersion,
           let match = javaRuntimes.first(where: { $0.majorVersion == requirement.majorVersion }) {
            return match
        }
        return javaRuntimes.first
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
