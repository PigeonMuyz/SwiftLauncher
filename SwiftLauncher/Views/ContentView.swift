import SwiftUI

struct ContentView: View {
    @Bindable var store: LauncherStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @ViewBuilder
    var body: some View {
        if #available(macOS 15.0, *) {
            rootContent
                .toolbar(removing: .title)
        } else {
            rootContent
        }
    }

    private var rootContent: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            detailContainer
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
    }

    @ViewBuilder
    private var detailContainer: some View {
        if store.selection == .home {
            ZStack(alignment: .topTrailing) {
                HomeView(store: store)
                topActions
                    .padding(.top, 18)
                    .padding(.trailing, 22)
            }
        } else {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(store.selection.title)
                        .font(.title2.weight(.semibold))
                    Spacer()

                    if store.selection == .instances {
                        Button {
                            store.isPresentingNewInstance = true
                        } label: {
                            Label("添加实例", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        store.loadLog()
                        openWindow(id: "logs")
                    } label: {
                        Label("游戏日志", systemImage: "terminal")
                    }

                    topActions
                }
                .padding(.horizontal, 22)
                .frame(height: 62)

                Divider()
                selectedDetail
            }
        }
    }

    @ViewBuilder
    private var selectedDetail: some View {
        switch store.selection {
        case .home:
            HomeView(store: store)
        case .instances:
            InstancesView(store: store)
        case .downloads:
            DownloadsView(store: store)
        case .accounts:
            AccountsView(store: store)
        }
    }

    private var topActions: some View {
        HStack(spacing: 10) {
            Button {
                store.selection = .accounts
            } label: {
                Label("账户", systemImage: "person.crop.circle")
            }
            .help("账户")

            Button {
                Task { await store.refreshEnvironment() }
            } label: {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(store.isRefreshing)
            .help("刷新官方数据")

            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }
            .help("设置")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(LauncherCircleButtonStyle())
    }
}

private struct LauncherCircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .medium))
            .frame(width: 38, height: 38)
            .background(.ultraThinMaterial, in: Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(configuration.isPressed ? 0.28 : 0.14), lineWidth: 0.5)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
    }
}
