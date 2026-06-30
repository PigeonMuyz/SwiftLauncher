import SwiftUI

struct InstanceLoaderSheet: View {
    @Bindable var store: LauncherStore
    let instance: LauncherInstance
    var onApply: (LauncherInstance) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @ViewState private var selectedLoader: ModLoader
    @ViewState private var selectedLoaderVersion: String
    @ViewState private var isApplying = false

    init(
        store: LauncherStore,
        instance: LauncherInstance,
        onApply: @escaping (LauncherInstance) -> Void = { _ in }
    ) {
        self.store = store
        self.instance = instance
        self.onApply = onApply
        _selectedLoader = ViewState(initialValue: instance.loader)
        _selectedLoaderVersion = ViewState(initialValue: instance.loaderVersion ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("目标实例") {
                    LabeledContent("名称", value: instance.name)
                    LabeledContent("Minecraft", value: instance.versionID)
                    LabeledContent("当前加载器", value: currentLoaderSummary)
                }

                Section("加载器") {
                    Picker("类型", selection: $selectedLoader) {
                        ForEach(ModLoader.allCases) { loader in
                            Text(loader.title).tag(loader)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedLoader == .vanilla {
                        Text("切回原版只会更新此实例的启动配置，不会删除已有的模组、资源包或加载器文件。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if store.isLoadingLoaderVersions {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在读取 \(selectedLoader.title) 版本…")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Picker("版本", selection: $selectedLoaderVersion) {
                            if availableVersions.isEmpty {
                                Text("没有可用版本").tag("")
                            } else {
                                ForEach(availableVersions) { version in
                                    Text(version.stable == true ? "\(version.version)（稳定）" : version.version)
                                        .tag(version.version)
                                }
                            }
                        }

                        if availableVersions.isEmpty {
                            Text("当前 Minecraft 版本没有找到 \(selectedLoader.title) 的可安装版本。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("安装影响") {
                    Text(impactText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("已有 mods 不会被自动删除；从原版切到加载器后，请确认模组与目标加载器兼容。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("管理加载器")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isApplying)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(applyButtonTitle) {
                        applyChanges()
                    }
                    .disabled(!canApply)
                }
            }
        }
        .frame(width: 560, height: 440)
        .task(id: selectedLoader) {
            await refreshLoaderVersions()
        }
    }

    private var currentLoaderSummary: String {
        if instance.loader == .vanilla {
            return instance.loader.title
        }
        return "\(instance.loader.title) \(instance.loaderVersion ?? "")"
    }

    private var availableVersions: [LoaderVersionInfo] {
        store.loaderVersions[selectedLoader, default: []]
    }

    private var selectedTargetVersion: String? {
        selectedLoader == .vanilla ? nil : selectedLoaderVersion
    }

    private var hasConfigurationChanges: Bool {
        selectedLoader != instance.loader || selectedTargetVersion != instance.loaderVersion
    }

    private var canApply: Bool {
        guard !isApplying, !store.isWorking(on: instance), !store.isLoadingLoaderVersions else {
            return false
        }
        guard selectedLoader == .vanilla || !selectedLoaderVersion.isEmpty else {
            return false
        }
        return hasConfigurationChanges || !store.isInstalled(instance)
    }

    private var applyButtonTitle: String {
        hasConfigurationChanges ? "应用并安装" : "重新安装"
    }

    private var impactText: String {
        if selectedLoader == .vanilla {
            return "应用后此实例会按 Mojang 原版配置启动，并重新写入安装标记。"
        }
        return "应用后会安装 \(selectedLoader.title) \(selectedLoaderVersion)，并让此实例后续启动使用该加载器。"
    }

    private func refreshLoaderVersions() async {
        let loader = selectedLoader
        guard loader != .vanilla else {
            selectedLoaderVersion = ""
            return
        }

        let preferredVersion = selectedLoaderVersion
        await store.loadLoaderVersions(gameVersion: instance.versionID, loader: loader)
        guard selectedLoader == loader else { return }

        let versions = store.loaderVersions[loader, default: []]
        selectedLoaderVersion = versions.first { $0.version == preferredVersion }?.version
            ?? versions.first?.version
            ?? ""
    }

    private func applyChanges() {
        guard canApply else { return }
        isApplying = true
        Task {
            var updated = instance
            updated.loader = selectedLoader
            updated.loaderVersion = selectedTargetVersion
            await store.updateInstance(updated)
            onApply(updated)
            await store.install(updated)
            isApplying = false
            dismiss()
        }
    }
}
