import SwiftUI

enum GameLoadingPresentationKind: String, CaseIterable, Identifiable {
    case compactCard

    var id: Self { self }
}

struct GameLoadingView: View {
    let store: LauncherStore
    let instance: LauncherInstance
    var loadProgress: GameLogParser.GameLoadProgress
    var presentation: GameLoadingPresentationKind = .compactCard

    var body: some View {
        switch presentation {
        case .compactCard:
            CompactGameLoadingPanel(
                store: store,
                instance: instance,
                loadProgress: loadProgress
            )
        }
    }
}

private struct CompactGameLoadingPanel: View {
    let store: LauncherStore
    let instance: LauncherInstance
    var loadProgress: GameLogParser.GameLoadProgress
    @State private var currentState: CustomGameLoadingState = .loading

    private var progress: Double {
        min(max(loadProgress.totalProgress, 0), 1)
    }

    var body: some View {
        loadingContent
        .padding(22)
        .frame(width: 320, height: 160)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        }
        .onAppear(perform: updateState)
        .onChange(of: loadProgress.hasFatalError) { _, _ in updateState() }
        .onChange(of: loadProgress.isGameReady) { _, _ in updateState() }
    }

    private var loadingContent: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                InstanceIconView(store: store, instance: instance, size: 42)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(instance.name)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text("Minecraft \(instance.versionID) · \(instance.loader.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 24)
            }

            progressBar
        }
    }

    private var progressBar: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(currentState.color)
                        .frame(width: geometry.size.width * progress, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: progress)
                        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: currentState)
                }
            }
            .frame(height: 6)

            HStack {
                Text(statusText)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if loadProgress.hasFatalError {
            return "启动失败，请查看游戏日志"
        }
        if loadProgress.isGameReady {
            return "加载完成，正在显示游戏窗口"
        }
        return loadProgress.currentStage.rawValue
    }

    private func updateState() {
        if loadProgress.hasFatalError {
            currentState = .failed
        } else if loadProgress.isGameReady {
            currentState = .success
        } else {
            currentState = .loading
        }
    }
}

private enum CustomGameLoadingState {
    case loading
    case success
    case failed

    var color: Color {
        switch self {
        case .loading: .blue
        case .success: .green
        case .failed: .red
        }
    }
}
