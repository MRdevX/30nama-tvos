// Draws the layered tvOS app icon and the Top Shelf images into the asset catalog.
// Run from the project root:  swift Tools/make-icons.swift
import AppKit
import CoreText

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let catalog = root.appendingPathComponent("30nama/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets")
CTFontManagerRegisterFontsForURL(root.appendingPathComponent("30nama/Resources/Fonts/Vazirmatn-ExtraBold.ttf") as CFURL, .process, nil)

let accent = NSColor(srgbRed: 0xF0 / 255, green: 0x45 / 255, blue: 0x4A / 255, alpha: 1)
let ink = NSColor(srgbRed: 0xF4 / 255, green: 0xF1 / 255, blue: 0xEA / 255, alpha: 1)
let bgTop = NSColor(srgbRed: 0x16 / 255, green: 0x19 / 255, blue: 0x22 / 255, alpha: 1)
let bgBottom = NSColor(srgbRed: 0x07 / 255, green: 0x08 / 255, blue: 0x0B / 255, alpha: 1)

enum Layer { case back, middle, front, flat }

func render(_ width: Int, _ height: Int, _ layer: Layer) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let w = CGFloat(width), h = CGFloat(height)
    let rect = CGRect(x: 0, y: 0, width: w, height: h)

    if layer == .back || layer == .flat {
        NSGradient(starting: bgBottom, ending: bgTop)!.draw(in: rect, angle: 90)
        // Projector-lamp bloom behind the wordmark.
        let bloom = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [accent.withAlphaComponent(0.42).cgColor, accent.withAlphaComponent(0).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(bloom, startCenter: CGPoint(x: w / 2, y: h * 0.5), startRadius: 0, endCenter: CGPoint(x: w / 2, y: h * 0.5), endRadius: h * 0.78, options: [])
    }
    let size = h * 0.30
    let font = NSFont(name: "Vazirmatn-ExtraBold", size: size) ?? .systemFont(ofSize: size, weight: .heavy)
    let text = NSMutableAttributedString(string: "30", attributes: [.font: font, .foregroundColor: accent])
    text.append(NSAttributedString(string: "nama", attributes: [.font: font, .foregroundColor: ink]))
    let bounds = text.boundingRect(with: rect.size, options: [.usesLineFragmentOrigin])
    let origin = CGPoint(x: (w - bounds.width) / 2, y: (h - bounds.height) / 2 + h * 0.03)
    if layer == .front || layer == .flat {
        text.draw(at: origin)
    }
    if layer == .middle || layer == .flat {
        accent.setFill()
        let lineWidth = bounds.width * 0.42
        CGRect(x: (w - lineWidth) / 2, y: origin.y - h * 0.045, width: lineWidth, height: max(2, h * 0.012)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func write(_ data: Data, _ path: String) {
    let url = catalog.appendingPathComponent(path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! data.write(to: url)
}

func json(_ object: Any, _ path: String) {
    let url = catalog.appendingPathComponent(path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]).write(to: url)
}

let info: [String: Any] = ["author": "xcode", "version": 1]

/// A layered icon: `scales` maps a scale ("1x") to pixel dimensions.
func imageStack(_ name: String, scales: [(String, Int, Int)]) {
    let layers: [(String, Layer)] = [("Front", .front), ("Middle", .middle), ("Back", .back)]
    json(["info": info, "layers": layers.map { ["filename": "\($0.0).imagestacklayer"] }], "\(name).imagestack/Contents.json")
    for (layerName, layer) in layers {
        let base = "\(name).imagestack/\(layerName).imagestacklayer"
        json(["info": info], "\(base)/Contents.json")
        var images: [[String: String]] = []
        for (scale, w, h) in scales {
            let file = "\(layerName.lowercased())@\(scale).png"
            write(render(w, h, layer), "\(base)/Content.imageset/\(file)")
            images.append(["filename": file, "idiom": "tv", "scale": scale])
        }
        json(["images": images, "info": info], "\(base)/Content.imageset/Contents.json")
    }
}

func imageSet(_ name: String, scales: [(String, Int, Int)]) {
    var images: [[String: String]] = []
    for (scale, w, h) in scales {
        let file = "image@\(scale).png"
        write(render(w, h, .flat), "\(name).imageset/\(file)")
        images.append(["filename": file, "idiom": "tv", "scale": scale])
    }
    json(["images": images, "info": info], "\(name).imageset/Contents.json")
}

imageStack("App Icon", scales: [("1x", 400, 240), ("2x", 800, 480)])
imageStack("App Icon - App Store", scales: [("1x", 1280, 768)])
imageSet("Top Shelf Image", scales: [("1x", 1920, 720), ("2x", 3840, 1440)])
imageSet("Top Shelf Image Wide", scales: [("1x", 2320, 720), ("2x", 4640, 1440)])
json([
    "assets": [
        ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
        ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
        ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
        ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
    ],
    "info": info,
], "Contents.json")
print("Wrote \(catalog.path)")
