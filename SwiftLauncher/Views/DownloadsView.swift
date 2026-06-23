import SwiftUI

struct DownloadsView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        Group {
            if store.downloads.isEmpty {
                ContentUnavailableView {
                    Label("没有下载任务", systemImage: "arrow.down.circle")
                } description: {
                    Text("安装实例时，真实下载进度会显示在这里。")
                } actions: {
                    Button("添加实例") { store.isPresentingNewInstance = true }
                }
            } else {
                List(store.downloads) { task in
                    VStack(alignment: .leading, spacing: 9) {
                        HStack {
                            Image(systemName: icon(for: task.state))
                                .foregroundStyle(color(for: task.state))
                            Text(task.title)
                                .font(.headline)
                            Spacer()
                            Text(task.state.title)
                                .foregroundStyle(.secondary)
                        }
                        Text(task.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if task.state == .downloading || task.state == .queued {
                            ProgressView(value: task.progress)
                                .tint(.green)
                        }
                        if let error = task.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .toolbar {
                    ToolbarItem {
                        Button("清除已完成") { store.clearCompletedDownloads() }
                    }
                }
            }
        }
    }

    private func icon(for state: DownloadState) -> String {
        switch state {
        case .queued: "clock"
        case .downloading: "arrow.down.circle"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .cancelled: "xmark.circle"
        }
    }

    private func color(for state: DownloadState) -> Color {
        switch state {
        case .completed: .green
        case .failed: .red
        case .downloading: .blue
        case .queued, .cancelled: .secondary
        }
    }
}
