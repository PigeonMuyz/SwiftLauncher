import SwiftUI

struct DownloadsView: View {
    @Bindable var store: LauncherStore
    @State private var section: DownloadSection = .games
    @State private var versionType: VersionType = .release
    @State private var versionSearch = ""
    @State private var selectedVersionID = ""
    @State private var modSearch = ""
    @AppStorage(LauncherExperienceMode.defaultsKey) private var experienceMode = LauncherExperienceMode.beginner.rawValue
    @AppStorage(LauncherExperienceMode.autoDependenciesDefaultsKey) private var autoInstallRequiredMods = true

    var body: some View {
        VStack(spacing: 0) {
            Picker("下载内容", selection: $section) {
                ForEach(DownloadSection.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 520)
            .padding(.vertical, 12)

            Divider()

            Group {
                switch section {
                case .games:
                    gameDownloads
                case .mods:
                    modDownloads
                case .tasks:
                    taskList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            if selectedVersionID.isEmpty {
                selectedVersionID = store.manifest?.latest.release ?? ""
            }
            if store.selectedDownloadInstanceID == nil {
                store.selectedDownloadInstanceID = compatibleInstances.first?.id
            }
        }
        .onChange(of: versionType) { _, _ in
            selectedVersionID = filteredVersions.first?.id ?? ""
        }
        .onChange(of: store.selectedDownloadInstanceID) { _, _ in
            store.modrinthSearchResults = []
            store.modInstallPlan = nil
        }
        .sheet(
            isPresented: Binding(
                get: { store.modInstallPlan != nil },
                set: { if !$0 { store.modInstallPlan = nil } }
            )
        ) {
            if let instance = selectedDownloadInstance {
                ModDetailsSheet(store: store, instance: instance)
            }
        }
    }

    private var gameDownloads: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    Picker("版本类型", selection: $versionType) {
                        ForEach(VersionType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("搜索 Minecraft 版本", text: $versionSearch)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(14)

                Divider()

                List(filteredVersions.prefix(300), selection: $selectedVersionID) { version in
                    VersionRow(version: version)
                        .tag(version.id)
                }
                .overlay {
                    if store.manifest == nil {
                        ProgressView("正在读取版本清单…")
                    } else if filteredVersions.isEmpty {
                        ContentUnavailableView.search(text: versionSearch)
                    }
                }
            }
            .frame(width: 360)

            Divider()

            if let version = selectedGameVersion {
                VStack(alignment: .leading, spacing: 22) {
                    Spacer()
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Minecraft \(version.id)")
                            .font(.largeTitle.weight(.semibold))
                        Text("\(version.type.title) · 发布于 \(version.releaseTime.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                    Text("下一步可以选择原版、Fabric、Quilt、Forge 或 NeoForge，并设置实例名称。基础游戏文件会进入共享缓存，同一版本无需重复下载。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        store.presentNewInstance(versionID: version.id)
                    } label: {
                        Label("选择加载器并安装", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .controlSize(.large)
                    Spacer()
                }
                .padding(36)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView("选择一个游戏版本", systemImage: "shippingbox")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var modDownloads: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("目标实例", selection: $store.selectedDownloadInstanceID) {
                    Text("选择已安装加载器的实例").tag(UUID?.none)
                    ForEach(compatibleInstances) { instance in
                        Text("\(instance.name) · MC \(instance.versionID) · \(instance.loader.title)")
                            .tag(UUID?.some(instance.id))
                    }
                }
                .frame(minWidth: 300, maxWidth: 430)

                TextField("搜索 Modrinth 模组", text: $modSearch)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { searchMods() }

                Button {
                    searchMods()
                } label: {
                    if store.isSearchingMods {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("搜索", systemImage: "magnifyingglass")
                    }
                }
                .disabled(selectedDownloadInstance == nil || store.isSearchingMods)
            }
            .padding(14)

            HStack(spacing: 8) {
                Label(selectedExperienceMode.title, systemImage: modeSystemImage)
                    .font(.caption.weight(.semibold))
                if selectedExperienceMode == .normal {
                    Toggle("自动补全必需前置", isOn: $autoInstallRequiredMods)
                        .toggleStyle(.checkbox)
                } else {
                    Text(selectedExperienceMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider()

            if compatibleInstances.isEmpty {
                ContentUnavailableView {
                    Label("没有可安装模组的实例", systemImage: "puzzlepiece.extension")
                } description: {
                    Text("请先在“游戏”中创建 Fabric、Quilt、Forge 或 NeoForge 实例。")
                } actions: {
                    Button("下载游戏实例") { section = .games }
                }
            } else if store.modrinthSearchResults.isEmpty && !store.isSearchingMods {
                ContentUnavailableView {
                    Label("从 Modrinth 获取模组", systemImage: "puzzlepiece.extension")
                } description: {
                    Text("结果会按目标实例的 Minecraft 版本和加载器过滤；安装时也会补全 Modrinth 声明的必需前置。")
                } actions: {
                    Button("查看热门模组") { searchMods() }
                }
            } else {
                List(store.modrinthSearchResults) { project in
                    HStack(spacing: 14) {
                        AsyncImage(url: project.iconURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Image(systemName: "puzzlepiece.extension.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(10)
                                    .foregroundStyle(.green)
                            }
                        }
                        .frame(width: 52, height: 52)
                        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 7) {
                                Text(project.title).font(.headline)
                                Text("by \(project.author)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(project.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text("\(project.downloads.formatted()) 次下载")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer(minLength: 16)
                        Button(selectedExperienceMode == .expert ? "查看详情" : "选择版本") {
                            guard let instance = selectedDownloadInstance else { return }
                            Task { await store.showModDetails(project, for: instance) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(store.isBusy || store.isLoadingModDetails)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var taskList: some View {
        Group {
            if store.downloads.isEmpty {
                ContentUnavailableView {
                    Label("没有下载任务", systemImage: "arrow.down.circle")
                } description: {
                    Text("游戏、模组和导入任务的真实进度会显示在这里。")
                }
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("下载与导入记录")
                            .font(.headline)
                        Spacer()
                        Button("清除已完成") { store.clearCompletedDownloads() }
                    }
                    .padding(14)
                    Divider()
                    List(store.downloads) { task in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Image(systemName: icon(for: task.state))
                                    .foregroundStyle(color(for: task.state))
                                Text(task.title)
                                    .font(.headline)
                                Spacer()
                                Text(task.state.title)
                                    .foregroundStyle(.secondary)
                            }
                            Text(task.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if task.state == .downloading || task.state == .queued {
                                ProgressView(value: task.progress)
                                    .tint(.green)
                            }
                            if let error = task.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private var filteredVersions: [MinecraftVersion] {
        (store.manifest?.versions ?? []).filter {
            $0.type == versionType
                && (versionSearch.isEmpty || $0.id.localizedCaseInsensitiveContains(versionSearch))
        }
    }

    private var selectedGameVersion: MinecraftVersion? {
        store.manifest?.versions.first { $0.id == selectedVersionID }
    }

    private var compatibleInstances: [LauncherInstance] {
        store.instances.filter { $0.loader != .vanilla }
    }

    private var selectedDownloadInstance: LauncherInstance? {
        compatibleInstances.first { $0.id == store.selectedDownloadInstanceID }
    }

    private var selectedExperienceMode: LauncherExperienceMode {
        LauncherExperienceMode(rawValue: experienceMode) ?? .beginner
    }

    private var modeSystemImage: String {
        switch selectedExperienceMode {
        case .beginner: "wand.and.stars"
        case .normal: "slider.horizontal.3"
        case .expert: "info.circle"
        }
    }

    private func searchMods() {
        guard let instance = selectedDownloadInstance else { return }
        Task { await store.searchMods(query: modSearch, for: instance) }
    }

    private func icon(for state: DownloadState) -> String {
        switch state {
        case .queued: "clock"
        case .downloading: "arrow.down.circle"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private func color(for state: DownloadState) -> Color {
        switch state {
        case .completed: .green
        case .failed: .red
        case .downloading: .blue
        case .queued, .cancelled: .secondary
        }
    }
}

private struct ModDetailsSheet: View {
    let store: LauncherStore
    let instance: LauncherInstance
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LauncherExperienceMode.defaultsKey) private var experienceMode = LauncherExperienceMode.beginner.rawValue
    @AppStorage(LauncherExperienceMode.autoDependenciesDefaultsKey) private var autoInstallRequiredMods = true

    private var plan: ModrinthInstallPlan? {
        store.modInstallPlan
    }

    private var selectedExperienceMode: LauncherExperienceMode {
        LauncherExperienceMode(rawValue: experienceMode) ?? .beginner
    }

    private var installButtonTitle: String {
        switch selectedExperienceMode {
        case .beginner:
            "安装此版本及必需前置"
        case .normal:
            autoInstallRequiredMods ? "安装此版本及必需前置" : "仅安装此版本"
        case .expert:
            "仅安装此版本"
        }
    }

    var body: some View {
        Group {
            if let plan {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 16) {
                        AsyncImage(url: plan.project.iconURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Image(systemName: "puzzlepiece.extension.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(13)
                                    .foregroundStyle(.green)
                            }
                        }
                        .frame(width: 64, height: 64)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 13))
                        .clipShape(RoundedRectangle(cornerRadius: 13))

                        VStack(alignment: .leading, spacing: 5) {
                            Text(plan.project.title)
                                .font(.title2.weight(.semibold))
                            Text(plan.project.description)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text("目标：\(instance.name) · MC \(instance.versionID) · \(instance.loader.title)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(22)

                    Divider()

                    Form {
                        Section("选择 Mod 版本") {
                            Picker(
                                "兼容版本",
                                selection: Binding(
                                    get: { plan.selectedVersionID },
                                    set: { versionID in
                                        Task {
                                            await store.showModDetails(
                                                plan.project,
                                                for: instance,
                                                selectedVersionID: versionID
                                            )
                                        }
                                    }
                                )
                            ) {
                                ForEach(plan.versions) { version in
                                    Text("\(version.versionNumber) — \(version.name)")
                                        .tag(version.id)
                                }
                            }
                            .disabled(store.isLoadingModDetails)

                            if let selectedVersion = plan.versions.first(where: { $0.id == plan.selectedVersionID }) {
                                LabeledContent("版本名称", value: selectedVersion.name)
                                LabeledContent("版本号", value: selectedVersion.versionNumber)
                                LabeledContent(
                                    "支持 Minecraft",
                                    value: selectedVersion.supportedMinecraftVersionsText
                                )
                                LabeledContent("加载器", value: selectedVersion.loadersText)
                                if let fileName = selectedVersion.primaryFileName {
                                    LabeledContent("文件", value: fileName)
                                }
                            }
                        }

                        Section("必需前置 Mod（\(plan.requiredDependencies.count)）") {
                            if plan.requiredDependencies.isEmpty {
                                Text("此版本没有声明必需前置。")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(plan.requiredDependencies) { dependency in
                                    HStack(spacing: 10) {
                                        AsyncImage(url: dependency.iconURL) { phase in
                                            if let image = phase.image {
                                                image.resizable().scaledToFill()
                                            } else {
                                                Image(systemName: "puzzlepiece.extension")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .frame(width: 30, height: 30)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(dependency.title)
                                                .font(.body.weight(.medium))
                                            Text("\(dependency.versionNumber) · \(dependency.versionName)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                        .padding(.leading, CGFloat(dependency.depth) * 14)
                                        Spacer()
                                        Link(destination: dependency.projectURL) {
                                            Label("下载页", systemImage: "arrow.up.right.square")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .overlay {
                        if store.isLoadingModDetails {
                            ProgressView("正在读取版本与前置信息…")
                                .padding(18)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    Divider()
                    HStack {
                        Text(selectedExperienceMode.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                        Button("取消") { dismiss() }
                        Button(installButtonTitle) {
                            dismiss()
                            Task {
                                await store.installMod(
                                    plan.project,
                                    for: instance,
                                    specificVersionID: plan.selectedVersionID
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(store.isLoadingModDetails)
                    }
                    .padding(16)
                }
            } else {
                ProgressView("正在读取 Modrinth 版本…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 780, height: 680)
    }
}

private enum DownloadSection: String, CaseIterable, Identifiable {
    case games
    case mods
    case tasks

    var id: Self { self }

    var title: String {
        switch self {
        case .games: "游戏"
        case .mods: "模组"
        case .tasks: "任务"
        }
    }

    var systemImage: String {
        switch self {
        case .games: "shippingbox"
        case .mods: "puzzlepiece.extension"
        case .tasks: "list.bullet.rectangle"
        }
    }
}
