import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ResourceLibraryView: View {
    @Bindable var store: LauncherStore
    let kind: ResourceLibraryKind

    @ViewState private var query = ""
    @ViewState private var isImporting = false
    @ViewState private var filtersCurrentInstanceVersion = false

    private var searchInstance: LauncherInstance? {
        store.selectedInstance ?? store.instances.first
    }

    private var installPlanInstance: LauncherInstance? {
        guard let id = store.selectedDownloadInstanceID else { return searchInstance }
        return store.instances.first { $0.id == id } ?? searchInstance
    }

    var body: some View {
        Group {
            if let instance = searchInstance {
                ModrinthRemoteSearchPanel(
                    store: store,
                    kind: kind.modrinthKind,
                    instance: instance,
                    query: $query,
                    filtersCurrentInstanceVersion: $filtersCurrentInstanceVersion,
                    allowsTargetSelectionOnInstall: true
                )
            } else {
                noInstanceView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if kind.modrinthKind.supportsCurrentInstanceVersionFilter, let instance = searchInstance {
                    Button {
                        filtersCurrentInstanceVersion.toggle()
                    } label: {
                        Label(
                            filtersCurrentInstanceVersion
                                ? "已按 \(instance.versionID) 过滤"
                                : "按当前实例版本过滤",
                            systemImage: "personalhotspot"
                        )
                    }
                    .foregroundStyle(filtersCurrentInstanceVersion ? Color.accentColor : .secondary)
                    .help(
                        filtersCurrentInstanceVersion
                            ? "搜索结果仅显示适配 Minecraft \(instance.versionID) 的\(kind.title)"
                            : "当前搜索不限制 Minecraft 版本"
                    )
                }

                Button {
                    beginImport()
                } label: {
                    Label("导入\(kind.title)", systemImage: "square.and.arrow.down")
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: kind.allowedContentTypes,
            allowsMultipleSelection: kind.allowsMultipleImport
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { await importFiles(urls) }
        }
        .sheet(
            isPresented: Binding(
                get: { store.modInstallPlan?.kind == kind.modrinthKind && installPlanInstance != nil },
                set: { if !$0 { store.modInstallPlan = nil } }
            )
        ) {
            if let instance = installPlanInstance {
                ModrinthDetailsSheet(store: store, instance: instance)
            }
        }
    }

    private var noInstanceView: some View {
        ContentUnavailableView {
            Label("还没有实例", systemImage: "shippingbox")
        } description: {
            Text("资源库需要至少一个实例来确定 Minecraft 版本。")
        } actions: {
            Button("下载游戏版本") {
                store.selection = .downloadVersions
            }
        }
    }

    private func beginImport() {
        switch kind {
        case .dataPacks:
            store.errorMessage = "数据包需要选择具体世界，后续会和世界管理一起接入。"
            store.errorHelpURL = nil
        default:
            isImporting = true
        }
    }

    private func importFiles(_ urls: [URL]) async {
        switch kind {
        case .mods:
            guard let instance = store.selectedInstance, instance.loader != .vanilla else {
                store.errorMessage = "导入模组前，请先选择 Fabric、Quilt、Forge 或 NeoForge 实例。"
                store.errorHelpURL = nil
                return
            }
            await store.importMods(urls, for: instance)
        case .resourcePacks:
            guard let instance = store.selectedInstance else {
                store.errorMessage = "请先选择一个目标实例。"
                store.errorHelpURL = nil
                return
            }
            await store.importManagedContent(urls, kind: .resourcePacks, for: instance)
        case .shaders:
            guard let instance = store.selectedInstance else {
                store.errorMessage = "请先选择一个目标实例。"
                store.errorHelpURL = nil
                return
            }
            await store.importManagedContent(urls, kind: .shaderPacks, for: instance)
        case .dataPacks:
            break
        case .modpacks:
            guard let url = urls.first else { return }
            await store.importModpack(from: url)
        }
    }
}

enum ResourceLibraryKind: String, CaseIterable, Identifiable {
    case mods
    case shaders
    case resourcePacks
    case dataPacks
    case modpacks

    var id: Self { self }

    var title: String {
        switch self {
        case .mods: "模组"
        case .shaders: "光影包"
        case .resourcePacks: "资源包"
        case .dataPacks: "数据包"
        case .modpacks: "整合包"
        }
    }

    var modrinthKind: ModrinthContentKind {
        switch self {
        case .mods: .mods
        case .shaders: .shaderPacks
        case .resourcePacks: .resourcePacks
        case .dataPacks: .dataPacks
        case .modpacks: .modpacks
        }
    }

    var allowedContentTypes: [UTType] {
        switch self {
        case .mods:
            [UTType(filenameExtension: "jar") ?? .data]
        case .shaders, .resourcePacks:
            [.zip, .folder]
        case .dataPacks:
            [.zip, .folder]
        case .modpacks:
            [UTType(filenameExtension: "mrpack") ?? .zip, .zip]
        }
    }

    var allowsMultipleImport: Bool {
        switch self {
        case .modpacks:
            false
        default:
            true
        }
    }
}
