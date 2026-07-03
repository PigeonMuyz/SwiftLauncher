import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let sidebarPickerAnimation = Animation.easeInOut(duration: 0.18)

struct SidebarBottomPanel: View {
    let store: LauncherStore
    let width: CGFloat
    let displayTemplate: String
    @Binding var isShowingInstancePicker: Bool
    @Binding var isShowingAccountPicker: Bool
    @Binding var showingAccountManagement: Bool
    @Binding var showingInstanceManagement: Bool

    var body: some View {
        VStack(spacing: 8) {
            InstanceSwitchCard(
                store: store,
                width: width,
                displayTemplate: displayTemplate,
                isShowingInstancePicker: $isShowingInstancePicker,
                isShowingAccountPicker: $isShowingAccountPicker,
                showingInstanceManagement: $showingInstanceManagement
            )

            if isShowingInstancePicker {
                InstancePickerList(
                    store: store,
                    isPresented: $isShowingInstancePicker,
                    width: width,
                    displayTemplate: displayTemplate,
                    showingInstanceManagement: $showingInstanceManagement
                )
                .transition(.opacity)
                .clipped()
            }

            AccountSwitchCard(
                store: store,
                width: width,
                isShowingAccountPicker: $isShowingAccountPicker,
                isShowingInstancePicker: $isShowingInstancePicker
            )

            if isShowingAccountPicker {
                AccountPickerList(
                    store: store,
                    isPresented: $isShowingAccountPicker,
                    width: width,
                    showingAccountManagement: $showingAccountManagement
                )
                .transition(.opacity)
                .clipped()
            }

            LaunchGameCard(store: store, width: width)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}

private struct InstanceSwitchCard: View {
    let store: LauncherStore
    let width: CGFloat
    let displayTemplate: String
    @Binding var isShowingInstancePicker: Bool
    @Binding var isShowingAccountPicker: Bool
    @Binding var showingInstanceManagement: Bool

    var body: some View {
        Button {
            withAnimation(sidebarPickerAnimation) {
                let shouldOpen = !isShowingInstancePicker
                isShowingInstancePicker = shouldOpen
                if shouldOpen {
                    isShowingAccountPicker = false
                }
            }
        } label: {
            HStack(spacing: 10) {
                if let instance = store.selectedInstance {
                    InstanceIconView(store: store, instance: instance, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instance.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(versionLine(for: instance))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Image(systemName: "shippingbox")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("选择实例")
                            .font(.subheadline.weight(.medium))
                        Text("新建或导入游戏")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                PickerChevron(isExpanded: isShowingInstancePicker)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: width)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func versionLine(for instance: LauncherInstance) -> String {
        let modCount = store.mods[instance.id]?.count ?? 0
        let loader = instance.loader == .vanilla ? "原版" : instance.loader.title

        return displayTemplate
            .replacingOccurrences(of: "${mc_version}", with: instance.versionID)
            .replacingOccurrences(of: "${mod_loader}", with: loader)
            .replacingOccurrences(of: "${mod_num}", with: "\(modCount)")
    }
}

private struct AccountSwitchCard: View {
    let store: LauncherStore
    let width: CGFloat
    @Binding var isShowingAccountPicker: Bool
    @Binding var isShowingInstancePicker: Bool

    var body: some View {
        Button {
            withAnimation(sidebarPickerAnimation) {
                let shouldOpen = !isShowingAccountPicker
                isShowingAccountPicker = shouldOpen
                if shouldOpen {
                    isShowingInstancePicker = false
                }
            }
        } label: {
            HStack(spacing: 10) {
                MinecraftAvatarView(account: store.selectedAccount, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selectedAccount?.username ?? "选择账户")
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(store.selectedAccount?.kind.title ?? "登录或添加本地账户")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
            }
            Spacer()
            PickerChevron(isExpanded: isShowingAccountPicker)
        }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct PickerChevron: View {
    let isExpanded: Bool

    var body: some View {
        Image(systemName: "chevron.up")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 14, height: 14)
            .rotationEffect(.degrees(isExpanded ? 180 : 0))
            .animation(sidebarPickerAnimation, value: isExpanded)
    }
}

private struct LaunchGameCard: View {
    let store: LauncherStore
    let width: CGFloat

    var body: some View {
        Button {
            performAction()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "play.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(state.isDisabled ? Color.secondary : Color.green, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("开始游戏")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(state.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    (state.isDisabled ? Color.secondary : Color.green)
                        .opacity(state.isDisabled ? 0.15 : 0.35),
                    lineWidth: 1
                )
        }
        .disabled(state.isDisabled)
        .opacity(state.isDisabled ? 0.55 : 1)
    }

    private var state: LaunchCardState {
        guard let instance = store.selectedInstance else {
            return .disabled("先选择游戏实例")
        }
        if store.gameProcessID != nil {
            return .disabled("游戏正在运行")
        }
        if store.isWorking(on: instance) {
            return .disabled("\(instance.name) 正在准备")
        }
        guard let account = store.account(for: instance) else {
            return .disabled("先选择有效用户")
        }
        return .ready(instance: instance, account: account)
    }

    private func performAction() {
        switch state {
        case .disabled:
            break
        case .ready:
            Task { await store.launchSelectedInstance() }
        }
    }
}

private struct InstancePickerList: View {
    let store: LauncherStore
    @Binding var isPresented: Bool
    let width: CGFloat
    let displayTemplate: String
    @Binding var showingInstanceManagement: Bool

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach(store.instances.filter { $0.id != store.selectedInstanceID }) { instance in
                    Button {
                        store.selectedInstanceID = instance.id
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            InstanceIconView(store: store, instance: instance, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(instance.name)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                Text(versionLine(for: instance))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(width: width)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }

                instanceActionButton("新建实例...", systemImage: "plus.circle.fill", color: .green) {
                    store.presentNewInstance()
                }

                instanceActionButton("导入整合包...", systemImage: "archivebox", color: .blue) {
                    openModpackImporter()
                }

                instanceActionButton("导入 .minecraft...", systemImage: "folder.badge.plus", color: .orange) {
                    openMinecraftFolderImporter()
                }

                instanceActionButton("管理实例...", systemImage: "square.stack.3d.up", color: .secondary) {
                    showingInstanceManagement = true
                }
            }
        }
        .frame(maxHeight: 320)
        .clipped()
    }

    private func instanceActionButton(
        _ title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: width)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func dismiss() {
        withAnimation(sidebarPickerAnimation) {
            isPresented = false
        }
    }

    private func openModpackImporter() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: "mrpack") ?? .zip, .zip]
        panel.message = "选择 Modrinth 整合包文件 (.mrpack 或 .zip)"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await store.importModpack(from: url) }
        }
    }

    private func openMinecraftFolderImporter() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "选择 .minecraft 文件夹"

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { await store.importMinecraftFolder(from: url) }
        }
    }

    private func versionLine(for instance: LauncherInstance) -> String {
        let modCount = store.mods[instance.id]?.count ?? 0
        let loader = instance.loader == .vanilla ? "原版" : instance.loader.title

        return displayTemplate
            .replacingOccurrences(of: "${mc_version}", with: instance.versionID)
            .replacingOccurrences(of: "${mod_loader}", with: loader)
            .replacingOccurrences(of: "${mod_num}", with: "\(modCount)")
    }
}

private struct AccountPickerList: View {
    let store: LauncherStore
    @Binding var isPresented: Bool
    let width: CGFloat
    @Binding var showingAccountManagement: Bool

    var body: some View {
        VStack(spacing: 8) {
            ForEach(store.accounts.filter { $0.id != store.selectedAccountID }) { account in
                Button {
                    store.selectedAccountID = account.id
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        MinecraftAvatarView(account: account, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.username)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(account.kind.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(width: width)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            accountActionButton("管理用户...", systemImage: "person.2", color: .secondary) {
                showingAccountManagement = true
            }
        }
    }

    private func accountActionButton(
        _ title: String,
        systemImage: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(width: width)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func dismiss() {
        withAnimation(sidebarPickerAnimation) {
            isPresented = false
        }
    }
}

private enum LaunchCardState {
    case disabled(String)
    case ready(instance: LauncherInstance, account: PlayerAccount)

    var subtitle: String {
        switch self {
        case let .disabled(reason):
            reason
        case let .ready(instance, account):
            "\(instance.versionID) · \(account.username)"
        }
    }

    var isDisabled: Bool {
        switch self {
        case .disabled:
            true
        case .ready:
            false
        }
    }
}
