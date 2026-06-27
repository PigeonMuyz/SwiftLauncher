import AppKit
import SwiftUI

struct HomeView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                launcherBackground
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()

                Color.black.opacity(0.34)

                VStack(spacing: 32) {
                    Spacer()

                    // 账户选择卡片
                    accountCard
                        .frame(width: min(480, proxy.size.width - 80))

                    // 启动游戏按钮
                    launchButton
                        .frame(width: min(480, proxy.size.width - 80))

                    Spacer()
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

    @ViewBuilder
    private var accountCard: some View {
        VStack(spacing: 16) {
            Text("选择账户")
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            if store.accounts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.6))

                    Text("还没有账户")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.8))

                    Button {
                        store.selection = .accounts
                    } label: {
                        Label("添加账户", systemImage: "plus.circle.fill")
                            .font(.body.weight(.medium))
                            .frame(width: 200, height: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(mossButton)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                Picker("账户", selection: $store.selectedAccountID) {
                    Text("选择账户").tag(nil as UUID?)
                    ForEach(store.accounts) { account in
                        accountRow(account)
                            .tag(account.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var launchButton: some View {
        if let instance = store.selectedInstance {
            Button {
                Task { await store.launchSelectedInstance() }
            } label: {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        InstanceIconView(store: store, instance: instance, size: 48, tint: .white)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(instance.name)
                                .font(.title3.weight(.semibold))
                                .lineLimit(1)

                            Text("MC \(instance.versionID)")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                        }

                        Spacer()

                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(mossButton, in: RoundedRectangle(cornerRadius: 20))
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(.white.opacity(0.25), lineWidth: 1)
                }
                .shadow(color: mossButton.opacity(0.4), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(store.isBusy || store.gameProcessID != nil || store.selectedAccountID == nil)
            .opacity((store.isBusy || store.gameProcessID != nil || store.selectedAccountID == nil) ? 0.5 : 1)
        } else {
            VStack(spacing: 16) {
                Image(systemName: "shippingbox.circle")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.7))

                Text("还没有游戏实例")
                    .font(.title3.weight(.medium))

                Text("从 Sidebar 底部创建或导入实例")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
            }
        }
    }

    @ViewBuilder
    private func accountRow(_ account: PlayerAccount) -> some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.8))
            Text(account.username)
                .font(.body)
        }
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
