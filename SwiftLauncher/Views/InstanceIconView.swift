import SwiftUI

struct InstanceIconView: View {
    let store: LauncherStore
    let instance: LauncherInstance
    var size: CGFloat = 42
    var tint: Color = .green

    var body: some View {
        Group {
            if let image = store.instanceIconImage(for: instance) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                VoxelGrassBlock(loader: instance.loader, tint: tint)
                    .padding(size * 0.12)
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(.separator.opacity(0.55), lineWidth: 0.5)
        }
    }
}

private struct VoxelGrassBlock: View {
    let loader: ModLoader
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            ZStack(alignment: .bottomTrailing) {
                Canvas { context, size in
                    let top = Path { path in
                        path.move(to: CGPoint(x: size.width * 0.5, y: size.height * 0.03))
                        path.addLine(to: CGPoint(x: size.width * 0.94, y: size.height * 0.27))
                        path.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 0.52))
                        path.addLine(to: CGPoint(x: size.width * 0.06, y: size.height * 0.27))
                        path.closeSubpath()
                    }
                    let left = Path { path in
                        path.move(to: CGPoint(x: size.width * 0.06, y: size.height * 0.27))
                        path.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 0.52))
                        path.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 0.96))
                        path.addLine(to: CGPoint(x: size.width * 0.06, y: size.height * 0.70))
                        path.closeSubpath()
                    }
                    let right = Path { path in
                        path.move(to: CGPoint(x: size.width * 0.94, y: size.height * 0.27))
                        path.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 0.52))
                        path.addLine(to: CGPoint(x: size.width * 0.5, y: size.height * 0.96))
                        path.addLine(to: CGPoint(x: size.width * 0.94, y: size.height * 0.70))
                        path.closeSubpath()
                    }
                    context.fill(top, with: .linearGradient(
                        Gradient(colors: [Color(red: 0.45, green: 0.75, blue: 0.25), Color(red: 0.22, green: 0.52, blue: 0.16)]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: size.width, y: size.height)
                    ))
                    context.fill(left, with: .color(Color(red: 0.47, green: 0.30, blue: 0.18)))
                    context.fill(right, with: .color(Color(red: 0.34, green: 0.21, blue: 0.13)))
                    context.stroke(top, with: .color(.white.opacity(0.28)), lineWidth: 0.7)
                    context.stroke(left, with: .color(.black.opacity(0.28)), lineWidth: 0.7)
                    context.stroke(right, with: .color(.black.opacity(0.35)), lineWidth: 0.7)
                }

                if loader != .vanilla {
                    Image(systemName: loader.badgeSystemImage)
                        .font(.system(size: min(width, height) * 0.20, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: width * 0.34, height: height * 0.34)
                        .background(loader.badgeColor, in: Circle())
                        .overlay { Circle().stroke(.white.opacity(0.7), lineWidth: 0.7) }
                }
            }
        }
    }
}

private extension ModLoader {
    var badgeSystemImage: String {
        switch self {
        case .vanilla: "leaf.fill"
        case .fabric: "square.stack.3d.up.fill"
        case .quilt: "square.grid.3x3.fill"
        case .forge: "hammer.fill"
        case .neoForge: "sparkles"
        }
    }

    var badgeColor: Color {
        switch self {
        case .vanilla: .green
        case .fabric: .brown
        case .quilt: .purple
        case .forge: .orange
        case .neoForge: .cyan
        }
    }
}
