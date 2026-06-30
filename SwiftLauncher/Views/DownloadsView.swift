import SwiftUI

struct DownloadsView: View {
    @Bindable var store: LauncherStore
    let section: DownloadSection
    @State private var versionType: VersionType = .release
    @State private var versionSearch = ""
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
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Picker("版本类型", selection: $versionType) {
                    ForEach(VersionType.allCases, id: \.self) { type in
                        Text(type.title).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                TextField("搜索 Minecraft 版本", text: $versionSearch)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(14)

            Divider()

            List(filteredVersions.prefix(300)) { version in
                HStack(spacing: 12) {
                    Image(systemName: version.type == .release ? "tag" : "circle.dotted")
                        .foregroundStyle(version.type == .release ? .green : .blue)
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
                } else if filteredVersions.isEmpty {
                    ContentUnavailableView.search(text: versionSearch)
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
                            Picker("任务筛选", selection: $taskFilter) {
                                ForEach(DownloadTaskFilter.allCases) { filter in
                                    Text(filter.title).tag(filter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 360)
                            Button("清除已完成") { store.clearCompletedDownloads() }
                                .disabled(store.downloads.allSatisfy(\.isActive))
                        }

                        HStack(spacing: 18) {
                            taskMetric("全部", value: store.downloads.count, color: .secondary)
                            taskMetric("进行中", value: store.activeDownloads.count, color: .blue)
                            taskMetric("失败", value: store.downloads.filter { $0.state == .failed }.count, color: .red)
                            taskMetric("已完成", value: store.downloads.filter { $0.state == .completed }.count, color: .green)
                            Spacer()
                        }
                    }
                    .padding(14)
                    Divider()
                    if filteredDownloads.isEmpty {
                        ContentUnavailableView {
                            Label("没有\(taskFilter.title)任务", systemImage: taskFilter.systemImage)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(filteredDownloads) { task in
                            taskRow(task)
                        }
                    }
                }
            }
        }
    }

    private var filteredVersions: [MinecraftVersion] {
        (store.manifest?.versions ?? []).filter {
            $0.type == versionType
                && (versionSearch.isEmpty || $0.id.localizedCaseInsensitiveContains(versionSearch))
        }
    }

    private var filteredDownloads: [DownloadTaskInfo] {
        switch taskFilter {
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

    private func color(for state: DownloadState) -> Color {
        switch state {
        case .completed: .green
        case .failed: .red
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
