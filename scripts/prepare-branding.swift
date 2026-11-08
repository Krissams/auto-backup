// Package the supplied logo into native application resources; keep the original unchanged.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let resources = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let iconset = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
let fm = FileManager.default
try fm.createDirectory(at: resources, withIntermediateDirectories: true)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
let original = URL(fileURLWithPath: "Assets/AutoBackupLogo.png")
guard let source = CGImageSourceCreateWithURL(original as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let symbol = image.cropping(to: CGRect(x: 308, y: 211, width: 636, height: 636)) else {
    fatalError("Cannot load the supplied Auto Backup logo")
}
func savePNG(_ image: CGImage, to url: URL) {
    guard let writer = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Cannot create \(url.path)")
    }
    CGImageDestinationAddImage(writer, image, nil)
    precondition(CGImageDestinationFinalize(writer), "Cannot save logo resource")
}
func render(size: Int, inset: CGFloat) -> CGImage {
    let side = CGFloat(size)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    let bounds = CGRect(x: side * inset, y: side * inset, width: side * (1 - inset * 2), height: side * (1 - inset * 2))
    // Match the supplied symbol's rounded silhouette instead of including its white page margin.
    context.addPath(CGPath(roundedRect: bounds, cornerWidth: bounds.width * 0.275,
                           cornerHeight: bounds.height * 0.275, transform: nil))
    context.clip()
    context.draw(symbol, in: bounds)
    return context.makeImage()!
}
savePNG(render(size: 636, inset: 0), to: resources.appendingPathComponent("AutoBackupMark.png"))
try Data(contentsOf: original).write(to: resources.appendingPathComponent("AutoBackupLogo.png"))
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let filename = "icon_\(size)x\(size)\(suffix).png"
        savePNG(render(size: size * scale, inset: 0.09), to: iconset.appendingPathComponent(filename))
    }
}
