import SwiftUI

struct SettingsView: View {
    @Bindable var store: LauncherStore
    @AppStorage("defaultMemoryMB") private var defaultMemoryMB = 4096
    @AppStorage("showSnapshots") private var showSnapshots = true

    var body: some View {
        TabView {
            Form {
                Section("默认启动设置") {
                    Stepper("最大内存：\(defaultMemoryMB) MB", value: $defaultMemoryMB, in: 1024...32768, step: 512)
                    Toggle("显示快照版本", isOn: $showSnapshots)
                }
                Section("数据目录") {
                    LabeledContent("位置") {
                        Button("在访达中显示") { store.openApplicationSupport() }
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            Form {
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
        .frame(width: 620, height: 390)
    }
}
