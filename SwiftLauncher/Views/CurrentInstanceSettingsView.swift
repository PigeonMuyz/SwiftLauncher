import SwiftUI

struct CurrentInstanceSettingsView: View {
    @Bindable var store: LauncherStore

    var body: some View {
        Group {
            if let instance = store.selectedInstance {
                InstanceDetailView(store: store, instance: instance)
                    .id(instance.id)
            } else {
                ContentUnavailableView {
                    Label("未选择实例", systemImage: "shippingbox")
                } description: {
                    Text("请先在左下角选择一个游戏实例。")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
