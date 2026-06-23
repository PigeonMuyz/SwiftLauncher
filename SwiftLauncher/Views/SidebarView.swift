import SwiftUI

struct SidebarView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        List(selection: $store.selection) {
            ForEach(AppSection.allCases) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                if let task = store.activeDownloads.first {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("下载任务")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("\(store.activeDownloads.count)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Text(task.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        ProgressView(value: task.progress)
                            .tint(.green)
                    }
                }

                HStack(spacing: 7) {
                    Circle()
                        .fill(store.manifest == nil ? Color.orange : Color.green)
                        .frame(width: 8, height: 8)
                    Text(store.manifest == nil ? "等待官方数据" : "Mojang 连接正常")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }
}
