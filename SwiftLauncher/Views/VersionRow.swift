import SwiftUI

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
