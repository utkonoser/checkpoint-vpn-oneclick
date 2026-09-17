import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

let sadSrc = URL(fileURLWithPath: CommandLine.arguments[1])
let happySrc = URL(fileURLWithPath: CommandLine.arguments[2])
let outDir = URL(fileURLWithPath: CommandLine.arguments[3])

func cgImage(from url: URL) -> CGImage {
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}

func templateize(_ source: CGImage, pixels: Int) -> CGImage {
    let color = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: pixels * 4,
        space: color,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.clear(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    ctx.interpolationQuality = .high
    ctx.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let count = pixels * pixels
    let data = ctx.data!.bindMemory(to: UInt8.self, capacity: count * 4)
    for i in 0..<count {
        let r = Int(data[i * 4])
        let g = Int(data[i * 4 + 1])
        let b = Int(data[i * 4 + 2])
        let a = Int(data[i * 4 + 3])
        let lum = (r + g + b) / 3
        let dark = 255 - lum
        let outA = min(255, dark * a / 255)
        data[i * 4] = 0
        data[i * 4 + 1] = 0
        data[i * 4 + 2] = 0
        data[i * 4 + 3] = UInt8(outA)
    }
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func writeSet(name: String, source: CGImage) {
    let set = outDir.appendingPathComponent("\(name).imageset")
    writePNG(templateize(source, pixels: 22), to: set.appendingPathComponent("\(name).png"))
    writePNG(templateize(source, pixels: 44), to: set.appendingPathComponent("\(name)@2x.png"))
    let json = """
    {
      "images" : [
        { "filename" : "\(name).png", "idiom" : "mac", "scale" : "1x" },
        { "filename" : "\(name)@2x.png", "idiom" : "mac", "scale" : "2x" }
      ],
      "info" : { "author" : "xcode", "version" : 1 },
      "properties" : { "template-rendering-intent" : "template" }
    }
    """
    try! json.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

writeSet(name: "MenuBarDisconnected", source: cgImage(from: sadSrc))
writeSet(name: "MenuBarConnected", source: cgImage(from: happySrc))
print("wrote menu bar icons to \(outDir.path)")
