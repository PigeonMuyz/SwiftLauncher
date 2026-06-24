import SwiftUI
import UniformTypeIdentifiers

struct ModsView: View {
    @Bindable var store: LauncherStore
    @ViewState private var isImportingMods = false
    @ViewState private var modPendingDeletion: ModFile?

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
    }

    @ViewBuilder
    private func modsContent(for instance: LauncherInstance) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                instanceHeader(instance)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("已安装模组")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Button {
                            isImportingMods = true
                        } label: {
                            Label("导入模组 JAR", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if instance.loader == .fabric {
                        Text("Fabric Loader \(instance.loaderVersion ?? "") 已安装；Fabric API 是独立模组，可在下载页面安装。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 12)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
                    }

                    if store.mods[instance.id, default: []].isEmpty {
                        ContentUnavailableView {
                            Label("尚未导入模组", systemImage: "cube.box")
                        } description: {
                            Text("点击「导入模组 JAR」来添加本地模组文件。")
                        }
                        .padding(.vertical, 60)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(store.mods[instance.id, default: []]) { mod in
                                modRow(mod: mod, instance: instance)
                            }
                        }
                    }
                }
            }
            .padding(26)
        }
    }

    private func instanceHeader(_ instance: LauncherInstance) -> some View {
        HStack(spacing: 14) {
            InstanceIconView(store: store, instance: instance, size: 54)
            VStack(alignment: .leading, spacing: 3) {
                Text(instance.name)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)
                Text("Minecraft \(instance.versionID) · \(instance.loader.title)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.bottom, 8)
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

            AsyncImage(url: mod.iconURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "puzzlepiece.extension.fill")
                        .foregroundStyle(.secondary)
                }
            }
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
