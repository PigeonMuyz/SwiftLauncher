import SwiftUI

struct SettingsView: View {
    @Bindable var store: LauncherStore
    @AppStorage("defaultMemoryMB") private var defaultMemoryMB = 4096
    @AppStorage("showSnapshots") private var showSnapshots = true
    @AppStorage("autoDownloadJava") private var autoDownloadJava = true
    @AppStorage(DownloadEndpointResolver.defaultsKey) private var downloadSource = DownloadSource.automatic.rawValue
    @AppStorage(LauncherExperienceMode.defaultsKey) private var experienceMode = LauncherExperienceMode.beginner.rawValue
    @AppStorage(LauncherExperienceMode.autoDependenciesDefaultsKey) private var autoInstallRequiredMods = true

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
                            VStack(alignment: .leading, spacing: 3) {
                                Text(runtime.displayName)
                                Text("\(runtime.vendor) · \(runtime.path)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    Button("重新扫描") { Task { await store.refreshEnvironment() } }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Java", systemImage: "cup.and.heat.waves") }
        }
        .frame(width: 660, height: 480)
    }

    private var selectedDownloadSource: DownloadSource {
        DownloadSource(rawValue: downloadSource) ?? .automatic
    }

    private var selectedExperienceMode: LauncherExperienceMode {
        LauncherExperienceMode(rawValue: experienceMode) ?? .beginner
    }
}
