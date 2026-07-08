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
                        Button("新建实例") { store.presentNewInstance() }
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
            .frame(minWidth: 220, idealWidth: 320, maxWidth: 420)

            if let instance = store.selectedInstance {
                InstanceDetailView(store: store, instance: instance)
                    .id(instance.id)
                    .frame(minWidth: 320)
            } else {
                ContentUnavailableView("选择一个实例", systemImage: "sidebar.right")
                    .frame(minWidth: 320)
            }
        }
    }
}

private struct InstanceRow: View {
    let store: LauncherStore
    let instance: LauncherInstance

    var body: some View {
        HStack(spacing: 12) {
            InstanceIconView(
                store: store,
                instance: instance,
                size: 38,
                tint: store.isInstalled(instance) ? .green : .secondary
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(instance.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("MC \(instance.versionID) · \(instance.loader.title) · \(store.installationStatus(for: instance))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            Spacer()
        }
        .padding(.vertical, 5)
    }
}

struct InstanceDetailView: View {
    @Bindable var store: LauncherStore
    @ViewState private var draft: LauncherInstance
    @ViewState private var isConfirmingDelete = false
    @ViewState private var isSelectingIcon = false
    @ViewState private var isSelectingJava = false
    @ViewState private var isManagingLoader = false

    init(store: LauncherStore, instance: LauncherInstance) {
        self.store = store
        _draft = ViewState(initialValue: instance)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                instanceHeader

                Form {
                    Section("实例") {
                        TextField("名称", text: $draft.name)
                        LabeledContent("实例图标") {
                            HStack(spacing: 8) {
                                InstanceIconView(store: store, instance: draft, size: 34)
                                Button("选择图片…") { isSelectingIcon = true }
                                if draft.iconFileName != nil {
                                    Button("恢复默认") {
                                        Task {
                                            await store.removeInstanceIcon(draft)
                                            draft.iconFileName = nil
                                        }
                                    }
                                }
                            }
                        }
                        LabeledContent("游戏版本", value: draft.versionID)
                        LabeledContent("来源", value: "Mojang 官方")
                        LabeledContent("加载器") {
                            HStack(spacing: 8) {
                                Text(loaderSummary)
                                    .foregroundStyle(.secondary)
                                Button("安装/更换…") {
                                    isManagingLoader = true
                                }
                                .disabled(store.isWorking(on: draft))
                            }
                        }
                        Toggle("启用版本隔离", isOn: $draft.isVersionIsolated)
                        Text(
                            draft.isVersionIsolated
                                ? "存档、模组、配置和日志保存在此实例的独立目录中。"
                                : "此实例将与其他未隔离实例共用游戏目录。"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        LabeledContent(
                            "状态",
                            value: store.installationStatus(for: draft)
                        )
                    }

                    Section("运行") {
                        Picker(
                            "Java 运行时",
                            selection: Binding(
                                get: { draft.usesAutomaticJava ? nil : draft.javaPath },
                                set: { newValue in
                                    draft.usesAutomaticJava = newValue == nil
                                    draft.javaPath = newValue
                                }
                            )
                        ) {
                            Text(automaticJavaLabel).tag(String?.none)
                            ForEach(store.javaRuntimes) { runtime in
                                Text("\(runtime.displayName) — \(runtime.vendor)")
                                    .tag(String?.some(runtime.path))
                            }
                        }
                        LabeledContent("自定义 Java") {
                            Button("选择 Java Home 或 java…") { isSelectingJava = true }
                        }
                        Picker("游戏账户", selection: $draft.accountID) {
                            Text("使用当前账户").tag(UUID?.none)
                            ForEach(store.accounts) { account in
                                Text("\(account.username)（\(account.kind.title)）")
                                    .tag(UUID?.some(account.id))
                            }
                        }
                        TextField(
                            "游戏窗口标题（默认使用实例名称）",
                            text: Binding(
                                get: { draft.launchTitle ?? "" },
                                set: { value in
                                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                                    draft.launchTitle = trimmed.isEmpty ? nil : value
                                }
                            )
                        )
                        Stepper("最大内存：\(draft.memoryMB) MB", value: $draft.memoryMB, in: 1024...32768, step: 512)
                        TextField(
                            "额外 JVM 参数",
                            text: Binding(
                                get: { draft.additionalJVMArguments.joined(separator: " ") },
                                set: { draft.additionalJVMArguments = $0.split(separator: " ").map(String.init) }
                            )
                        )
                    }

                    Section("服务器") {
                        Toggle("启动后自动加入服务器", isOn: $draft.autoJoinServer)
                        if draft.autoJoinServer {
                            TextField("服务器地址，例如 play.example.com", text: $draft.serverHost)
                            TextField("端口（默认 25565）", value: $draft.serverPort, format: .number)
                        }
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
                        .disabled(store.isWorking(on: draft))
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
        .fileImporter(
            isPresented: $isSelectingIcon,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task {
                await store.setInstanceIcon(from: url, for: draft)
                draft.iconFileName = "icon.png"
            }
        }
        .fileImporter(
            isPresented: $isSelectingJava,
            allowedContentTypes: [.folder, .unixExecutable],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task {
                if let runtime = await store.registerCustomJava(at: url) {
                    draft.usesAutomaticJava = false
                    draft.javaPath = runtime.path
                }
            }
        }
        .sheet(isPresented: $isManagingLoader) {
            InstanceLoaderSheet(store: store, instance: draft) { updated in
                draft = updated
            }
        }
    }

    private var instanceHeader: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                instanceHeaderSummary
                Spacer(minLength: 12)
                launchButton
            }

            VStack(alignment: .leading, spacing: 14) {
                instanceHeaderSummary
                launchButton
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var instanceHeaderSummary: some View {
        HStack(spacing: 14) {
            InstanceIconView(store: store, instance: draft, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(draft.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text("Minecraft \(draft.versionID) · \(store.installationStatus(for: draft))")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var launchButton: some View {
        Button {
            Task {
                await store.updateInstance(draft)
                store.selectedInstanceID = draft.id
                await store.launchSelectedInstance()
            }
        } label: {
            Label(store.launchButtonTitle(for: draft), systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .controlSize(.large)
        .disabled(store.isWorking(on: draft) || store.gameProcessID != nil)
    }

    private var automaticJavaLabel: String {
        if let major = store.requiredJavaMajor(for: draft) {
            return "自动选择（推荐 Java \(major)）"
        }
        return "自动选择（按官方版本要求）"
    }

    private var loaderSummary: String {
        if draft.loader == .vanilla {
            return draft.loader.title
        }
        return "\(draft.loader.title) \(draft.loaderVersion ?? "")"
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
            selectedVersionID = store.consumeNewInstanceSuggestedVersionID()
                ?? store.manifest?.latest.release
                ?? ""
            if let version = store.manifest?.versions.first(where: { $0.id == selectedVersionID }) {
                selectedType = version.type
            }
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
