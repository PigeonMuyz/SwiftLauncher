import SwiftUI
import UniformTypeIdentifiers

struct ModsView: View {
    @Bindable var store: LauncherStore
    @ViewState private var isImportingMods = false
    @ViewState private var modPendingDeletion: ModFile?
    @ViewState private var remoteSearch = ""
    @ViewState private var isShowingInstalled = false

    var body: some View {
        Group {
            if let instance = store.selectedInstance {
                if instance.loader == .vanilla {
                    ContentUnavailableView {
                        Label("原版实例不支持模组", systemImage: "cube.box")
                    } description: {
                        Text("请创建 Fabric、Quilt、Forge 或 NeoForge 实例来安装模组。")
                    }
                } else {
                    modsContent(for: instance)
                }
            } else {
                ContentUnavailableView {
                    Label("未选择实例", systemImage: "shippingbox")
                } description: {
                    Text("请在侧边栏选择一个实例来管理模组。")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let instance = store.selectedInstance, instance.loader != .vanilla {
                    Button {
                        isShowingInstalled = true
                    } label: {
                        Label(
                            "已安装 \(store.mods[instance.id, default: []].count)",
                            systemImage: "tray.full"
                        )
                    }
                    Button {
                        isImportingMods = true
                    } label: {
                        Label("导入 JAR", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
        .confirmationDialog(
            "移除模组「\(modPendingDeletion?.displayName ?? "")」？",
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
            isPresented: $isImportingMods,
            allowedContentTypes: [UTType(filenameExtension: "jar") ?? .data],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result, let instance = store.selectedInstance else { return }
            Task { await store.importMods(urls, for: instance) }
        }
        .task(id: store.selectedInstanceID) {
            guard let instance = store.selectedInstance else { return }
            await store.loadMods(for: instance)
        }
        .sheet(
            isPresented: Binding(
                get: { store.modInstallPlan?.kind == .mods && store.selectedInstance != nil },
                set: { if !$0 { store.modInstallPlan = nil } }
            )
        ) {
            if let instance = store.selectedInstance {
                ModrinthDetailsSheet(store: store, instance: instance)
            }
        }
        .popover(isPresented: $isShowingInstalled, arrowEdge: .top) {
            if let instance = store.selectedInstance {
                installedPopover(for: instance)
            }
        }
    }

    @ViewBuilder
    private func modsContent(for instance: LauncherInstance) -> some View {
        ModrinthRemoteSearchPanel(
            store: store,
            kind: .mods,
            instance: instance,
            query: $remoteSearch
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func installedPopover(for instance: LauncherInstance) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已安装模组")
                    .font(.headline)
                Spacer()
                Button {
                    isImportingMods = true
                } label: {
                    Label("导入", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            let mods = store.mods[instance.id, default: []]
            if mods.isEmpty {
                ContentUnavailableView {
                    Label("没有本地模组", systemImage: "cube.box")
                } description: {
                    Text("从资源列表安装，或导入本地 JAR 文件。")
                }
                .frame(width: 360, height: 220)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(mods) { mod in
                            modRow(mod: mod, instance: instance)
                        }
                    }
                }
                .frame(width: 460, height: 380)
            }
        }
        .padding(16)
    }

    private func modRow(mod: ModFile, instance: LauncherInstance) -> some View {
        HStack(spacing: 12) {
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
                padding: 8
            )
            .frame(width: 40, height: 40)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
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
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
