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

    private var progress: Double {
        min(max(loadProgress.totalProgress, 0), 1)
    }

    private var stateColor: Color {
        if loadProgress.hasFatalError { return .red }
        if loadProgress.isGameReady { return .green }
        return .blue
    }

    var body: some View {
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

                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.primary.opacity(0.1))
                            .frame(height: 6)

                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(stateColor)
                            .frame(width: geometry.size.width * progress, height: 6)
                            .animation(.easeInOut(duration: 0.25), value: progress)
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
        .padding(22)
        .frame(width: 320, height: 160)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
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
}
