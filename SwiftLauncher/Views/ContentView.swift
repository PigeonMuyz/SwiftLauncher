import SwiftUI

struct ContentView: View {
    @Bindable var store: LauncherStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @ViewState private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        rootContent
    }

    private var rootContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } detail: {
            detailContainer
                .frame(minWidth: 700)
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .tint(Color(red: 0.62, green: 0.76, blue: 0.36))
        .sheet(isPresented: $store.isPresentingNewInstance) {
            NewInstanceSheet(store: store)
        }
        .alert(
            "SwiftLauncher",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: {
                    if !$0 {
                        store.errorMessage = nil
                        store.errorHelpURL = nil
                    }
                }
            )
        ) {
            if let helpURL = store.errorHelpURL {
                Button("打开官方登记表") {
                    openURL(helpURL)
                    store.errorMessage = nil
                    store.errorHelpURL = nil
                }
            }
            Button("好") {
                store.errorMessage = nil
                store.errorHelpURL = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .onChange(of: store.shouldOpenGameLog) { _, shouldOpen in
            guard shouldOpen else { return }
            store.loadLog()
            openWindow(id: "logs")
            store.shouldOpenGameLog = false
        }
        .overlay {
            if store.showGameLoadingOverlay, let instance = store.selectedInstance {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    GameLoadingView(
                        store: store,
                        instance: instance,
                        loadProgress: store.gameLoadProgress
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var detailContainer: some View {
        selectedDetail
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle(store.selection.title)
    }

    @ViewBuilder
    private var selectedDetail: some View {
        switch store.selection {
        case .mods:
            ModsView(store: store)
        case .resourcePacks:
            ResourcePacksView(store: store)
        case .shaders:
            ShadersView(store: store)
        case .downloads:
            DownloadsView(store: store)
        case .settings:
            SettingsView(store: store)
        }
    }

}
