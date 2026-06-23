import SwiftUI
import UniformTypeIdentifiers

struct InstancesView: View {
    @Bindable var store: LauncherStore
    @ViewState private var searchText = ""

    private var filteredInstances: [LauncherInstance] {
        guard !searchText.isEmpty else { return store.instances }
        return store.instances.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.versionID.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        HSplitView {
            Group {
                if store.instances.isEmpty {
                    ContentUnavailableView {
                        Label("还没有实例", systemImage: "shippingbox")
                    } description: {
                        Text("实例会保存独立的存档、模组和设置。")
                    } actions: {
                        Button("新建实例") { store.isPresentingNewInstance = true }
                    }
                } else {
                    List(filteredInstances, selection: $store.selectedInstanceID) { instance in
                        InstanceRow(store: store, instance: instance)
                            .tag(instance.id)
                            .contextMenu {
                                Button("在访达中显示") { store.openGameDirectory(instance) }
                                Button("删除实例", role: .destructive) {
                                    Task { await store.deleteInstance(instance) }
                                }
                            }
                    }
                    .listStyle(.inset)
                    .searchable(text: $searchText, prompt: "搜索实例或版本")
                }
            }
            .frame(minWidth: 310, idealWidth: 390)

            if let instance = store.selectedInstance {
                InstanceDetailView(store: store, instance: instance)
                    .id(instance.id)
                    .frame(minWidth: 430)
            } else {
                ContentUnavailableView("选择一个实例", systemImage: "sidebar.right")
                    .frame(minWidth: 430)
            }
        }
    }
}

private struct InstanceRow: View {
    let store: LauncherStore
    let instance: LauncherInstance

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(store.isInstalled(instance) ? .green : .secondary)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(instance.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text("MC \(instance.versionID)")
                    Text("·")
                    Text(instance.loader.title)
                    Text("·")
                    Text(store.isInstalled(instance) ? "已安装" : "未安装")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 5)
    }
}

private struct InstanceDetailView: View {
    @Bindable var store: LauncherStore
    @ViewState private var draft: LauncherInstance
    @ViewState private var isConfirmingDelete = false
    @ViewState private var isImportingMods = false
    @ViewState private var modPendingDeletion: ModFile?

    init(store: LauncherStore, instance: LauncherInstance) {
        self.store = store
        _draft = ViewState(initialValue: instance)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(draft.name)
                            .font(.title2.weight(.semibold))
                        Text("Minecraft \(draft.versionID) · \(store.isInstalled(draft) ? "已安装" : "等待安装")")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task {
                            await store.updateInstance(draft)
                            await store.launchSelectedInstance()
                        }
                    } label: {
                        Label(store.isInstalled(draft) ? "启动游戏" : "安装并启动", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                    .disabled(store.isBusy)
                }

                Form {
                    Section("实例") {
                        TextField("名称", text: $draft.name)
                        LabeledContent("游戏版本", value: draft.versionID)
                        LabeledContent("来源", value: "Mojang 官方")
                        LabeledContent(
                            "加载器",
                            value: draft.loader == .vanilla
                                ? draft.loader.title
                                : "\(draft.loader.title) \(draft.loaderVersion ?? "")"
                        )
                        Toggle("启用版本隔离", isOn: $draft.isVersionIsolated)
                        Text(
                            draft.isVersionIsolated
                                ? "存档、模组、配置和日志保存在此实例的独立目录中。"
                                : "此实例将与其他未隔离实例共用游戏目录。"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        LabeledContent("状态", value: store.isInstalled(draft) ? "文件完整" : "尚未安装")
                    }

                    Section("运行") {
                        Picker("Java 运行时", selection: $draft.javaPath) {
                            Text("自动选择").tag(String?.none)
                            ForEach(store.javaRuntimes) { runtime in
                                Text("\(runtime.displayName) — \(runtime.vendor)")
                                    .tag(String?.some(runtime.path))
                            }
                        }
                        Picker("游戏账户", selection: $draft.accountID) {
                            Text("使用当前账户").tag(UUID?.none)
                            ForEach(store.accounts) { account in
                                Text("\(account.username)（\(account.kind.title)）")
                                    .tag(UUID?.some(account.id))
                            }
                        }
                        Stepper("最大内存：\(draft.memoryMB) MB", value: $draft.memoryMB, in: 1024...32768, step: 512)
                        TextField(
                            "额外 JVM 参数",
                            text: Binding(
                                get: { draft.additionalJVMArguments.joined(separator: " ") },
                                set: { draft.additionalJVMArguments = $0.split(separator: " ").map(String.init) }
                            )
                        )
                    }

                    Section("窗口") {
                        Toggle(
                            "自定义分辨率",
                            isOn: Binding(
                                get: { draft.resolutionWidth != nil },
                                set: { enabled in
                                    draft.resolutionWidth = enabled ? (draft.resolutionWidth ?? 1280) : nil
                                    draft.resolutionHeight = enabled ? (draft.resolutionHeight ?? 720) : nil
                                }
                            )
                        )
                        if draft.resolutionWidth != nil {
                            HStack {
                                TextField("宽度", value: $draft.resolutionWidth, format: .number)
                                Text("×")
                                TextField("高度", value: $draft.resolutionHeight, format: .number)
                            }
                        }
                    }

                    Section("模组") {
                        if draft.loader == .vanilla {
                            Text("原版实例可以保存模组文件，但启动模组通常需要 Fabric 或 Quilt。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if store.mods[draft.id, default: []].isEmpty {
                            Text("尚未导入模组")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(store.mods[draft.id, default: []]) { mod in
                                HStack {
                                    Button {
                                        Task { await store.setMod(mod, enabled: !mod.isEnabled, for: draft) }
                                    } label: {
                                        Image(systemName: mod.isEnabled ? "checkmark.circle.fill" : "circle")
                                            .foregroundStyle(mod.isEnabled ? .green : .secondary)
                                    }
                                    .buttonStyle(.plain)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mod.displayName)
                                            .lineLimit(1)
                                        Text(mod.size.formatted(.byteCount(style: .file)))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(role: .destructive) {
                                        modPendingDeletion = mod
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }

                        Button {
                            isImportingMods = true
                        } label: {
                            Label("导入模组 JAR", systemImage: "square.and.arrow.down")
                        }
                    }
                }
                .formStyle(.grouped)

                HStack {
                    Button("在访达中显示") { store.openGameDirectory(draft) }
                    Button("删除实例", role: .destructive) { isConfirmingDelete = true }
                    Spacer()
                    if !store.isInstalled(draft) {
                        Button("仅安装") {
                            Task {
                                await store.updateInstance(draft)
                                await store.install(draft)
                            }
                        }
                        .disabled(store.isBusy)
                    }
                    Button("保存设置") {
                        Task { await store.updateInstance(draft) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(26)
        }
        .confirmationDialog("删除“\(draft.name)”及其全部游戏文件？", isPresented: $isConfirmingDelete) {
            Button("删除", role: .destructive) {
                Task { await store.deleteInstance(draft) }
            }
        }
        .confirmationDialog(
            "移除模组“\(modPendingDeletion?.displayName ?? "")”？",
            isPresented: Binding(
                get: { modPendingDeletion != nil },
                set: { if !$0 { modPendingDeletion = nil } }
            )
        ) {
            Button("移除", role: .destructive) {
                if let mod = modPendingDeletion {
                    Task { await store.removeMod(mod, for: draft) }
                }
                modPendingDeletion = nil
            }
        }
        .fileImporter(
            isPresented: $isImportingMods,
            allowedContentTypes: [UTType(filenameExtension: "jar") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task { await store.importMods(urls, for: draft) }
            }
        }
        .task {
            await store.loadMods(for: draft)
        }
    }
}

struct NewInstanceSheet: View {
    @Bindable var store: LauncherStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var name = ""
    @ViewState private var selectedVersionID = ""
    @ViewState private var selectedType: VersionType = .release
    @ViewState private var searchText = ""
    @ViewState private var selectedLoader: ModLoader = .vanilla
    @ViewState private var selectedLoaderVersion = ""
    @ViewState private var isVersionIsolated = true
    @ViewState private var usesSuggestedName = true

    private var versions: [MinecraftVersion] {
        (store.manifest?.versions ?? []).filter {
            $0.type == selectedType && (searchText.isEmpty || $0.id.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("创建游戏实例")
                        .font(.title2.weight(.semibold))
                    Text("选择官方版本、加载器和独立的实例名称。")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(22)

            Divider()

            HSplitView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("1. 选择 Minecraft 版本")
                        .font(.headline)

                    Picker("版本类型", selection: $selectedType) {
                        ForEach(VersionType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("搜索 Mojang 官方版本", text: $searchText)
                        .textFieldStyle(.roundedBorder)

                    List(versions.prefix(250), selection: $selectedVersionID) { version in
                        VersionRow(version: version)
                            .tag(version.id)
                    }
                    .overlay {
                        if store.manifest == nil {
                            ProgressView("正在读取官方版本列表…")
                        } else if versions.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }

                    Text("共 \(versions.count) 个真实版本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(minWidth: 420, idealWidth: 470)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("2. 选择加载器")
                                .font(.headline)

                            Picker("加载器", selection: $selectedLoader) {
                                ForEach(ModLoader.allCases) { loader in
                                    Text(loader.title).tag(loader)
                                }
                            }
                            .pickerStyle(.segmented)

                            if selectedLoader != .vanilla {
                                if store.isLoadingLoaderVersions {
                                    HStack(spacing: 8) {
                                        ProgressView()
                                            .controlSize(.small)
                                        Text("正在读取 \(selectedLoader.title) 版本…")
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Picker("加载器版本", selection: $selectedLoaderVersion) {
                                        if store.loaderVersions[selectedLoader, default: []].isEmpty {
                                            Text("该游戏版本暂无可用加载器").tag("")
                                        } else {
                                            ForEach(store.loaderVersions[selectedLoader, default: []]) { version in
                                                Text(version.stable == true ? "\(version.version)（稳定）" : version.version)
                                                    .tag(version.version)
                                            }
                                        }
                                    }
                                }
                            } else {
                                Text("不安装额外加载器，使用 Mojang 原版客户端。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("3. 命名与隔离")
                                .font(.headline)

                            TextField(
                                "实例名称，例如 Utopia3.5",
                                text: Binding(
                                    get: { name },
                                    set: {
                                        name = $0
                                        usesSuggestedName = false
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)

                            Toggle("启用版本隔离", isOn: $isVersionIsolated)

                            Text(
                                isVersionIsolated
                                    ? "默认开启：此实例拥有独立的存档、模组、配置与日志目录。"
                                    : "关闭后，此实例会与其他未隔离实例共用游戏目录。"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            instancePreview
                        }
                    }
                    .padding(22)
                }
                .frame(minWidth: 390, idealWidth: 430)
            }

            Divider()

            HStack {
                Label("版本来源：Mojang 官方", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }
                Button("创建并安装") {
                    Task {
                        await store.createInstance(
                            name: name,
                            versionID: selectedVersionID,
                            loader: selectedLoader,
                            loaderVersion: selectedLoader == .vanilla ? nil : selectedLoaderVersion,
                            isVersionIsolated: isVersionIsolated,
                            installAfterCreation: true
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || selectedVersionID.isEmpty
                        || (selectedLoader != .vanilla && selectedLoaderVersion.isEmpty)
                )
            }
            .padding(16)
        }
        .frame(width: 940, height: 680)
        .onAppear {
            selectedVersionID = store.manifest?.latest.release ?? ""
            if name.isEmpty, !selectedVersionID.isEmpty {
                name = suggestedName(for: selectedVersionID)
            }
        }
        .onChange(of: selectedVersionID) { _, newValue in
            if usesSuggestedName || name.isEmpty {
                name = suggestedName(for: newValue)
                usesSuggestedName = true
            }
            refreshLoaderVersions()
        }
        .onChange(of: selectedType) { _, _ in
            if !versions.contains(where: { $0.id == selectedVersionID }) {
                selectedVersionID = versions.first?.id ?? ""
            }
        }
        .onChange(of: selectedLoader) { _, _ in
            refreshLoaderVersions()
        }
    }

    private var instancePreview: some View {
        HStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(name.isEmpty ? "未命名实例" : name)
                    .font(.headline)
                    .lineLimit(1)
                Text(previewVersionLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.separator, lineWidth: 0.5)
        }
    }

    private var previewVersionLine: String {
        var value = selectedVersionID.isEmpty ? "请选择 MC 版本" : "MC \(selectedVersionID)"
        if selectedLoader != .vanilla {
            value += " · \(selectedLoader.title)"
        } else {
            value += " · 原版"
        }
        return value
    }

    private func suggestedName(for versionID: String) -> String {
        versionID.isEmpty ? "" : "Minecraft \(versionID)"
    }

    private func refreshLoaderVersions() {
        selectedLoaderVersion = ""
        guard selectedLoader != .vanilla, !selectedVersionID.isEmpty else { return }
        Task {
            await store.loadLoaderVersions(gameVersion: selectedVersionID, loader: selectedLoader)
            selectedLoaderVersion = store.loaderVersions[selectedLoader]?.first?.version ?? ""
        }
    }
}
