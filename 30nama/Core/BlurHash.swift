import Foundation

/// Decoder for BlurHash strings (https://blurha.sh), which the API sends as `image.poster.preview`.
/// Produces a tiny RGBA bitmap that is stretched as a placeholder until the real poster arrives.
enum BlurHash {
    private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")
    private static let digit: [Character: Int] = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($1, $0) })

    private static func decode83(_ s: Substring) -> Int? {
        var value = 0
        for c in s {
            guard let d = digit[c] else { return nil }
            value = value * 83 + d
        }
        return value
    }

    private static func linear(_ srgb: Int) -> Double {
        let v = Double(srgb) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func srgb(_ linear: Double) -> UInt8 {
        let v = max(0, min(1, linear))
        let s = v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
        return UInt8(max(0, min(255, (s * 255).rounded())))
    }

    private static func signedPow(_ v: Double, _ e: Double) -> Double {
        v < 0 ? -pow(-v, e) : pow(v, e)
    }

    /// The image's average colour (the hash's DC component), each channel 0...1 in sRGB.
    static func average(_ hash: String) -> (red: Double, green: Double, blue: Double)? {
        let chars = Substring(hash)
        guard chars.count >= 6, let v = decode83(chars.dropFirst(2).prefix(4)) else { return nil }
        return (Double(v >> 16) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }

    /// RGBA8 pixels, row-major, `width * height * 4` bytes. `nil` for a malformed hash.
    static func pixels(_ hash: String, width: Int, height: Int, punch: Double = 1) -> [UInt8]? {
        let chars = Substring(hash)
        guard chars.count >= 6, width > 0, height > 0,
              let sizeFlag = decode83(chars.prefix(1)) else { return nil }
        let numY = sizeFlag / 9 + 1, numX = sizeFlag % 9 + 1
        guard chars.count == 4 + 2 * numX * numY,
              let quantisedMax = decode83(chars.dropFirst(1).prefix(1)) else { return nil }
        let maxValue = Double(quantisedMax + 1) / 166 * punch

        var colors: [(Double, Double, Double)] = []
        colors.reserveCapacity(numX * numY)
        for i in 0..<(numX * numY) {
            if i == 0 {
                guard let v = decode83(chars.dropFirst(2).prefix(4)) else { return nil }
                colors.append((linear(v >> 16), linear((v >> 8) & 255), linear(v & 255)))
            } else {
                guard let v = decode83(chars.dropFirst(4 + i * 2).prefix(2)) else { return nil }
                func ac(_ q: Int) -> Double { signedPow((Double(q) - 9) / 9, 2) * maxValue }
                colors.append((ac(v / (19 * 19)), ac((v / 19) % 19), ac(v % 19)))
            }
        }

        var out = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                var r = 0.0, g = 0.0, b = 0.0
                for j in 0..<numY {
                    let by = cos(Double.pi * Double(y) * Double(j) / Double(height))
                    for i in 0..<numX {
                        let basis = cos(Double.pi * Double(x) * Double(i) / Double(width)) * by
                        let c = colors[i + j * numX]
                        r += c.0 * basis; g += c.1 * basis; b += c.2 * basis
                    }
                }
                let o = (y * width + x) * 4
                out[o] = srgb(r); out[o + 1] = srgb(g); out[o + 2] = srgb(b)
            }
        }
        return out
    }
}
