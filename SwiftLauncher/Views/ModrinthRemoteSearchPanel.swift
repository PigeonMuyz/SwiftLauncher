import SwiftUI

struct ModrinthRemoteSearchPanel: View {
    @Bindable var store: LauncherStore
    let kind: ModrinthContentKind
    let instance: LauncherInstance
    @Binding var query: String
    @Binding var filtersCurrentInstanceVersion: Bool
    var allowsTargetSelectionOnInstall = false
    @ViewState private var targetSelectionProject: ModrinthSearchResult?

    init(
        store: LauncherStore,
        kind: ModrinthContentKind,
        instance: LauncherInstance,
        query: Binding<String>,
        filtersCurrentInstanceVersion: Binding<Bool> = .constant(false),
        allowsTargetSelectionOnInstall: Bool = false
    ) {
        self.store = store
        self.kind = kind
        self.instance = instance
        self._query = query
        self._filtersCurrentInstanceVersion = filtersCurrentInstanceVersion
        self.allowsTargetSelectionOnInstall = allowsTargetSelectionOnInstall
    }

    private var isCurrentContext: Bool {
        store.selectedDownloadContentKind == kind && store.selectedDownloadInstanceID == instance.id
    }

    private var isSearching: Bool {
        isCurrentContext && store.isSearchingMods
    }

    private var results: [ModrinthSearchResult] {
        isCurrentContext ? store.modrinthSearchResults : []
    }

    private var accentColor: Color {
        switch kind {
        case .mods: .green
        case .resourcePacks: .teal
        case .shaderPacks: .orange
        case .dataPacks: .blue
        case .modpacks: .purple
        }
    }

    var body: some View {
        resultsBody
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .searchable(text: $query, placement: .toolbar, prompt: "搜索资源")
        .onSubmit(of: .search) {
            Task { await search(loadIfEmptyOnly: false) }
        }
        .onChange(of: query) { oldValue, newValue in
            guard !oldValue.isEmpty && newValue.isEmpty else { return }
            Task { await search(loadIfEmptyOnly: false) }
        }
        .task(id: "\(kind.id)-\(instance.id)-\(filtersCurrentInstanceVersion)") {
            prepareContext(clearResults: true)
            await search(loadIfEmptyOnly: true)
        }
        .sheet(item: $targetSelectionProject) { project in
            installTargetSheet(project)
        }
    }

    @ViewBuilder
    private var resultsBody: some View {
        if !isCurrentContext || results.isEmpty && !isSearching {
            ContentUnavailableView {
                Label("没有\(kind.title)结果", systemImage: kind.systemImage)
            } description: {
                Text("可以换关键词，或清除筛选后再试。")
            } actions: {
                Button("查看热门\(kind.title)") {
                    query = ""
                    Task { await search(loadIfEmptyOnly: false) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { project in
                        resultRow(project)
                        Divider()
                            .padding(.leading, 88)
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func resultRow(_ project: ModrinthSearchResult) -> some View {
        HStack(alignment: .center, spacing: 14) {
            RemoteImageIconView(
                url: project.iconURL,
                systemImage: kind.systemImage,
                tint: accentColor
            )
            .frame(width: 56, height: 56)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 9))
            .clipShape(RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(project.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("by \(project.author)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(project.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if !project.categories.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(project.categories.prefix(3), id: \.self) { category in
                            Text(category)
                                .font(.caption2.weight(.semibold))
                                .padding(.vertical, 2)
                                .padding(.horizontal, 5)
                                .background(Color.secondary.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                        }
                        if project.categories.count > 3 {
                            Text("+\(project.categories.count - 3)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 7) {
                Label(project.downloads.formatted(.number.notation(.compactName)), systemImage: "arrow.down.circle")
                Label(project.follows.formatted(.number.notation(.compactName)), systemImage: "heart")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .frame(width: 82, alignment: .trailing)

            Button(installButtonTitle) {
                install(project)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentColor)
            .frame(width: 82)
            .disabled(store.isLoadingModDetails || installButtonDisabled)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 18)
    }

    private var installButtonTitle: String {
        if kind.requiresModLoader, instance.loader == .vanilla, allowsTargetSelectionOnInstall {
            return "选择实例"
        }
        if !kind.supportsDirectInstall {
            return "选择版本"
        }
        return "安装"
    }

    private var installButtonDisabled: Bool {
        switch kind {
        case .mods:
            false
        case .resourcePacks, .shaderPacks:
            installTargets.isEmpty
        case .dataPacks, .modpacks:
            false
        }
    }

    private var installTargets: [LauncherInstance] {
        store.instances.filter { target in
            if kind.requiresModLoader {
                return target.loader != .vanilla
            }
            return true
        }
    }

    private func install(_ project: ModrinthSearchResult) {
        if kind.requiresModLoader,
           instance.loader == .vanilla,
           allowsTargetSelectionOnInstall {
            targetSelectionProject = project
            return
        }
        prepareContext(clearResults: false, targetInstance: instance)
        Task {
            await store.showModrinthDetails(kind, project, for: instance)
        }
    }

    private func installTargetSheet(_ project: ModrinthSearchResult) -> some View {
        NavigationStack {
            Group {
                if installTargets.isEmpty {
                    ContentUnavailableView {
                        Label("没有可安装模组的实例", systemImage: "puzzlepiece.extension")
                    } description: {
                        Text("请先在实例设置中为某个实例安装 Fabric、Quilt、Forge 或 NeoForge。")
                    }
                } else {
                    List(installTargets) { target in
                        Button {
                            targetSelectionProject = nil
                            prepareContext(clearResults: false, targetInstance: target)
                            Task {
                                await store.showModrinthDetails(kind, project, for: target)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                InstanceIconView(store: store, instance: target, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(target.name)
                                        .font(.headline)
                                    Text("Minecraft \(target.versionID) · \(target.loader.title)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("选择安装实例")
        }
        .frame(width: 460, height: 420)
    }

    private func search(loadIfEmptyOnly: Bool) async {
        prepareContext(clearResults: false, targetInstance: instance)
        guard !loadIfEmptyOnly || results.isEmpty else { return }
        await store.searchModrinthContent(
            kind,
            query: query,
            for: instance,
            filtersCurrentInstanceVersion: filtersCurrentInstanceVersion
        )
    }

    private func prepareContext(clearResults: Bool, targetInstance: LauncherInstance? = nil) {
        let targetID = targetInstance?.id ?? instance.id
        let contextChanged = store.selectedDownloadContentKind != kind || store.selectedDownloadInstanceID != targetID
        guard contextChanged || clearResults else { return }
        store.selectedDownloadContentKind = kind
        store.selectedDownloadInstanceID = targetID
        store.modInstallPlan = nil
        if clearResults || contextChanged {
            store.modrinthSearchResults = []
        }
    }
}
