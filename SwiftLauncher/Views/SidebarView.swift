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

            // 底部：实例选择器（气泡样式）
            VStack(spacing: 0) {
                if let instance = store.selectedInstance {
                    Menu {
                        ForEach(store.instances) { inst in
                            Button {
                                store.selectedInstanceID = inst.id
                            } label: {
                                HStack {
                                    Image(systemName: inst.loader.systemImage)
                                    VStack(alignment: .leading) {
                                        Text(inst.name)
                                        Text(versionLine(for: inst))
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
                    } label: {
                        HStack(spacing: 10) {
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
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                } else {
                    Button {
                        store.presentNewInstance()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "shippingbox")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                            Text("选择实例")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 10)
                }

                // 下载任务指示器（可选）
                if let task = store.activeDownloads.first {
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
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
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
