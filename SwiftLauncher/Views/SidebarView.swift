import SwiftUI

struct SidebarView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(spacing: 0) {
            // 上半部分：固定导航
            List(selection: $store.selection) {
                Label(AppSection.home.title, systemImage: AppSection.home.systemImage)
                    .tag(AppSection.home)
                Label(AppSection.downloads.title, systemImage: AppSection.downloads.systemImage)
                    .tag(AppSection.downloads)
                Label(AppSection.accounts.title, systemImage: AppSection.accounts.systemImage)
                    .tag(AppSection.accounts)
                Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage)
                    .tag(AppSection.settings)
            }
            .listStyle(.sidebar)

            Divider()

            // 下半部分：实例上下文
            InstanceContextView(store: store)
        }
        .navigationTitle("")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if let task = store.activeDownloads.first {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("下载任务")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(store.activeDownloads.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(task.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        ProgressView(value: task.progress)
                            .tint(.green)
                    }
                }

                HStack(spacing: 7) {
                    Circle()
                        .fill(store.manifest == nil ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(
                        store.manifest == nil
                            ? "等待版本数据"
                            : "下载源：\(DownloadEndpointResolver.selectedSource.title)"
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }
}

private struct InstanceContextView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前实例")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            // 实例选择 Picker
            Picker("", selection: $store.selectedInstanceID) {
                ForEach(store.instances) { instance in
                    HStack {
                        Image(systemName: instance.loader.systemImage)
                        Text(instance.name)
                    }
                    .tag(Optional(instance.id))
                }

                if !store.instances.isEmpty {
                    Divider()
                }

                Label("新建实例...", systemImage: "plus.circle")
                    .tag(UUID?.none)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .padding(.horizontal, 8)
            .onChange(of: store.selectedInstanceID) { oldValue, newValue in
                if newValue == nil {
                    store.presentNewInstance()
                    store.selectedInstanceID = oldValue
                }
            }

            // 动态资源管理区
            if let instance = store.selectedInstance {
                VStack(alignment: .leading, spacing: 0) {
                    // 模组管理（仅非原版）
                    if instance.loader != .vanilla {
                        NavigationLink(value: AppSection.mods) {
                            Label("模组管理", systemImage: "cube.box")
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }

                    // 资源包（所有实例）
                    NavigationLink(value: AppSection.resourcePacks) {
                        Label("资源包", systemImage: "photo.stack")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)

                    // 光影包（仅支持光影的实例）
                    if instance.hasShaderSupport(mods: store.mods[instance.id] ?? []) {
                        NavigationLink(value: AppSection.shaders) {
                            Label("光影包", systemImage: "sparkles")
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                    }
                }
                .font(.callout)
            } else {
                Text("未选择实例")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 12)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
