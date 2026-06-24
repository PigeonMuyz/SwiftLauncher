import SwiftUI

struct SettingsView: View {
    @Bindable var store: LauncherStore
    @AppStorage("defaultMemoryMB") private var defaultMemoryMB = 4096
    @AppStorage("showSnapshots") private var showSnapshots = true
    @AppStorage("autoDownloadJava") private var autoDownloadJava = true
    @AppStorage(DownloadEndpointResolver.defaultsKey) private var downloadSource = DownloadSource.automatic.rawValue
    @AppStorage(LauncherExperienceMode.defaultsKey) private var experienceMode = LauncherExperienceMode.beginner.rawValue
    @AppStorage(LauncherExperienceMode.autoDependenciesDefaultsKey) private var autoInstallRequiredMods = true
    @AppStorage("instanceDisplayTemplate") private var instanceDisplayTemplate = "${mc_version} · ${mod_loader}"

    private static let defaultTemplate = "${mc_version} · ${mod_loader}"

    @ViewState private var javaDeleteError: Error?
    @ViewState private var showingJavaDeleteError = false
    @ViewState private var javaToDelete: JavaRuntime?
    @ViewState private var showingJavaDeleteConfirm = false
    @ViewState private var selectedTargetJava: JavaRuntime?
    @ViewState private var availableTargetJavas: [JavaRuntime] = []
    @ViewState private var showingAddJava = false
    @ViewState private var selectedJavaMajorVersion = 21

    private let availableJavaVersions = [25, 21, 17, 11, 8]

    var body: some View {
        TabView {
            Form {
                Section("使用模式") {
                    Picker("启动器模式", selection: $experienceMode) {
                        ForEach(LauncherExperienceMode.allCases) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    Text(selectedExperienceMode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if selectedExperienceMode == .normal {
                        Toggle("下载 Mod 时自动补全必需前置", isOn: $autoInstallRequiredMods)
                    }
                }
                Section("默认启动设置") {
                    Stepper("最大内存：\(defaultMemoryMB) MB", value: $defaultMemoryMB, in: 1024...32768, step: 512)
                    Toggle("显示快照版本", isOn: $showSnapshots)
                }
                Section("实例显示格式") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("自定义实例信息显示格式")
                            .font(.subheadline.weight(.medium))
                        Text("可用变量：${mc_version} MC版本号 · ${mod_loader} 模组加载器 · ${mod_num} 模组数量")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack {
                            TextField("显示模板", text: $instanceDisplayTemplate)
                                .textFieldStyle(.roundedBorder)

                            Button("恢复默认") {
                                instanceDisplayTemplate = Self.defaultTemplate
                            }
                            .buttonStyle(.borderless)
                        }

                        Text("示例：\(formatExample())")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 4)
                }
                Section("数据目录") {
                    LabeledContent("位置") {
                        Button("在访达中显示") { store.openApplicationSupport() }
                    }
                }
                Section("下载源") {
                    Picker("Minecraft 下载源", selection: $downloadSource) {
                        ForEach(DownloadSource.allCases) { source in
                            Text(source.title).tag(source.rawValue)
                        }
                    }
                    Text(selectedDownloadSource.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("无论使用哪个下载源，启动器都会按 Mojang 或上游提供的哈希校验文件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            Form {
                Section("自动管理") {
                    Toggle("自动下载缺失的推荐 Java", isOn: $autoDownloadJava)
                    Text("启动器优先匹配 Mojang 元数据指定的 Java 主版本，并将托管运行时保存在应用数据目录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("已检测到的 Java") {
                    if store.javaRuntimes.isEmpty {
                        Text("未检测到 Java 运行时")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.javaRuntimes) { runtime in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 8) {
                                        Text(runtime.displayName)
                                            .font(.headline)

                                        let usingInstances = store.instancesUsing(javaRuntime: runtime)
                                        if !usingInstances.isEmpty {
                                            Text("正在使用: \(usingInstances.count)个实例")
                                                .font(.caption)
                                                .foregroundStyle(.green)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.green.opacity(0.15), in: Capsule())
                                        }

                                        if runtime == store.javaRuntimes.first {
                                            Text("推荐")
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(.blue)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.blue.opacity(0.15), in: Capsule())
                                        }

                                        if !store.isManagedJava(runtime) {
                                            Text("系统")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(.secondary.opacity(0.1), in: Capsule())
                                        }
                                    }

                                    Text("\(runtime.vendor) · \(runtime.path)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                if store.isManagedJava(runtime) {
                                    Button(role: .destructive) {
                                        Task {
                                            let usingInstances = store.instancesUsing(javaRuntime: runtime)
                                            if usingInstances.isEmpty {
                                                // 没有实例使用，直接删除
                                                do {
                                                    try await store.deleteJavaRuntime(runtime)
                                                } catch {
                                                    javaDeleteError = error
                                                    showingJavaDeleteError = true
                                                }
                                            } else {
                                                // 有实例使用，准备选择目标 Java
                                                let higherVersions = store.javaRuntimes.filter { $0.majorVersion > runtime.majorVersion }
                                                if higherVersions.isEmpty {
                                                    javaDeleteError = LauncherError.invalidOperation(
                                                        "以下实例正在使用此 Java：\(usingInstances.map { $0.name }.joined(separator: "、"))\n\n没有更高版本的 Java 可供切换。"
                                                    )
                                                    showingJavaDeleteError = true
                                                } else {
                                                    javaToDelete = runtime
                                                    availableTargetJavas = higherVersions
                                                    selectedTargetJava = higherVersions.first
                                                    showingJavaDeleteConfirm = true
                                                }
                                            }
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                    }
                                    .buttonStyle(.borderless)
                                    .help("删除此 Java 运行时")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    HStack {
                        Button("重新扫描") { Task { await store.refreshEnvironment() } }
                        Spacer()
                        Button("添加 Java...") {
                            showingAddJava = true
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Java", systemImage: "cup.and.heat.waves") }
        }
        .frame(width: 660, height: 480)
        .alert("删除失败", isPresented: $showingJavaDeleteError, presenting: javaDeleteError) { _ in
            Button("确定", role: .cancel) {}
        } message: { error in
            Text(error.localizedDescription)
        }
        .alert("确认删除", isPresented: $showingJavaDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认删除并迁移", role: .destructive) {
                guard let runtime = javaToDelete, let target = selectedTargetJava else { return }
                Task {
                    do {
                        try await store.deleteJavaRuntime(runtime, migrateTo: target)
                    } catch {
                        javaDeleteError = error
                        showingJavaDeleteError = true
                    }
                }
            }
        } message: {
            if let runtime = javaToDelete {
                let usingInstances = store.instancesUsing(javaRuntime: runtime)
                VStack(alignment: .leading, spacing: 8) {
                    Text("以下实例正在使用此 Java：\(usingInstances.map { $0.name }.joined(separator: "、"))")

                    if !availableTargetJavas.isEmpty {
                        Text("请选择要迁移到的 Java 版本：")
                            .font(.headline)
                            .padding(.top, 4)

                        Picker("目标 Java", selection: $selectedTargetJava) {
                            ForEach(availableTargetJavas) { java in
                                Text("Java \(java.majorVersion) · \(java.vendor)").tag(java as JavaRuntime?)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddJava) {
            NavigationStack {
                Form {
                    Section {
                        Picker("Java 版本", selection: $selectedJavaMajorVersion) {
                            ForEach(availableJavaVersions, id: \.self) { version in
                                Text("Java \(version)").tag(version)
                            }
                        }
                        .pickerStyle(.menu)

                        Text("将从 Adoptium 下载并安装 Eclipse Temurin JRE。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("添加 Java")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            showingAddJava = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("下载并安装") {
                            installJava(version: selectedJavaMajorVersion)
                            showingAddJava = false
                        }
                    }
                }
            }
            .frame(width: 400, height: 180)
        }
    }

    private var selectedDownloadSource: DownloadSource {
        DownloadSource(rawValue: downloadSource) ?? .automatic
    }

    private var selectedExperienceMode: LauncherExperienceMode {
        LauncherExperienceMode(rawValue: experienceMode) ?? .beginner
    }

    private func formatExample() -> String {
        instanceDisplayTemplate
            .replacingOccurrences(of: "${mc_version}", with: "1.20.1")
            .replacingOccurrences(of: "${mod_loader}", with: "Fabric")
            .replacingOccurrences(of: "${mod_num}", with: "42")
    }

    private func installJava(version: Int) {
        Task {
            do {
                _ = try await store.installJavaRuntime(majorVersion: version) { _, _ in }
            } catch {
                javaDeleteError = error
                showingJavaDeleteError = true
            }
        }
    }
}
