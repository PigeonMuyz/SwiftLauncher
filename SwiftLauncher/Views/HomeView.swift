import AppKit
import SwiftUI

struct HomeView: View {
    @Bindable var store: LauncherStore

    private var recentInstances: [LauncherInstance] {
        store.instances.sorted {
            ($0.lastPlayedAt ?? $0.createdAt) > ($1.lastPlayedAt ?? $1.createdAt)
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                launcherBackground
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                Color.black.opacity(0.34)

                ScrollView {
                    VStack(spacing: 24) {
                        hero
                            .frame(minHeight: 430)

                        recentSection
                    }
                    .frame(width: contentWidth(for: proxy.size.width))
                    .padding(.top, 24)
                    .padding(.bottom, 36)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .foregroundStyle(.white)
        .overlay {
            if store.manifest == nil && store.isRefreshing {
                ProgressView("正在读取 Mojang 官方数据…")
                    .controlSize(.large)
                    .padding(22)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func contentWidth(for availableWidth: CGFloat) -> CGFloat {
        max(520, min(1120, availableWidth - min(96, availableWidth * 0.1)))
    }

    @ViewBuilder
    private var hero: some View {
        if let instance = store.selectedInstance {
            VStack(spacing: 18) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.white.opacity(0.78))

                VStack(spacing: 5) {
                    Text(instance.name)
                        .font(.system(size: 50, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)

                    Text("MC \(instance.versionID)")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(mossAccent)
                }

                VStack(spacing: 10) {
                    Label(
                        store.preferredRuntime(for: instance)?.displayName ?? "未找到适用的 Java",
                        systemImage: "cup.and.heat.waves"
                    )
                    .foregroundStyle(.white.opacity(0.86))

                    Label(
                        instance.isVersionIsolated ? "版本隔离已启用" : "使用共享游戏目录",
                        systemImage: instance.isVersionIsolated ? "checkmark.circle.fill" : "folder"
                    )
                    .foregroundStyle(instance.isVersionIsolated ? mossAccent : .white.opacity(0.72))

                    if instance.loader != .vanilla {
                        Label(loaderDescription(instance), systemImage: "puzzlepiece.extension.fill")
                            .foregroundStyle(.white.opacity(0.82))
                    }
                }
                .font(.body.weight(.medium))

                HStack(spacing: 12) {
                    Button {
                        Task { await store.launchSelectedInstance() }
                    } label: {
                        Label(
                            store.isInstalled(instance) ? "启动游戏" : "安装并启动",
                            systemImage: "play.fill"
                        )
                        .font(.title3.weight(.semibold))
                        .frame(width: 310, height: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(mossButton, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.white.opacity(0.22), lineWidth: 0.75)
                    }
                    .shadow(color: mossButton.opacity(0.34), radius: 12, y: 5)
                    .opacity(store.isBusy ? 0.5 : 1)
                    .disabled(store.isBusy)

                    instanceMenu(instance)
                }

                Text(store.isInstalled(instance) ? "Mojang 官方文件 · 已安装" : "Mojang 官方文件 · 等待安装")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }
        } else {
            VStack(spacing: 18) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 50, weight: .light))
                    .foregroundStyle(.white.opacity(0.76))
                Text("创建你的第一个实例")
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                Text("选择 Minecraft 版本、加载器和实例名称，游戏文件默认互相隔离。")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.72))
                Button {
                    store.isPresentingNewInstance = true
                } label: {
                    Label("新建游戏实例", systemImage: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 290, height: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(mossButton)
                .controlSize(.large)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近实例")
                    .font(.headline)
                Spacer()
                Button("管理全部") { store.selection = .instances }
                    .buttonStyle(.plain)
                    .foregroundStyle(mossAccent)
            }
            .padding(.bottom, 10)

            Divider()
                .overlay(.white.opacity(0.16))

            if recentInstances.isEmpty {
                HStack {
                    Text("尚未创建游戏实例")
                        .foregroundStyle(.white.opacity(0.64))
                    Spacer()
                    Button("立即创建") { store.isPresentingNewInstance = true }
                        .buttonStyle(.plain)
                        .foregroundStyle(mossAccent)
                }
                .frame(height: 64)
            } else {
                ForEach(Array(recentInstances.prefix(5).enumerated()), id: \.element.id) { index, instance in
                    RecentInstanceRow(
                        store: store,
                        instance: instance,
                        accent: mossAccent,
                        onSelect: { store.selectedInstanceID = instance.id },
                        onLaunch: {
                            store.selectedInstanceID = instance.id
                            Task { await store.launchSelectedInstance() }
                        }
                    )
                    if index < min(recentInstances.count, 5) - 1 {
                        Divider()
                            .overlay(.white.opacity(0.12))
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
    }

    private func instanceMenu(_ instance: LauncherInstance) -> some View {
        Menu {
            Button("管理实例") { store.selection = .instances }
            Button("打开游戏目录") { store.openGameDirectory(instance) }
            if !store.isInstalled(instance) {
                Button("仅安装") { Task { await store.install(instance) } }
            }
            Divider()
            Button("创建新实例") { store.isPresentingNewInstance = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.semibold))
                .frame(width: 46, height: 46)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func loaderDescription(_ instance: LauncherInstance) -> String {
        guard let version = instance.loaderVersion, !version.isEmpty else {
            return instance.loader.title
        }
        return "\(instance.loader.title) \(version)"
    }

    private var mossAccent: Color {
        Color(red: 0.68, green: 0.80, blue: 0.43)
    }

    private var mossButton: Color {
        Color(red: 0.42, green: 0.56, blue: 0.24)
    }

    private var launcherBackground: Image {
        if let image = NSImage(named: "LauncherBackground") {
            return Image(nsImage: image)
        }
        let developmentURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("SwiftLauncher/Resources/LauncherBackground.png")
        if let image = NSImage(contentsOf: developmentURL) {
            return Image(nsImage: image)
        }
        return Image("LauncherBackground")
    }
}

private struct RecentInstanceRow: View {
    let store: LauncherStore
    let instance: LauncherInstance
    let accent: Color
    let onSelect: () -> Void
    let onLaunch: () -> Void

    private var activeDownload: DownloadTaskInfo? {
        store.downloads.first {
            $0.title == instance.name && ($0.state == .queued || $0.state == .downloading)
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: store.isInstalled(instance) ? "shippingbox.fill" : "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(store.isInstalled(instance) ? accent : .white.opacity(0.66))
                .frame(width: 38, height: 38)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(instance.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(versionLine)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let activeDownload {
                VStack(alignment: .leading, spacing: 5) {
                    Text("正在安装 \(Int(activeDownload.progress * 100))%")
                        .font(.caption)
                    ProgressView(value: activeDownload.progress)
                        .tint(accent)
                }
                .frame(width: 170)
            } else {
                Text(store.isInstalled(instance) ? "安装完成" : "等待安装")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(width: 100, alignment: .leading)
            }

            Text((instance.lastPlayedAt ?? instance.createdAt), format: .dateTime.month().day().hour().minute())
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 110, alignment: .trailing)

            Button(action: onLaunch) {
                Image(systemName: "play.fill")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.bordered)
            .tint(accent)
            .disabled(store.isBusy)

            Menu {
                Button("选择实例", action: onSelect)
                Button("打开游戏目录") { store.openGameDirectory(instance) }
                Button("管理设置") {
                    onSelect()
                    store.selection = .instances
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 24)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .frame(height: 62)
    }

    private var versionLine: String {
        let loader = instance.loader == .vanilla ? "原版" : instance.loader.title
        return "MC \(instance.versionID) · \(loader)"
    }
}

struct VersionRow: View {
    let version: MinecraftVersion

    var body: some View {
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
        }
        .padding(.vertical, 4)
    }
}
