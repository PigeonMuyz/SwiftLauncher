import SwiftUI

struct SidebarView: View {
    @Bindable var store: LauncherStore
    @ViewState private var isShowingInstancePicker = false
    @ViewState private var isShowingAccountPicker = false
    @ViewState private var showingInstanceManagement = false
    @AppStorage("instanceDisplayTemplate") private var instanceDisplayTemplate = "${mc_version} · ${mod_loader}"

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // 上半部分：固定导航 + 动态资源管理
                List(selection: $store.selection) {
                    Label(AppSection.downloads.title, systemImage: AppSection.downloads.systemImage)
                        .tag(AppSection.downloads)
                    Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage)
                        .tag(AppSection.settings)

                    if let instance = store.selectedInstance {
                        Section {
                            // 模组管理（仅非原版）
                            if instance.loader != .vanilla {
                                Label(AppSection.mods.title, systemImage: AppSection.mods.systemImage)
                                    .tag(AppSection.mods)
                            }

                            // 资源包（所有实例）
                            Label(AppSection.resourcePacks.title, systemImage: AppSection.resourcePacks.systemImage)
                                .tag(AppSection.resourcePacks)

                            // 光影包（仅支持光影的实例）
                            let instanceMods = store.mods[instance.id] ?? []
                            let hasShaders = instance.hasShaderSupport(mods: instanceMods)

                            if hasShaders {
                                Label(AppSection.shaders.title, systemImage: AppSection.shaders.systemImage)
                                    .tag(AppSection.shaders)
                            }
                        } header: {
                            Text("当前实例")
                                .font(.caption2)
                        }
                        .task(id: instance.id) {
                            // 确保加载模组数据
                            await store.loadMods(for: instance)
                        }
                    }
                }
                .listStyle(.sidebar)

                SidebarBottomPanel(
                    store: store,
                    width: geometry.size.width - 20,
                    displayTemplate: instanceDisplayTemplate,
                    isShowingInstancePicker: $isShowingInstancePicker,
                    isShowingAccountPicker: $isShowingAccountPicker,
                    showingAccountManagement: $store.isPresentingAccountManagement,
                    showingInstanceManagement: $showingInstanceManagement
                )
            }
        }
        .navigationTitle("")
        .sheet(isPresented: $store.isPresentingAccountManagement) {
            AccountsView(store: store)
                .frame(width: 680, height: 520)
        }
        .sheet(isPresented: $showingInstanceManagement) {
            InstanceManagementSheet(store: store)
                .frame(width: 720, height: 540)
        }
    }

}
