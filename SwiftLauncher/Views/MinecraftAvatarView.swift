import AppKit
import SwiftUI

struct MinecraftAvatarView: View {
    let account: PlayerAccount?
    var size: CGFloat = 32

    @ViewState private var renderedImage: NSImage?

    private var cacheKey: String {
        guard let account else { return "empty" }
        return account.skinURL?.absoluteString ?? "offline:\(account.offlineSkinName)"
    }

    var body: some View {
        Group {
            if let renderedImage {
                Image(nsImage: renderedImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(nsImage: Self.generatedAvatar(named: account?.offlineSkinName ?? "steve"))
                    .interpolation(.none)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: size, height: size)
        .background(.quaternary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .stroke(.separator.opacity(0.55), lineWidth: 0.5)
        }
        .task(id: cacheKey) {
            await loadAvatar()
        }
    }

    @MainActor
    private func loadAvatar() async {
        guard let account else {
            renderedImage = nil
            return
        }
        if let skinURL = account.skinURL {
            let key = skinURL.absoluteString as NSString
            if let cached = Self.imageCache.object(forKey: key) {
                renderedImage = cached
                return
            }
            let diskURL = Self.diskCacheURL(for: skinURL)
            if let image = NSImage(contentsOf: diskURL) {
                Self.imageCache.setObject(image, forKey: key)
                renderedImage = image
                return
            }
            do {
                let (data, _) = try await URLSession.shared.data(from: skinURL)
                if let image = Self.renderSkinHead(from: data) {
                    Self.imageCache.setObject(image, forKey: key)
                    Self.store(image, at: diskURL)
                    renderedImage = image
                    return
                }
            } catch {
                renderedImage = Self.generatedAvatar(named: account.offlineSkinName)
                return
            }
        }

        let key = "offline:\(account.offlineSkinName)" as NSString
        if let cached = Self.imageCache.object(forKey: key) {
            renderedImage = cached
        } else {
            let image = Self.generatedAvatar(named: account.offlineSkinName)
            Self.imageCache.setObject(image, forKey: key)
            renderedImage = image
        }
    }

    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        cache.totalCostLimit = 4 * 1024 * 1024
        return cache
    }()

    private static func diskCacheURL(for skinURL: URL) -> URL {
        LauncherFileSystem.shared.avatarCacheRoot
            .appendingPathComponent(Hashing.sha256(Data(skinURL.absoluteString.utf8)))
            .appendingPathExtension("png")
    }

    private static func store(_ image: NSImage, at url: URL) {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            guard let data = pngData(from: image) else { return }
            try data.write(to: url, options: [.atomic])
        } catch {
            return
        }
    }

    private static func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return representation.representation(using: .png, properties: [:])
    }

    private static func renderSkinHead(from data: Data) -> NSImage? {
        guard let source = NSImage(data: data),
              let cgImage = source.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cgImage.width >= 64,
              cgImage.height >= 64 else {
            return nil
        }

        let scale = CGFloat(cgImage.width) / 64
        let headRect = CGRect(x: 8 * scale, y: 8 * scale, width: 8 * scale, height: 8 * scale)
        let layerRect = CGRect(x: 40 * scale, y: 8 * scale, width: 8 * scale, height: 8 * scale)
        guard let head = cgImage.cropping(to: headRect) else { return nil }
        let layer = cgImage.cropping(to: layerRect)

        let target = NSImage(size: NSSize(width: 64, height: 64))
        target.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        NSImage(cgImage: head, size: NSSize(width: 8, height: 8)).draw(
            in: NSRect(x: 0, y: 0, width: 64, height: 64),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        if let layer, hasVisiblePixels(layer) {
            NSImage(cgImage: layer, size: NSSize(width: 8, height: 8)).draw(
                in: NSRect(x: 0, y: 0, width: 64, height: 64),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }
        target.unlockFocus()
        return target
    }

    private static func hasVisiblePixels(_ image: CGImage) -> Bool {
        guard let provider = image.dataProvider,
              let data = provider.data,
              let bytes = CFDataGetBytePtr(data) else { return true }
        let bytesPerPixel = max(image.bitsPerPixel / 8, 1)
        guard bytesPerPixel >= 4 else { return true }
        for y in 0..<image.height {
            for x in 0..<image.width {
                let alphaIndex = y * image.bytesPerRow + x * bytesPerPixel + 3
                if bytes[alphaIndex] > 0 { return true }
            }
        }
        return false
    }

    private static func generatedAvatar(named name: String) -> NSImage {
        let palette = GeneratedAvatarPalette.palette(for: name)
        let target = NSImage(size: NSSize(width: 64, height: 64))
        target.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()

        func fill(_ color: NSColor, _ x: Int, _ y: Int, _ width: Int = 1, _ height: Int = 1) {
            color.setFill()
            NSRect(x: x * 8, y: (7 - y - height + 1) * 8, width: width * 8, height: height * 8).fill()
        }

        for y in 0..<8 {
            for x in 0..<8 {
                fill(palette.skin, x, y)
            }
        }
        for x in 0..<8 { fill(palette.hair, x, 0) }
        for x in 0..<8 where x != 3 && x != 4 { fill(palette.hair, x, 1) }
        fill(palette.hair, 0, 2)
        fill(palette.hair, 7, 2)
        fill(palette.eye, 2, 3)
        fill(palette.eye, 5, 3)
        fill(palette.mouth, 3, 5, 2)
        fill(palette.shadow, 1, 6, 6)
        target.unlockFocus()
        return target
    }
}

private struct GeneratedAvatarPalette {
    let skin: NSColor
    let hair: NSColor
    let eye: NSColor
    let mouth: NSColor
    let shadow: NSColor

    static func palette(for name: String) -> Self {
        switch name {
        case "alex":
            Self(skin: .init(red: 0.89, green: 0.64, blue: 0.45, alpha: 1), hair: .init(red: 0.73, green: 0.33, blue: 0.17, alpha: 1), eye: .init(red: 0.22, green: 0.43, blue: 0.58, alpha: 1), mouth: .init(red: 0.54, green: 0.24, blue: 0.22, alpha: 1), shadow: .init(red: 0.78, green: 0.45, blue: 0.34, alpha: 1))
        case "ari":
            Self(skin: .init(red: 0.68, green: 0.44, blue: 0.31, alpha: 1), hair: .init(red: 0.14, green: 0.09, blue: 0.07, alpha: 1), eye: .init(red: 0.22, green: 0.55, blue: 0.36, alpha: 1), mouth: .init(red: 0.42, green: 0.17, blue: 0.15, alpha: 1), shadow: .init(red: 0.50, green: 0.30, blue: 0.22, alpha: 1))
        case "efe":
            Self(skin: .init(red: 0.55, green: 0.36, blue: 0.25, alpha: 1), hair: .init(red: 0.08, green: 0.07, blue: 0.06, alpha: 1), eye: .init(red: 0.13, green: 0.28, blue: 0.48, alpha: 1), mouth: .init(red: 0.35, green: 0.14, blue: 0.12, alpha: 1), shadow: .init(red: 0.42, green: 0.26, blue: 0.18, alpha: 1))
        case "kai":
            Self(skin: .init(red: 0.86, green: 0.56, blue: 0.36, alpha: 1), hair: .init(red: 0.21, green: 0.13, blue: 0.08, alpha: 1), eye: .init(red: 0.18, green: 0.46, blue: 0.56, alpha: 1), mouth: .init(red: 0.52, green: 0.23, blue: 0.18, alpha: 1), shadow: .init(red: 0.70, green: 0.39, blue: 0.27, alpha: 1))
        case "makena":
            Self(skin: .init(red: 0.44, green: 0.29, blue: 0.20, alpha: 1), hair: .init(red: 0.06, green: 0.05, blue: 0.05, alpha: 1), eye: .init(red: 0.28, green: 0.58, blue: 0.42, alpha: 1), mouth: .init(red: 0.30, green: 0.12, blue: 0.11, alpha: 1), shadow: .init(red: 0.34, green: 0.21, blue: 0.15, alpha: 1))
        case "noor":
            Self(skin: .init(red: 0.76, green: 0.50, blue: 0.34, alpha: 1), hair: .init(red: 0.12, green: 0.08, blue: 0.06, alpha: 1), eye: .init(red: 0.17, green: 0.35, blue: 0.55, alpha: 1), mouth: .init(red: 0.45, green: 0.18, blue: 0.16, alpha: 1), shadow: .init(red: 0.58, green: 0.34, blue: 0.24, alpha: 1))
        case "sunny":
            Self(skin: .init(red: 0.88, green: 0.66, blue: 0.48, alpha: 1), hair: .init(red: 0.93, green: 0.70, blue: 0.24, alpha: 1), eye: .init(red: 0.25, green: 0.45, blue: 0.64, alpha: 1), mouth: .init(red: 0.56, green: 0.25, blue: 0.22, alpha: 1), shadow: .init(red: 0.78, green: 0.48, blue: 0.35, alpha: 1))
        case "zuri":
            Self(skin: .init(red: 0.50, green: 0.33, blue: 0.24, alpha: 1), hair: .init(red: 0.11, green: 0.07, blue: 0.05, alpha: 1), eye: .init(red: 0.16, green: 0.44, blue: 0.40, alpha: 1), mouth: .init(red: 0.32, green: 0.13, blue: 0.12, alpha: 1), shadow: .init(red: 0.39, green: 0.24, blue: 0.17, alpha: 1))
        default:
            Self(skin: .init(red: 0.80, green: 0.55, blue: 0.36, alpha: 1), hair: .init(red: 0.24, green: 0.14, blue: 0.08, alpha: 1), eye: .init(red: 0.12, green: 0.26, blue: 0.44, alpha: 1), mouth: .init(red: 0.45, green: 0.19, blue: 0.16, alpha: 1), shadow: .init(red: 0.65, green: 0.37, blue: 0.26, alpha: 1))
        }
    }
}
