import SwiftUI

struct ContentView: View {
    @Bindable var store: LauncherStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openURL) private var openURL
    @AppStorage(LauncherAppearancePreference.accentColorDefaultsKey) private var accentColor = LauncherAccentColor.green.rawValue
    @ViewState private var columnVisibility: NavigationSplitViewVisibility = .all

    private var selectedAccentColor: LauncherAccentColor {
        LauncherAccentColor(rawValue: accentColor) ?? .green
    }

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
        .tint(selectedAccentColor.color)
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
        .onChange(of: store.showGameLoadingOverlay) { _, shouldShow in
            if shouldShow {
                openWindow(id: "game-loading")
            } else {
                dismissWindow(id: "game-loading")
            }
        }
    }

    @ViewBuilder
    private var detailContainer: some View {
        selectedDetail
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle(navigationTitle)
    }

    private var navigationTitle: String {
        switch store.selection {
        case .downloadVersions, .instanceResources:
            ""
        default:
            store.selection.title
        }
    }

    @ViewBuilder
    private var selectedDetail: some View {
        switch store.selection {
        case .downloadVersions:
            DownloadsView(store: store, section: .games)
        case .downloadTasks:
            DownloadsView(store: store, section: .tasks)
        case .libraryMods:
            ResourceLibraryView(store: store, kind: .mods)
        case .libraryShaders:
            ResourceLibraryView(store: store, kind: .shaders)
        case .libraryResourcePacks:
            ResourceLibraryView(store: store, kind: .resourcePacks)
        case .libraryDataPacks:
            ResourceLibraryView(store: store, kind: .dataPacks)
        case .libraryModpacks:
            ResourceLibraryView(store: store, kind: .modpacks)
        case .instanceResources:
            InstanceResourcesView(store: store)
        case .instanceSettings:
            CurrentInstanceSettingsView(store: store)
        case .settings:
            SettingsView(store: store)
        }
    }

}
