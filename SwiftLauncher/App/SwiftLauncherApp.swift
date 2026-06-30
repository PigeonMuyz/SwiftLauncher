import SwiftUI
import AppKit

@main
struct SwiftLauncherApp: App {
    @ViewState private var store = LauncherStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("SwiftLauncher", id: "main") {
            ContentView(store: store)
                .task {
                    await store.bootstrap()
                }
                .frame(minWidth: 1000, minHeight: 700)
                .onAppear {
                    centerMainWindow()
                }
        }
        .defaultSize(width: 1280, height: 820)
        .commands {
            SidebarCommands()

            CommandMenu("启动器") {
                Button("刷新真实数据") {
                    Task { await store.refreshEnvironment() }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("新建游戏实例") {
                    store.presentNewInstance()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Divider()

                Button("启动选中实例") {
                    Task { await store.launchSelectedInstance() }
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(store.selectedInstance.map { store.isWorking(on: $0) } ?? true)
            }
        }

        Window("游戏日志", id: "logs") {
            LogView(store: store)
                .frame(minWidth: 760, minHeight: 480)
        }

        Window("启动游戏", id: "game-loading") {
            if let instance = store.gameLoadingInstance {
                GameLoadingView(
                    store: store,
                    instance: instance,
                    loadProgress: store.gameLoadProgress
                )
                .background(LoadingWindowChromeView())
            } else {
                ProgressView("正在准备游戏启动…")
                    .frame(width: 320, height: 160)
                    .background(LoadingWindowChromeView())
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultPosition(.center)
        .defaultSize(width: 320, height: 160)

        Settings {
            SettingsView(store: store)
        }
    }

    private func centerMainWindow() {
        if let window = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.center()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 居中主窗口
        if let window = NSApplication.shared.windows.first {
            window.center()
        }
    }
}
