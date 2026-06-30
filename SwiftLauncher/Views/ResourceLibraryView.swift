import SwiftUI

struct ResourceLibraryView: View {
    @Bindable var store: LauncherStore
    let kind: ResourceLibraryKind

    @ViewState private var query = ""
    @ViewState private var isManagingLoader = false

    var body: some View {
        Group {
            if let modrinthKind = kind.modrinthKind {
                if let instance = store.selectedInstance {
                    if modrinthKind == .mods, instance.loader == .vanilla {
                        loaderRequiredView(for: instance)
                    } else {
                        ModrinthRemoteSearchPanel(
                            store: store,
                            kind: modrinthKind,
                            instance: instance,
                            query: $query
                        )
                    }
                } else {
                    noInstanceView
                }
            } else {
                unsupportedView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(
            isPresented: Binding(
                get: {
                    guard let modrinthKind = kind.modrinthKind else { return false }
                    return store.modInstallPlan?.kind == modrinthKind && store.selectedInstance != nil
                },
                set: { if !$0 { store.modInstallPlan = nil } }
            )
        ) {
            if let instance = store.selectedInstance {
                ModrinthDetailsSheet(store: store, instance: instance)
            }
        }
        .sheet(isPresented: $isManagingLoader) {
            if let instance = store.selectedInstance {
                InstanceLoaderSheet(store: store, instance: instance)
            }
        }
    }

    private var noInstanceView: some View {
        ContentUnavailableView {
            Label("未选择实例", systemImage: "shippingbox")
        } description: {
            Text("资源库会按当前实例的 Minecraft 版本和加载器过滤结果。")
        }
    }

    private var unsupportedView: some View {
        ContentUnavailableView {
            Label("\(kind.title)即将接入", systemImage: kind.systemImage)
        } description: {
            Text(kind.unsupportedReason)
        }
    }

    private func loaderRequiredView(for instance: LauncherInstance) -> some View {
        ContentUnavailableView {
            Label("当前实例未安装模组加载器", systemImage: "puzzlepiece.extension")
        } description: {
            Text("“\(instance.name)” 是原版实例，安装模组前需要先安装 Fabric、Quilt、Forge 或 NeoForge。")
        } actions: {
            Button {
                isManagingLoader = true
            } label: {
                Label("安装加载器", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
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

    var systemImage: String {
        switch self {
        case .mods: "puzzlepiece.extension"
        case .shaders: "sparkles"
        case .resourcePacks: "photo.stack"
        case .dataPacks: "doc.text"
        case .modpacks: "archivebox"
        }
    }

    var modrinthKind: ModrinthContentKind? {
        switch self {
        case .mods: .mods
        case .shaders: .shaderPacks
        case .resourcePacks: .resourcePacks
        case .dataPacks, .modpacks: nil
        }
    }

    var unsupportedReason: String {
        switch self {
        case .mods, .shaders, .resourcePacks:
            ""
        case .dataPacks:
            "数据包需要选择具体存档世界，后续会和世界管理一起接入。"
        case .modpacks:
            "整合包会创建或导入完整实例，后续会接到新的整合包下载流程。"
        }
    }
}
