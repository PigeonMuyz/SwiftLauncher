import SwiftUI
import UniformTypeIdentifiers

struct ResourcePacksView: View {
    @Bindable var store: LauncherStore
    @ViewState private var isImporting = false

    var body: some View {
        Group {
            if let instance = store.selectedInstance {
                contentView(for: instance)
            } else {
                ContentUnavailableView {
                    Label("未选择实例", systemImage: "shippingbox")
                } description: {
                    Text("请在侧边栏选择一个实例来管理资源包。")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.zip, .folder],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result, let instance = store.selectedInstance else { return }
            Task {
                await store.importManagedContent(urls, kind: .resourcePacks, for: instance)
            }
        }
        .task(id: store.selectedInstanceID) {
            guard let instance = store.selectedInstance else { return }
            await store.loadManagedContent(.resourcePacks, for: instance)
        }
    }

    @ViewBuilder
    private func contentView(for instance: LauncherInstance) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                instanceHeader(instance)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("已安装资源包")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Button {
                            isImporting = true
                        } label: {
                            Label("导入资源包", systemImage: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if store.resourcePacks[instance.id, default: []].isEmpty {
                        ContentUnavailableView {
                            Label("尚未导入资源包", systemImage: "photo.stack")
                        } description: {
                            Text("点击「导入资源包」来添加 ZIP 文件或文件夹。")
                        }
                        .padding(.vertical, 60)
                    } else {
                        LazyVStack(spacing: 8) {
                            ForEach(store.resourcePacks[instance.id, default: []]) { file in
                                fileRow(file: file, instance: instance, kind: .resourcePacks)
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
                Text("Minecraft \(instance.versionID)")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.bottom, 8)
    }

    private func fileRow(file: ManagedContentFile, instance: LauncherInstance, kind: ManagedContentKind) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(file.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text(file.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .destructive) {
                Task {
                    await store.removeManagedContent(file, kind: kind, for: instance)
                }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
