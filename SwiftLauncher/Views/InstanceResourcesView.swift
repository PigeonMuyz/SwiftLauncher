import SwiftUI
import UniformTypeIdentifiers

struct InstanceResourcesView: View {
    @Bindable var store: LauncherStore

    @ViewState private var selectedKind: InstanceResourceKind = .mods
    @ViewState private var remoteQuery = ""
    @ViewState private var isImporting = false
    @ViewState private var isManagingLoader = false
    @ViewState private var modPendingDeletion: ModFile?

    var body: some View {
        Group {
            if let instance = store.selectedInstance {
                content(for: instance)
            } else {
                ContentUnavailableView {
                    Label("未选择实例", systemImage: "shippingbox")
                } description: {
                    Text("请先在左下角选择一个游戏实例。")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog(
            "移除模组“\(modPendingDeletion?.displayName ?? "")”？",
            isPresented: Binding(
                get: { modPendingDeletion != nil },
                set: { if !$0 { modPendingDeletion = nil } }
            )
        ) {
            Button("移除", role: .destructive) {
                if let mod = modPendingDeletion, let instance = store.selectedInstance {
                    Task { await store.removeMod(mod, for: instance) }
                }
                modPendingDeletion = nil
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: selectedKind.allowedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result, let instance = store.selectedInstance else { return }
            Task { await importFiles(urls, for: instance) }
        }
        .sheet(
            isPresented: Binding(
                get: {
                    store.modInstallPlan?.kind == selectedKind.modrinthKind
                        && store.selectedDownloadInstanceID == store.selectedInstanceID
                },
                set: { if !$0 { store.modInstallPlan = nil } }
            )
        ) {
            if let instance = store.selectedInstance {
                ModrinthDetailsSheet(store: store, instance: instance)
            }
        }
        .sheet(isPresented: $isManagingLoader) {
            if let instance = store.selectedInstance {
                InstanceLoaderSheet(store: store, instance: instance)
            }
        }
    }

    private func content(for instance: LauncherInstance) -> some View {
        VStack(spacing: 0) {
            instanceHeader(instance)
            Divider()
            HSplitView {
                installedPane(for: instance)
                    .frame(minWidth: 300, idealWidth: 360, maxWidth: 460)
                remotePane(for: instance)
                    .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(instance.id)-\(selectedKind.id)") {
            await loadInstalled(for: instance)
        }
    }

    private func instanceHeader(_ instance: LauncherInstance) -> some View {
        HStack(spacing: 14) {
            InstanceIconView(store: store, instance: instance, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("Minecraft \(instance.versionID) · \(instance.loader.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Picker("资源类型", selection: $selectedKind) {
                ForEach(InstanceResourceKind.allCases) { kind in
                    Label(kind.title, systemImage: kind.systemImage)
                        .tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 390)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func installedPane(for instance: LauncherInstance) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("已安装\(selectedKind.title)", systemImage: selectedKind.systemImage)
                    .font(.headline)
                Spacer()
                Button {
                    isImporting = true
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .disabled(selectedKind == .mods && instance.loader == .vanilla)
            }
            .padding(14)

            Divider()

            installedList(for: instance)
        }
        .background(.bar)
    }

    @ViewBuilder
    private func installedList(for instance: LauncherInstance) -> some View {
        switch selectedKind {
        case .mods:
            let mods = store.mods[instance.id, default: []]
            if mods.isEmpty {
                emptyInstalledView("尚未导入模组", systemImage: selectedKind.systemImage)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(mods) { mod in
                            modRow(mod, instance: instance)
                        }
                    }
                    .padding(12)
                }
            }
        case .resourcePacks:
            managedContentList(
                files: store.resourcePacks[instance.id, default: []],
                kind: .resourcePacks,
                systemImage: selectedKind.systemImage,
                emptyTitle: "尚未导入资源包",
                instance: instance
            )
        case .shaderPacks:
            managedContentList(
                files: store.shaderPacks[instance.id, default: []],
                kind: .shaderPacks,
                systemImage: selectedKind.systemImage,
                emptyTitle: "尚未导入光影包",
                instance: instance
            )
        }
    }

    private func managedContentList(
        files: [ManagedContentFile],
        kind: ManagedContentKind,
        systemImage: String,
        emptyTitle: String,
        instance: LauncherInstance
    ) -> some View {
        Group {
            if files.isEmpty {
                emptyInstalledView(emptyTitle, systemImage: systemImage)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(files) { file in
                            managedFileRow(file, kind: kind, systemImage: systemImage, instance: instance)
                        }
                    }
                    .padding(12)
                }
            }
        }
    }

    private func emptyInstalledView(_ title: String, systemImage: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text("可以从右侧远程资源安装，或导入本地文件。")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func remotePane(for instance: LauncherInstance) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label("远程\(selectedKind.title)", systemImage: "magnifyingglass")
                    .font(.headline)
                Spacer()
                Text("按 \(instance.versionID) 自动过滤")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if selectedKind == .mods && instance.loader == .vanilla {
                loaderRequiredView(for: instance)
            } else {
                ModrinthRemoteSearchPanel(
                    store: store,
                    kind: selectedKind.modrinthKind,
                    instance: instance,
                    query: $remoteQuery
                )
            }
        }
    }

    private func loaderRequiredView(for instance: LauncherInstance) -> some View {
        ContentUnavailableView {
            Label("需要模组加载器", systemImage: "puzzlepiece.extension")
        } description: {
            Text("“\(instance.name)” 是原版实例，安装模组前需要先安装 Fabric、Quilt、Forge 或 NeoForge。")
        } actions: {
            Button {
                isManagingLoader = true
            } label: {
                Label("安装加载器", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func modRow(_ mod: ModFile, instance: LauncherInstance) -> some View {
        HStack(spacing: 10) {
            Button {
                Task { await store.setMod(mod, enabled: !mod.isEnabled, for: instance) }
            } label: {
                Image(systemName: mod.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(mod.isEnabled ? .green : .secondary)
            }
            .buttonStyle(.plain)

            RemoteImageIconView(
                url: mod.iconURL,
                systemImage: "puzzlepiece.extension.fill",
                tint: .secondary,
                padding: 7
            )
            .frame(width: 36, height: 36)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(mod.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(mod.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive) {
                modPendingDeletion = mod
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func managedFileRow(
        _ file: ManagedContentFile,
        kind: ManagedContentKind,
        systemImage: String,
        instance: LauncherInstance
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(.green)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(file.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(file.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive) {
                Task { await store.removeManagedContent(file, kind: kind, for: instance) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func loadInstalled(for instance: LauncherInstance) async {
        switch selectedKind {
        case .mods:
            await store.loadMods(for: instance)
        case .resourcePacks:
            await store.loadManagedContent(.resourcePacks, for: instance)
        case .shaderPacks:
            await store.loadManagedContent(.shaderPacks, for: instance)
        }
    }

    private func importFiles(_ urls: [URL], for instance: LauncherInstance) async {
        switch selectedKind {
        case .mods:
            await store.importMods(urls, for: instance)
        case .resourcePacks:
            await store.importManagedContent(urls, kind: .resourcePacks, for: instance)
        case .shaderPacks:
            await store.importManagedContent(urls, kind: .shaderPacks, for: instance)
        }
    }
}

enum InstanceResourceKind: String, CaseIterable, Identifiable {
    case mods
    case shaderPacks
    case resourcePacks

    var id: Self { self }

    var title: String {
        switch self {
        case .mods: "模组"
        case .shaderPacks: "光影包"
        case .resourcePacks: "资源包"
        }
    }

    var systemImage: String {
        switch self {
        case .mods: "puzzlepiece.extension"
        case .shaderPacks: "sparkles"
        case .resourcePacks: "photo.stack"
        }
    }

    var modrinthKind: ModrinthContentKind {
        switch self {
        case .mods: .mods
        case .shaderPacks: .shaderPacks
        case .resourcePacks: .resourcePacks
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .mods:
            [UTType(filenameExtension: "jar") ?? .data]
        case .shaderPacks, .resourcePacks:
            [.zip, .folder]
        }
    }
}
