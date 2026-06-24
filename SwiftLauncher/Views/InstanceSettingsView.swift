import SwiftUI

struct InstanceSettingsView: View {
    @Bindable var store: LauncherStore
    let instanceID: UUID
    @Environment(\.dismiss) private var dismiss

    @ViewState private var editedInstance: LauncherInstance?
    @ViewState private var showingDeleteConfirmation = false
    @ViewState private var showingJavaPicker = false

    private var instance: LauncherInstance? {
        store.instances.first { $0.id == instanceID }
    }

    var body: some View {
        if let instance = editedInstance ?? instance {
            NavigationStack {
                Form {
                    basicInfoSection(instance)
                    javaSettingsSection(instance)
                    gameSettingsSection(instance)
                    dangerZoneSection(instance)
                }
                .formStyle(.grouped)
                .navigationTitle("实例设置")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            saveChanges(instance)
                        }
                        .disabled(editedInstance == nil)
                    }
                }
            }
            .frame(width: 600, height: 550)
            .alert("删除实例", isPresented: $showingDeleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    deleteInstance(instance)
                }
            } message: {
                Text("确定要删除实例「\(instance.name)」吗？这将删除所有游戏数据和配置。")
            }
        } else {
            ContentUnavailableView {
                Label("实例不存在", systemImage: "exclamationmark.triangle")
            } description: {
                Text("无法找到要编辑的实例。")
            }
        }
    }

    @ViewBuilder
    private func basicInfoSection(_ instance: LauncherInstance) -> some View {
        Section("基本信息") {
            HStack {
                Text("实例名称")
                Spacer()
                TextField("名称", text: binding(for: instance, keyPath: \.name))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 200)
            }

            LabeledContent("Minecraft 版本") {
                Text(instance.versionID)
                    .foregroundStyle(.secondary)
            }

            LabeledContent("模组加载器") {
                Text(instance.loader.title)
                    .foregroundStyle(.secondary)
            }

            if let version = instance.loaderVersion {
                LabeledContent("加载器版本") {
                    Text(version)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("创建时间") {
                Text(instance.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func javaSettingsSection(_ instance: LauncherInstance) -> some View {
        Section("Java 设置") {
            Toggle("自动选择 Java", isOn: binding(for: instance, keyPath: \.usesAutomaticJava))

            if !instance.usesAutomaticJava {
                Picker("Java 路径", selection: binding(for: instance, keyPath: \.javaPath)) {
                    Text("未选择").tag(nil as String?)
                    ForEach(store.javaRuntimes) { runtime in
                        Text(runtime.displayName).tag(runtime.path as String?)
                    }
                }
            }

            HStack {
                Text("最大内存")
                Spacer()
                Stepper(
                    "\(instance.memoryMB) MB",
                    value: binding(for: instance, keyPath: \.memoryMB),
                    in: 1024...32768,
                    step: 512
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("JVM 参数")
                    .font(.subheadline)
                TextEditor(text: jvmArgumentsBinding(for: instance))
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 60)
                    .border(Color.secondary.opacity(0.2))
                Text("每行一个参数，例如：-XX:+UseG1GC")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func gameSettingsSection(_ instance: LauncherInstance) -> some View {
        Section("游戏设置") {
            Toggle("版本隔离", isOn: binding(for: instance, keyPath: \.isVersionIsolated))

            Text("启用后，此实例的游戏数据（存档、资源包等）将独立存储，不与其他实例共享。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text("窗口宽度")
                Spacer()
                TextField("默认", value: binding(for: instance, keyPath: \.resolutionWidth), format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                Text("px")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("窗口高度")
                Spacer()
                TextField("默认", value: binding(for: instance, keyPath: \.resolutionHeight), format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                Text("px")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func dangerZoneSection(_ instance: LauncherInstance) -> some View {
        Section {
            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                Label("删除实例", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }

            Button {
                openGameDirectory(instance)
            } label: {
                Label("打开游戏目录", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
        } header: {
            Text("危险操作")
        } footer: {
            Text("删除实例将永久删除所有相关数据，此操作无法撤销。")
                .foregroundStyle(.red)
        }
    }

    private func binding<T>(for instance: LauncherInstance, keyPath: WritableKeyPath<LauncherInstance, T>) -> Binding<T> {
        Binding(
            get: {
                if let edited = editedInstance {
                    return edited[keyPath: keyPath]
                }
                return instance[keyPath: keyPath]
            },
            set: { newValue in
                var updated = editedInstance ?? instance
                updated[keyPath: keyPath] = newValue
                editedInstance = updated
            }
        )
    }

    private func jvmArgumentsBinding(for instance: LauncherInstance) -> Binding<String> {
        Binding(
            get: {
                let args = editedInstance?.additionalJVMArguments ?? instance.additionalJVMArguments
                return args.joined(separator: "\n")
            },
            set: { newValue in
                var updated = editedInstance ?? instance
                updated.additionalJVMArguments = newValue
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                editedInstance = updated
            }
        )
    }

    private func saveChanges(_ instance: LauncherInstance) {
        guard let edited = editedInstance else { return }

        if let index = store.instances.firstIndex(where: { $0.id == instance.id }) {
            store.instances[index] = edited
            Task {
                await store.saveInstances()
            }
        }
        dismiss()
    }

    private func deleteInstance(_ instance: LauncherInstance) {
        store.instances.removeAll { $0.id == instance.id }

        // 删除实例目录
        let instanceDir = store.fileSystem.instanceRoot(instance.id)
        try? FileManager.default.removeItem(at: instanceDir)

        Task {
            await store.saveInstances()
        }

        dismiss()
    }

    private func openGameDirectory(_ instance: LauncherInstance) {
        store.openGameDirectory(instance)
    }
}
