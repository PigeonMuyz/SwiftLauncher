import SwiftUI

struct DownloadsView: View {
    @Bindable var store: LauncherStore
    let section: DownloadSection
    @State private var versionType: VersionType = .release
    @State private var taskFilter: DownloadTaskFilter = .all

    init(store: LauncherStore, section: DownloadSection) {
        self.store = store
        self.section = section
    }

    var body: some View {
        Group {
            switch section {
            case .games:
                gameDownloads
            case .tasks:
                taskList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var gameDownloads: some View {
        TabView(selection: $versionType) {
            ForEach(VersionType.allCases, id: \.self) { type in
                versionList(for: type)
                    .tabItem {
                        Text(type.title)
                    }
                    .tag(type)
            }
        }
        .tabViewStyle(.automatic)
    }

    private func versionList(for type: VersionType) -> some View {
        List(filteredVersions(for: type).prefix(300)) { version in
            HStack(spacing: 12) {
                Image(systemName: systemImage(for: version.type))
                    .foregroundStyle(color(for: version.type))
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Minecraft \(version.id)")
                        .font(.body.monospacedDigit())
                    Text("\(version.type.title) · Mojang 官方")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(version.releaseTime, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    store.presentNewInstance(versionID: version.id)
                } label: {
                    Label("创建并安装", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
            .padding(.vertical, 4)
        }
        .overlay {
            if store.manifest == nil {
                ProgressView("正在读取版本清单…")
            } else if filteredVersions(for: type).isEmpty {
                ContentUnavailableView {
                    Label("没有\(type.title)版本", systemImage: systemImage(for: type))
                }
            }
        }
    }

    private var taskList: some View {
        Group {
            if store.downloads.isEmpty {
                ContentUnavailableView {
                    Label("没有下载任务", systemImage: "arrow.down.circle")
                } description: {
                    Text("游戏、模组和导入任务的真实进度会显示在这里。")
                }
            } else {
                VStack(spacing: 0) {
                    VStack(spacing: 10) {
                        HStack {
                            Text("任务队列")
                                .font(.headline)
                            if !store.activeDownloads.isEmpty {
                                Text("\(store.activeDownloads.count) 个进行中")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            Button("清除已完成") { store.clearCompletedDownloads() }
                                .disabled(!store.downloads.contains { $0.state == .completed || $0.state == .cancelled })
                        }

                        HStack(spacing: 18) {
                            taskMetric("全部", value: store.downloads.count, color: .secondary)
                            taskMetric("进行中", value: store.activeDownloads.count, color: .blue)
                            taskMetric("已暂停", value: store.downloads.filter { $0.state == .paused }.count, color: .orange)
                            taskMetric("失败", value: store.downloads.filter { $0.state == .failed }.count, color: .red)
                            taskMetric("已完成", value: store.downloads.filter { $0.state == .completed }.count, color: .green)
                            Spacer()
                        }
                    }
                    .padding(14)
                    Divider()
                    TabView(selection: $taskFilter) {
                        ForEach(DownloadTaskFilter.allCases) { filter in
                            taskPane(for: filter)
                                .tabItem {
                                    Text(filter.title)
                                }
                                .tag(filter)
                        }
                    }
                    .tabViewStyle(.automatic)
                }
            }
        }
    }

    @ViewBuilder
    private func taskPane(for filter: DownloadTaskFilter) -> some View {
        let tasks = downloads(for: filter)
        if tasks.isEmpty {
            ContentUnavailableView {
                Label("没有\(filter.title)任务", systemImage: filter.systemImage)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(tasks) { task in
                taskRow(task)
            }
        }
    }

    private func filteredVersions(for type: VersionType) -> [MinecraftVersion] {
        (store.manifest?.versions ?? []).filter {
            $0.type == type
        }
    }

    private func systemImage(for type: VersionType) -> String {
        switch type {
        case .release: "tag"
        case .snapshot: "camera.filters"
        case .oldBeta: "clock.badge"
        case .oldAlpha: "clock"
        }
    }

    private func color(for type: VersionType) -> Color {
        switch type {
        case .release: .green
        case .snapshot: .blue
        case .oldBeta, .oldAlpha: .orange
        }
    }

    private func downloads(for filter: DownloadTaskFilter) -> [DownloadTaskInfo] {
        switch filter {
        case .all:
            store.downloads
        case .active:
            store.downloads.filter(\.isActive)
        case .failed:
            store.downloads.filter { $0.state == .failed }
        case .completed:
            store.downloads.filter { $0.state == .completed || $0.state == .cancelled }
        }
    }

    private func taskMetric(_ title: String, value: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color.opacity(0.78))
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .fontWeight(.semibold)
        }
        .font(.caption)
    }

    private func taskRow(_ task: DownloadTaskInfo) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: task.kind.systemImage)
                    .foregroundStyle(color(for: task.state))
                    .frame(width: 18)
                Text(task.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(task.kind.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(task.state.title)
                    .foregroundStyle(.secondary)
                taskControls(for: task)
            }
            HStack(spacing: 8) {
                Text(task.phase.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color(for: task.state))
                Text(task.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if task.state == .downloading || task.state == .queued || task.state == .paused {
                ProgressView(value: task.progress)
                    .tint(task.state == .paused ? .orange : .green)
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

    @ViewBuilder
    private func taskControls(for task: DownloadTaskInfo) -> some View {
        if task.isActive {
            HStack(spacing: 4) {
                if task.state == .paused {
                    Button {
                        store.resumeDownload(task.id)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .help("继续任务")
                } else {
                    Button {
                        store.pauseDownload(task.id)
                    } label: {
                        Image(systemName: "pause.fill")
                    }
                    .help("暂停任务")
                }

                Button {
                    store.cancelDownload(task.id)
                } label: {
                    Image(systemName: "xmark")
                }
                .help("取消任务")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .foregroundStyle(.secondary)
        }
    }

    private func color(for state: DownloadState) -> Color {
        switch state {
        case .completed: .green
        case .failed: .red
        case .paused: .orange
        case .downloading: .blue
        case .queued, .cancelled: .secondary
        }
    }
}

enum DownloadSection: String, CaseIterable, Identifiable {
    case games
    case tasks

    var id: Self { self }

    var title: String {
        switch self {
        case .games: "游戏"
        case .tasks: "任务"
        }
    }

    var systemImage: String {
        switch self {
        case .games: "shippingbox"
        case .tasks: "list.bullet.rectangle"
        }
    }
}

private enum DownloadTaskFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case failed
    case completed

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部"
        case .active: "进行中"
        case .failed: "失败"
        case .completed: "已结束"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "list.bullet.rectangle"
        case .active: "arrow.down.circle"
        case .failed: "exclamationmark.triangle"
        case .completed: "checkmark.circle"
        }
    }
}
