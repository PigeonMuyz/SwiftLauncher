import SwiftUI

struct GameLoadingView: View {
    let instanceName: String
    @Binding var isPresented: Bool
    var loadProgress: GameLogParser.GameLoadProgress
    var logEntries: [GameLogParser.LogEntry]
    @State private var showDetailedLog = false

    var body: some View {
        ZStack {
            // 背景模糊效果
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                // Minecraft 风格标题
                VStack(spacing: 8) {
                    Text("Minecraft")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .green.opacity(0.7)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text(instanceName)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                // 加载动画
                LoadingCubeAnimation()
                    .frame(width: 120, height: 120)

                // 加载状态
                VStack(spacing: 12) {
                    Text(loadProgress.currentStage.rawValue)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    // 进度条
                    ProgressView(value: loadProgress.totalProgress)
                        .progressViewStyle(MinecraftProgressStyle())
                        .frame(width: 300)

                    // Mod 加载信息
                    if loadProgress.modsFound > 0 {
                        Text("已发现 \(loadProgress.modsFound) 个 Mod")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // 错误信息
                    if let error = loadProgress.lastError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error.prefix(100) + (error.count > 100 ? "..." : ""))
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }
                        .padding(.horizontal)
                    }
                }

                // 操作按钮
                HStack(spacing: 12) {
                    Button {
                        showDetailedLog.toggle()
                    } label: {
                        Label("详细日志", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)

                    Button("隐藏") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, 8)
            }
            .padding(40)
            .frame(width: 480, height: 520)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.3), radius: 20)
            }
        }
        .sheet(isPresented: $showDetailedLog) {
            DetailedLogView(entries: logEntries)
        }
    }
}

// Minecraft 风格加载方块动画
struct LoadingCubeAnimation: View {
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            // 外层立方体
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    LinearGradient(
                        colors: [.green, .green.opacity(0.5)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: 80, height: 80)
                .rotation3DEffect(
                    .degrees(rotation),
                    axis: (x: 1, y: 1, z: 0)
                )

            // 内层立方体
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    LinearGradient(
                        colors: [.green.opacity(0.3), .green.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 50, height: 50)
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
                RoundedRectangle(cornerRadius: 4)
                    .fill(.black.opacity(0.3))
                    .frame(height: 24)

                // 进度条
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(
                        width: geometry.size.width * CGFloat(configuration.fractionCompleted ?? 0),
                        height: 24
                    )
                    .overlay(alignment: .trailing) {
                        // 进度条末端高光
                        Rectangle()
                            .fill(.white.opacity(0.3))
                            .frame(width: 2)
                    }

                // 进度百分比
                Text("\(Int((configuration.fractionCompleted ?? 0) * 100))%")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 2)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 24)
    }
}

// 详细日志视图
struct DetailedLogView: View {
    let entries: [GameLogParser.LogEntry]
    @State private var selectedLevel: GameLogParser.LogLevel?

    var filteredEntries: [GameLogParser.LogEntry] {
        if let level = selectedLevel {
            return entries.filter { $0.level.priority >= level.priority }
        }
        return entries
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("详细日志")
                    .font(.headline)

                Spacer()

                // 日志级别过滤
                Picker("级别", selection: $selectedLevel) {
                    Text("全部").tag(nil as GameLogParser.LogLevel?)
                    Text("警告+").tag(GameLogParser.LogLevel.warn as GameLogParser.LogLevel?)
                    Text("错误+").tag(GameLogParser.LogLevel.error as GameLogParser.LogLevel?)
                    Text("致命").tag(GameLogParser.LogLevel.fatal as GameLogParser.LogLevel?)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }
            .padding()
            .background(.ultraThinMaterial)

            Divider()

            // 日志列表
            List(filteredEntries) { entry in
                HStack(alignment: .top, spacing: 12) {
                    // 级别标记
                    Circle()
                        .fill(levelColor(entry.level))
                        .frame(width: 8, height: 8)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.level.rawValue)
                                .font(.caption.bold())
                                .foregroundStyle(levelColor(entry.level))

                            Text(entry.logger)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Spacer()

                            Text(entry.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Text(entry.message)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
                    }
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
        }
        .frame(width: 800, height: 600)
    }

    private func levelColor(_ level: GameLogParser.LogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warn: return .orange
        case .error: return .red
        case .fatal: return .purple
        }
    }
}

// 毛玻璃效果
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

#Preview {
    GameLoadingView(
        instanceName: "我的整合包",
        isPresented: .constant(true),
        loadProgress: .init(),
        logEntries: []
    )
}
