import SwiftUI

@main
struct SwiftLauncherApp: App {
    @ViewState private var store = LauncherStore()

    var body: some Scene {
        WindowGroup("SwiftLauncher", id: "main") {
            ContentView(store: store)
                .task {
                    await store.bootstrap()
                }
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1180, height: 780)
        .commands {
            SidebarCommands()

            CommandMenu("启动器") {
                Button("刷新真实数据") {
                    Task { await store.refreshEnvironment() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("新建游戏实例") {
                    store.isPresentingNewInstance = true
                }
                .keyboardShortcut("n", modifiers: [.command])

                Divider()

                Button("启动选中实例") {
                    Task { await store.launchSelectedInstance() }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(store.selectedInstance == nil || store.isBusy)
            }
        }

        Window("游戏日志", id: "logs") {
            LogView(store: store)
                .frame(minWidth: 760, minHeight: 480)
        }

        Settings {
            SettingsView(store: store)
        }
    }
}
