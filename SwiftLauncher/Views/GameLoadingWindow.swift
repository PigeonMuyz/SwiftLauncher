import SwiftUI

struct GameLoadingWindow: View {
    @Bindable var store: LauncherStore

    var body: some View {
        GameLoadingView(
            instanceName: store.selectedInstance?.name ?? "Minecraft",
            isPresented: $store.showGameLoadingWindow,
            loadProgress: store.gameLoadProgress,
            logEntries: store.gameLogEntries
        )
    }
}
