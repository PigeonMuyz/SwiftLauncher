import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SidebarBottomPanel: View {
    let store: LauncherStore
    let width: CGFloat
    let displayTemplate: String
    @Binding var isShowingInstancePicker: Bool
    @Binding var isShowingAccountPicker: Bool
    @Binding var showingInstanceSettings: Bool

    var body: some View {
        VStack(spacing: 8) {
            InstanceSwitchCard(
                store: store,
                width: width,
                displayTemplate: displayTemplate,
                isShowingInstancePicker: $isShowingInstancePicker,
                showingInstanceSettings: $showingInstanceSettings
            )

            if isShowingInstancePicker {
                InstancePickerList(
                    store: store,
                    isPresented: $isShowingInstancePicker,
                    width: width,
                    displayTemplate: displayTemplate
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            AccountSwitchCard(
                store: store,
                width: width,
                isShowingAccountPicker: $isShowingAccountPicker
            )

            if isShowingAccountPicker {
                AccountPickerList(
                    store: store,
                    isPresented: $isShowingAccountPicker,
                    width: width
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
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
    @Binding var showingInstanceSettings: Bool

    var body: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isShowingInstancePicker.toggle()
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
                    Image(systemName: isShowingInstancePicker ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 14)
                .padding(.trailing, store.selectedInstance == nil ? 14 : 8)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if store.selectedInstance != nil {
                Button {
                    showingInstanceSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
                .help("实例设置")
            }
        }
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

    var body: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isShowingAccountPicker.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    AccountAvatarPlaceholder(account: store.selectedAccount, size: 32)
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
                    Image(systemName: isShowingAccountPicker ? "chevron.down" : "chevron.up")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 14)
                .padding(.trailing, 8)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                store.selection = .accounts
            } label: {
                Image(systemName: "person.crop.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 10)
            .help("账户管理")
        }
        .frame(width: width)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
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
                Image(systemName: state.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(state.tint, in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.title)
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
                .stroke(state.tint.opacity(state.isDisabled ? 0.15 : 0.35), lineWidth: 1)
        }
        .disabled(state.isDisabled)
        .opacity(state.isDisabled ? 0.55 : 1)
    }

    private var state: LaunchCardState {
        guard let instance = store.selectedInstance else {
            return .missingInstance
        }
        if store.runningInstanceID == instance.id {
            return .running(instance)
        }
        if store.gameProcessID != nil {
            return .runningOther
        }
        if store.isBusy || store.busyInstances.contains(instance.id) {
            return .busy(instance)
        }
        guard let account = store.account(for: instance) else {
            return .missingAccount(instance)
        }
        return .ready(instance: instance, account: account)
    }

    private func performAction() {
        switch state {
        case .missingInstance:
            store.presentNewInstance()
        case .missingAccount:
            store.selection = .accounts
        case .ready:
            Task { await store.launchSelectedInstance() }
        case .running:
            Task { await store.terminateGame() }
        case .busy, .runningOther:
            break
        }
    }
}

private struct InstancePickerList: View {
    let store: LauncherStore
    @Binding var isPresented: Bool
    let width: CGFloat
    let displayTemplate: String

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(store.instances.filter { $0.id != store.selectedInstanceID }) { instance in
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            store.selectedInstanceID = instance.id
                        }
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
            }
        }
        .frame(maxHeight: 320)
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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

    var body: some View {
        VStack(spacing: 8) {
            ForEach(store.accounts) { account in
                Button {
                    store.selectedAccountID = account.id
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        AccountAvatarPlaceholder(account: account, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.username)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(account.kind.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.selectedAccountID == account.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(width: width)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            accountActionButton("登录 Microsoft", systemImage: "person.badge.key", color: .green) {
                store.selection = .accounts
                store.beginMicrosoftLogin()
            }
            .disabled(store.isAuthenticatingMicrosoft)

            accountActionButton("添加本地账户", systemImage: "person.badge.plus", color: .blue) {
                store.selection = .accounts
                store.isPresentingLocalAccount = true
            }

            accountActionButton("管理账户", systemImage: "person.crop.circle", color: .secondary) {
                store.selection = .accounts
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPresented = false
        }
    }
}

private struct AccountAvatarPlaceholder: View {
    let account: PlayerAccount?
    let size: CGFloat

    var body: some View {
        Image(systemName: account?.kind == .microsoft ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle.fill")
            .font(.system(size: size * 0.72))
            .foregroundStyle(account?.kind == .microsoft ? .green : .secondary)
            .frame(width: size, height: size)
            .background(.quaternary.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .stroke(.separator.opacity(0.55), lineWidth: 0.5)
            }
    }
}

private enum LaunchCardState {
    case missingInstance
    case missingAccount(LauncherInstance)
    case busy(LauncherInstance)
    case running(LauncherInstance)
    case runningOther
    case ready(instance: LauncherInstance, account: PlayerAccount)

    var title: String {
        switch self {
        case .missingInstance:
            "创建游戏实例"
        case .missingAccount:
            "选择账户"
        case .busy:
            "正在准备"
        case .running:
            "停止游戏"
        case .runningOther:
            "游戏运行中"
        case .ready:
            "开始游戏"
        }
    }

    var subtitle: String {
        switch self {
        case .missingInstance:
            "新建或导入后开始"
        case let .missingAccount(instance):
            "\(instance.name) 需要账户"
        case let .busy(instance):
            "\(instance.name) 正在处理"
        case let .running(instance):
            "\(instance.name) 正在运行"
        case .runningOther:
            "请先停止当前游戏"
        case let .ready(instance, account):
            "\(instance.versionID) · \(account.username)"
        }
    }

    var systemImage: String {
        switch self {
        case .missingInstance:
            "plus"
        case .missingAccount:
            "person.crop.circle"
        case .busy:
            "hourglass"
        case .running:
            "stop.fill"
        case .runningOther:
            "play.slash"
        case .ready:
            "play.fill"
        }
    }

    var tint: Color {
        switch self {
        case .running:
            .red
        case .missingAccount:
            .blue
        case .missingInstance, .ready:
            .green
        case .busy, .runningOther:
            .secondary
        }
    }

    var isDisabled: Bool {
        switch self {
        case .busy, .runningOther:
            true
        case .missingInstance, .missingAccount, .running, .ready:
            false
        }
    }
}
