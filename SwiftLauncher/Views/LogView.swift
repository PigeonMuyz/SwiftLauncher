import SwiftUI

struct LogView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            Text(store.logText)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(14)
        }
        .toolbar {
            ToolbarItemGroup {
                Button("刷新") { store.loadLog() }
                if store.gameProcessID != nil {
                    Button("停止游戏", role: .destructive) {
                        Task { await store.terminateGame() }
                    }
                }
            }
        }
    }
}
