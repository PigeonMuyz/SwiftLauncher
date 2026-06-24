import SwiftUI

struct SidebarView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(spacing: 0) {
            // 上半部分：固定导航 + 动态资源管理
            List(selection: $store.selection) {
                Label(AppSection.home.title, systemImage: AppSection.home.systemImage)
                    .tag(AppSection.home)
                Label(AppSection.downloads.title, systemImage: AppSection.downloads.systemImage)
                    .tag(AppSection.downloads)
                Label(AppSection.accounts.title, systemImage: AppSection.accounts.systemImage)
                    .tag(AppSection.accounts)
                Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage)
                    .tag(AppSection.settings)

                if let instance = store.selectedInstance {
                    Section {
                        // 模组管理（仅非原版）
                        if instance.loader != .vanilla {
                            Label(AppSection.mods.title, systemImage: AppSection.mods.systemImage)
                                .tag(AppSection.mods)
                        }

                        // 资源包（所有实例）
                        Label(AppSection.resourcePacks.title, systemImage: AppSection.resourcePacks.systemImage)
                            .tag(AppSection.resourcePacks)

                        // 光影包（仅支持光影的实例）
                        let instanceMods = store.mods[instance.id] ?? []
                        let hasShaders = instance.hasShaderSupport(mods: instanceMods)

                        if hasShaders {
                            Label(AppSection.shaders.title, systemImage: AppSection.shaders.systemImage)
                                .tag(AppSection.shaders)
                        }
                    } header: {
                        Text("当前实例")
                            .font(.caption2)
                    }
                    .task(id: instance.id) {
                        // 确保加载模组数据
                        await store.loadMods(for: instance)
                    }
                }
            }
            .listStyle(.sidebar)

            // 底部：实例选择器
            VStack(spacing: 0) {
                Divider()

                Button {
                    // 触发实例选择菜单
                } label: {
                    HStack(spacing: 10) {
                        if let instance = store.selectedInstance {
                            InstanceIconView(store: store, instance: instance, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(instance.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(versionLine(for: instance))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        } else {
                            Image(systemName: "shippingbox")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("选择实例")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color(nsColor: .controlBackgroundColor))
                .contextMenu {
                    ForEach(store.instances) { instance in
                        Button {
                            store.selectedInstanceID = instance.id
                        } label: {
                            HStack {
                                Image(systemName: instance.loader.systemImage)
                                VStack(alignment: .leading) {
                                    Text(instance.name)
                                    Text(versionLine(for: instance))
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    if !store.instances.isEmpty {
                        Divider()
                    }

                    Button {
                        store.presentNewInstance()
                    } label: {
                        Label("新建实例...", systemImage: "plus.circle")
                    }
                }

                // 下载任务指示器（可选）
                if let task = store.activeDownloads.first {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("下载任务")
                                .font(.caption2.weight(.semibold))
                            Spacer()
                            Text("\(store.activeDownloads.count)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(task.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        ProgressView(value: task.progress)
                            .controlSize(.small)
                            .tint(.green)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))
                }
            }
        }
        .navigationTitle("")
    }

    private func versionLine(for instance: LauncherInstance) -> String {
        let loader = instance.loader == .vanilla ? "原版" : instance.loader.title
        return "MC \(instance.versionID) · \(loader)"
    }
}

private extension ModLoader {
    var systemImage: String {
        switch self {
        case .vanilla: return "cube"
        case .fabric: return "cube.box"
        case .quilt: return "cube.box.fill"
        case .forge: return "hammer"
        case .neoForge: return "hammer.fill"
        }
    }
}
