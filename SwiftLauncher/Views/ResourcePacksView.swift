import SwiftUI
import UniformTypeIdentifiers

struct ResourcePacksView: View {
    @Bindable var store: LauncherStore
    @ViewState private var isImporting = false
    @ViewState private var remoteSearch = ""
    @ViewState private var isShowingInstalled = false

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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let instance = store.selectedInstance {
                    Button {
                        isShowingInstalled = true
                    } label: {
                        Label(
                            "已安装 \(store.resourcePacks[instance.id, default: []].count)",
                            systemImage: "tray.full"
                        )
                    }
                    Button {
                        isImporting = true
                    } label: {
                        Label("导入资源包", systemImage: "square.and.arrow.down")
                    }
                }
            }
        }
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
        .sheet(
            isPresented: Binding(
                get: { store.modInstallPlan?.kind == .resourcePacks && store.selectedInstance != nil },
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
    private func contentView(for instance: LauncherInstance) -> some View {
        ModrinthRemoteSearchPanel(
            store: store,
            kind: .resourcePacks,
            instance: instance,
            query: $remoteSearch
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func installedPopover(for instance: LauncherInstance) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("已安装资源包")
                    .font(.headline)
                Spacer()
                Button {
                    isImporting = true
                } label: {
                    Label("导入", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }

            let files = store.resourcePacks[instance.id, default: []]
            if files.isEmpty {
                ContentUnavailableView {
                    Label("没有本地资源包", systemImage: "photo.stack")
                } description: {
                    Text("从资源列表安装，或导入 ZIP 文件和文件夹。")
                }
                .frame(width: 360, height: 220)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(files) { file in
                            fileRow(file: file, instance: instance, kind: .resourcePacks)
                        }
                    }
                }
                .frame(width: 420, height: 360)
            }
        }
        .padding(16)
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
