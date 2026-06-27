import SwiftUI

struct GameLoadingView: View {
    let store: LauncherStore
    let instance: LauncherInstance
    var loadProgress: GameLogParser.GameLoadProgress

    var body: some View {
        VStack(spacing: 20) {
            if loadProgress.hasFatalError {
                // 错误状态
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.red)

                VStack(spacing: 8) {
                    Text("启动失败")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)

                    Text("请查看游戏日志了解详情")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                // 实例图标
                InstanceIconView(store: store, instance: instance, size: 80)
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)

                VStack(spacing: 8) {
                    // 实例名称
                    Text(instance.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    // 加载状态
                    Text(loadProgress.currentStage.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))

                    ProgressView(value: loadProgress.totalProgress)
                        .progressViewStyle(MinecraftProgressStyle())
                        .frame(width: 200)

                    if loadProgress.modsFound > 0 {
                        Text("\(loadProgress.modsFound) Mods")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
        }
        .padding(30)
        .frame(width: 280, height: 240)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.black.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 10)
    }
}

// Minecraft 风格加载方块动画
struct LoadingCubeAnimation: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // 外层立方体
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    LinearGradient(
                        colors: [.green, .green.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: 50, height: 50)
                .rotation3DEffect(
                    .degrees(rotation),
                    axis: (x: 1, y: 1, z: 0)
                )

            // 内层立方体
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        colors: [.green.opacity(0.3), .green.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 30, height: 30)
                .rotation3DEffect(
                    .degrees(-rotation * 1.5),
                    axis: (x: 0, y: 1, z: 1)
                )
        }
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
    }
}

// Minecraft 风格进度条
struct MinecraftProgressStyle: ProgressViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 背景
                RoundedRectangle(cornerRadius: 3)
                    .fill(.black.opacity(0.3))
                    .frame(height: 18)

                // 进度条
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: geometry.size.width * CGFloat(configuration.fractionCompleted ?? 0),
                        height: 18
                    )
                    .overlay(alignment: .trailing) {
                        // 进度条末端高光
                        Rectangle()
                            .fill(.white.opacity(0.3))
                            .frame(width: 2)
                    }

                // 进度百分比
                Text("\(Int((configuration.fractionCompleted ?? 0) * 100))%")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 18)
    }
}

//#Preview {
//    GameLoadingView(
//        store: LauncherStore(),
//        instance: LauncherInstance(
//            id: UUID(),
//            name: "我的整合包",
//            versionID: "1.20.1",
//            loader: .forge
//        ),
//        loadProgress: GameLogParser.GameLoadProgress(
//            currentStage: .loadingMods,
//            modsFound: 42,
//            totalProgress: 0.5
//        )
//    )
//}
