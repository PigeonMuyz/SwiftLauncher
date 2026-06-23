import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 4 else {
    fatalError("usage: compose_qa reference.png implementation.png output.png")
}

func load(_ path: String) -> CGImage {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("cannot read \(path)")
    }
    return image
}

let reference = load(CommandLine.arguments[1])
let implementation = load(CommandLine.arguments[2])
let targetHeight = 1024
let referenceWidth = Int((Double(reference.width) / Double(reference.height) * Double(targetHeight)).rounded())
let implementationWidth = Int((Double(implementation.width) / Double(implementation.height) * Double(targetHeight)).rounded())
let gap = 24
let width = referenceWidth + implementationWidth + gap
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: width,
    height: targetHeight,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("cannot create context") }

context.setFillColor(CGColor(gray: 0.08, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: width, height: targetHeight))
context.interpolationQuality = .high
context.draw(reference, in: CGRect(x: 0, y: 0, width: referenceWidth, height: targetHeight))
context.draw(
    implementation,
    in: CGRect(x: referenceWidth + gap, y: 0, width: implementationWidth, height: targetHeight)
)

guard let output = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: CommandLine.arguments[3]) as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      ) else { fatalError("cannot create output") }
CGImageDestinationAddImage(destination, output, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("cannot write output") }
