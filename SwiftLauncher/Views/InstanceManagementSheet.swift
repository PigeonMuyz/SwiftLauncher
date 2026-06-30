import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InstanceManagementSheet: View {
    @Bindable var store: LauncherStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var selectedIDs: Set<UUID> = []
    @ViewState private var isConfirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .confirmationDialog(
            "删除所选实例？",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("删除 \(selectedInstances.count) 个实例", role: .destructive) {
                Task { await deleteSelectedInstances() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("实例目录也会被删除。此操作无法撤销。")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.title2)
                .foregroundStyle(.green)
                .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 4) {
                Text("管理实例")
                    .font(.title2.weight(.semibold))
                Text("批量选择实例进行删除，或从这里新建和导入。")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("完成") { dismiss() }
        }
        .padding(22)
    }

    private var content: some View {
        Group {
            if store.instances.isEmpty {
                ContentUnavailableView {
                    Label("还没有实例", systemImage: "shippingbox")
                } description: {
                    Text("新建或导入实例后会出现在这里。")
                } actions: {
                    Button("新建实例") {
                        dismiss()
                        store.presentNewInstance()
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.instances) { instance in
                            InstanceManagementRow(
                                store: store,
                                instance: instance,
                                isSelected: binding(for: instance.id)
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("全选") {
                selectedIDs = Set(store.instances.map(\.id))
            }
            .disabled(store.instances.isEmpty)

            Button("清空") {
                selectedIDs.removeAll()
            }
            .disabled(selectedIDs.isEmpty)

            Spacer()

            Button {
                dismiss()
                store.presentNewInstance()
            } label: {
                Label("新建", systemImage: "plus")
            }

            Button {
                openModpackImporter()
            } label: {
                Label("导入整合包", systemImage: "archivebox")
            }

            Button {
                openMinecraftFolderImporter()
            } label: {
                Label("导入 .minecraft", systemImage: "folder.badge.plus")
            }

            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("删除所选", systemImage: "trash")
            }
            .disabled(selectedIDs.isEmpty)
        }
        .padding(16)
    }

    private var selectedInstances: [LauncherInstance] {
        store.instances.filter { selectedIDs.contains($0.id) }
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding {
            selectedIDs.contains(id)
        } set: { isSelected in
            if isSelected {
                selectedIDs.insert(id)
            } else {
                selectedIDs.remove(id)
            }
        }
    }

    private func deleteSelectedInstances() async {
        let instances = selectedInstances
        selectedIDs.removeAll()
        for instance in instances {
            await store.deleteInstance(instance)
        }
    }

    private func openModpackImporter() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "mrpack") ?? .zip, .zip]
        panel.message = "选择 Modrinth 整合包文件 (.mrpack 或 .zip)"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await store.importModpack(from: url) }
        }
    }

    private func openMinecraftFolderImporter() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "选择 .minecraft 文件夹"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await store.importMinecraftFolder(from: url) }
        }
    }
}

private struct InstanceManagementRow: View {
    let store: LauncherStore
    let instance: LauncherInstance
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isSelected)
                .labelsHidden()
            InstanceIconView(store: store, instance: instance, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(instance.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("MC \(instance.versionID) · \(instance.loader.title) · \(store.installationStatus(for: instance))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if store.selectedInstanceID == instance.id {
                Text("当前")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
            Button {
                store.selectedInstanceID = instance.id
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .buttonStyle(.borderless)
            .help("设为当前实例")
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
