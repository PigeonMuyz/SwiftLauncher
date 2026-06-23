import AppKit
import SwiftUI

struct AccountsView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        VStack(spacing: 0) {
            if store.accounts.isEmpty {
                ContentUnavailableView {
                    Label("还没有游戏账户", systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text("正版账户使用 Microsoft 设备授权；本地账户适合开发和已有正版玩家的离线环境。")
                } actions: {
                    accountButtons
                }
            } else {
                List(store.accounts, selection: $store.selectedAccountID) { account in
                    HStack(spacing: 12) {
                        Image(systemName: account.kind == .microsoft ? "person.crop.circle.fill.badge.checkmark" : "person.crop.circle")
                            .font(.title2)
                            .foregroundStyle(account.kind == .microsoft ? .green : .secondary)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.username)
                                .font(.headline)
                            Text("\(account.kind.title) · \(formattedProfileID(account.profileID))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.selectedAccountID == account.id {
                            Text("当前")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(.vertical, 6)
                    .tag(account.id)
                    .contextMenu {
                        Button("移除账户", role: .destructive) {
                            Task { await store.removeAccount(account) }
                        }
                    }
                }

                Divider()
                HStack {
                    accountButtons
                    Spacer()
                    Text("访问令牌仅保存在 macOS Keychain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
            }
        }
        .sheet(isPresented: $store.isPresentingLocalAccount) {
            LocalAccountSheet(store: store)
        }
        .sheet(
            isPresented: Binding(
                get: { store.microsoftDeviceCode != nil },
                set: { if !$0 { store.cancelMicrosoftLogin() } }
            )
        ) {
            if let code = store.microsoftDeviceCode {
                MicrosoftDeviceCodeView(store: store, code: code)
            }
        }
    }

    @ViewBuilder
    private var accountButtons: some View {
        HStack {
            Button {
                store.beginMicrosoftLogin()
            } label: {
                Label("登录 Microsoft", systemImage: "person.badge.key")
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(store.isAuthenticatingMicrosoft)

            Button {
                store.isPresentingLocalAccount = true
            } label: {
                Label("添加本地账户", systemImage: "person.badge.plus")
            }
        }
    }

    private func formattedProfileID(_ value: String) -> String {
        value.count > 12 ? "\(value.prefix(8))…\(value.suffix(4))" : value
    }
}

private struct LocalAccountSheet: View {
    @Bindable var store: LauncherStore
    @Environment(\.dismiss) private var dismiss
    @ViewState private var username = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("添加本地账户")
                .font(.title2.weight(.semibold))
            Text("本地账户不会绕过服务器验证。请支持正版 Minecraft。")
                .foregroundStyle(.secondary)
            TextField("玩家名称", text: $username)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("添加") {
                    Task { await store.addLocalAccount(username: username) }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}

private struct MicrosoftDeviceCodeView: View {
    @Bindable var store: LauncherStore
    let code: MicrosoftDeviceCode

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 42))
                .foregroundStyle(.green)
            Text("在浏览器中完成 Microsoft 登录")
                .font(.title2.weight(.semibold))
            Text(code.userCode)
                .font(.system(.title, design: .monospaced, weight: .bold))
                .textSelection(.enabled)
            Text(code.message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack {
                Button("取消") { store.cancelMicrosoftLogin() }
                Button("复制代码") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code.userCode, forType: .string)
                }
                Button("打开登录网页") { NSWorkspace.shared.open(code.verificationURI) }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
            }
            ProgressView(store.microsoftAuthenticationStatus)
            Text("授权成功后此窗口会自动关闭；也可以随时取消。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 520)
    }
}
