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
                    Section("下载") {
                        sidebarRow(.downloadVersions)
                        sidebarRow(.downloadTasks)
                    }

                    Section("资源库") {
                        sidebarRow(.libraryMods)
                        sidebarRow(.libraryShaders)
                        sidebarRow(.libraryResourcePacks)
                        sidebarRow(.libraryDataPacks)
                        sidebarRow(.libraryModpacks)
                    }

                    Section("当前实例") {
                        sidebarRow(.instanceResources)
                            .disabled(store.selectedInstance == nil)
                        sidebarRow(.instanceSettings)
                            .disabled(store.selectedInstance == nil)
                    }

                    Section {
                        sidebarRow(.settings)
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

    private func sidebarRow(_ section: AppSection) -> some View {
        Label(section.title, systemImage: section.systemImage)
            .tag(section)
    }

}
