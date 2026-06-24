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
                                            Text("系统安装")
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
                                            do {
                                                try await store.deleteJavaRuntime(runtime)
                                            } catch {
                                                javaDeleteError = error
                                                showingJavaDeleteError = true
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
                    Button("重新扫描") { Task { await store.refreshEnvironment() } }
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
}
