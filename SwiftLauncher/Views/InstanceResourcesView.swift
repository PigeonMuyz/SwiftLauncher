import SwiftUI
import UniformTypeIdentifiers

struct InstanceResourcesView: View {
    @Bindable var store: LauncherStore

    @ViewState private var selectedKind: InstanceResourceKind = .mods
    @ViewState private var isImporting = false
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
    }

    private func content(for instance: LauncherInstance) -> some View {
        TabView(selection: $selectedKind) {
            ForEach(InstanceResourceKind.allCases) { kind in
                installedPane(for: instance, kind: kind)
                    .tabItem {
                        Text(kind.title)
                    }
                    .tag(kind)
            }
        }
        .task(id: "\(instance.id)-\(selectedKind.id)") {
            await loadInstalled(for: instance)
        }
    }

    private func installedPane(for instance: LauncherInstance, kind: InstanceResourceKind) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label("已安装\(kind.title)", systemImage: kind.systemImage)
                    .font(.headline)
                Spacer()
                Button {
                    isImporting = true
                } label: {
                    Label("导入", systemImage: "square.and.arrow.down")
                }
                .disabled(kind == .mods && instance.loader == .vanilla)
            }
            .padding(14)

            Divider()

            installedList(for: instance, kind: kind)
        }
    }

    @ViewBuilder
    private func installedList(for instance: LauncherInstance, kind: InstanceResourceKind) -> some View {
        switch kind {
        case .mods:
            let mods = store.mods[instance.id, default: []]
            if mods.isEmpty {
                emptyInstalledView("尚未导入模组", systemImage: kind.systemImage)
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
                systemImage: kind.systemImage,
                emptyTitle: "尚未导入资源包",
                instance: instance
            )
        case .shaderPacks:
            managedContentList(
                files: store.shaderPacks[instance.id, default: []],
                kind: .shaderPacks,
                systemImage: kind.systemImage,
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
            Text("可以导入本地文件，或到“资源库”中搜索并安装。")
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
