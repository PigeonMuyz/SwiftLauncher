import SwiftUI

struct ModrinthDetailsSheet: View {
    let store: LauncherStore
    let instance: LauncherInstance
    @Environment(\.dismiss) private var dismiss
    @AppStorage(LauncherExperienceMode.defaultsKey) private var experienceMode = LauncherExperienceMode.beginner.rawValue
    @AppStorage(LauncherExperienceMode.autoDependenciesDefaultsKey) private var autoInstallRequiredMods = true

    private var plan: ModrinthInstallPlan? {
        store.modInstallPlan
    }

    private var selectedExperienceMode: LauncherExperienceMode {
        LauncherExperienceMode(rawValue: experienceMode) ?? .beginner
    }

    private var installButtonTitle: String {
        guard plan?.kind == .mods else { return "安装此版本" }
        return switch selectedExperienceMode {
        case .beginner:
            "安装此版本及必需前置"
        case .normal:
            autoInstallRequiredMods ? "安装此版本及必需前置" : "仅安装此版本"
        case .expert:
            "仅安装此版本"
        }
    }

    var body: some View {
        Group {
            if let plan {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 16) {
                        RemoteImageIconView(
                            url: plan.project.iconURL,
                            systemImage: plan.kind.systemImage,
                            tint: .green,
                            padding: 13
                        )
                        .frame(width: 64, height: 64)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 13))
                        .clipShape(RoundedRectangle(cornerRadius: 13))

                        VStack(alignment: .leading, spacing: 5) {
                            Text(plan.project.title)
                                .font(.title2.weight(.semibold))
                            Text(plan.project.description)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text("目标：\(instance.name) · MC \(instance.versionID) · \(instance.loader.title)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(22)

                    Divider()

                    Form {
                        Section("选择\(plan.kind.title)版本") {
                            Picker(
                                "兼容版本",
                                selection: Binding(
                                    get: { plan.selectedVersionID },
                                    set: { versionID in
                                        Task {
                                            await store.showModrinthDetails(
                                                plan.kind,
                                                plan.project,
                                                for: instance,
                                                selectedVersionID: versionID
                                            )
                                        }
                                    }
                                )
                            ) {
                                ForEach(plan.versions) { version in
                                    Text("\(version.versionNumber) — \(version.name)")
                                        .tag(version.id)
                                }
                            }
                            .disabled(store.isLoadingModDetails)

                            if let selectedVersion = plan.versions.first(where: { $0.id == plan.selectedVersionID }) {
                                LabeledContent("版本名称", value: selectedVersion.name)
                                LabeledContent("版本号", value: selectedVersion.versionNumber)
                                LabeledContent(
                                    "支持 Minecraft",
                                    value: selectedVersion.supportedMinecraftVersionsText
                                )
                                if plan.kind == .mods {
                                    LabeledContent("加载器", value: selectedVersion.loadersText)
                                }
                                if let fileName = selectedVersion.primaryFileName {
                                    LabeledContent("文件", value: fileName)
                                }
                            }
                        }

                        if plan.kind == .mods {
                            Section("必需前置 Mod（\(plan.requiredDependencies.count)）") {
                                if plan.requiredDependencies.isEmpty {
                                    Text("此版本没有声明必需前置。")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(plan.requiredDependencies) { dependency in
                                        HStack(spacing: 10) {
                                            RemoteImageIconView(
                                                url: dependency.iconURL,
                                                systemImage: "puzzlepiece.extension",
                                                tint: .secondary,
                                                padding: 5
                                            )
                                            .frame(width: 30, height: 30)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(dependency.title)
                                                    .font(.body.weight(.medium))
                                                Text("\(dependency.versionNumber) · \(dependency.versionName)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .lineLimit(1)
                                            }
                                            .padding(.leading, CGFloat(dependency.depth) * 14)
                                            Spacer()
                                            Link(destination: dependency.projectURL) {
                                                Label("下载页", systemImage: "arrow.up.right.square")
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            Section("安装位置") {
                                Text("\(plan.kind.title)将安装到“\(instance.name)”对应的 \(plan.kind == .resourcePacks ? "resourcepacks" : "shaderpacks") 目录。")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .formStyle(.grouped)
                    .overlay {
                        if store.isLoadingModDetails {
                            ProgressView("正在读取版本与前置信息…")
                                .padding(18)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    Divider()
                    HStack {
                        Text(plan.kind == .mods ? selectedExperienceMode.detail : plan.kind.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer()
                        Button("取消") { dismiss() }
                        Button(installButtonTitle) {
                            dismiss()
                            Task {
                                await store.installModrinthContent(
                                    plan.kind,
                                    plan.project,
                                    for: instance,
                                    specificVersionID: plan.selectedVersionID
                                )
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(store.isLoadingModDetails)
                    }
                    .padding(16)
                }
            } else {
                ProgressView("正在读取 Modrinth 版本…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 780, height: 680)
    }
}
