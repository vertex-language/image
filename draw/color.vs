package draw

import "math"

/// A color: red, green, blue and alpha, each 0 to 255, not premultiplied.
public struct Color: Equatable {
    public var R: uint8
    public var G: uint8
    public var B: uint8
    public var A: uint8

    public init(_ r: uint8, _ g: uint8, _ b: uint8, _ a: uint8 = 255) {
        R = r
        G = g
        B = b
        A = a
    }

    public static let transparent = Color(0, 0, 0, 0)
    public static let black = Color(0, 0, 0)
    public static let white = Color(255, 255, 255)

    public var IsOpaque: bool { return A == 255 }
    public var IsTransparent: bool { return A == 0 }

    /// The color with its alpha multiplied by a factor from 0 to 1.
    public func Faded(_ opacity: float32) -> Color {
        if opacity >= 1 { return self }
        if opacity <= 0 { return Color(R, G, B, 0) }
        return Color(R, G, B, uint8(float32(A) * opacity + 0.5))
    }

    /// The pixel the color is on a canvas: premultiplied, R in the low byte.
    public func Premultiplied() -> uint32 {
        if A == 255 {
            return uint32(R) | (uint32(G) << 8) | (uint32(B) << 16) | 0xFF000000
        }
        let a = uint32(A)
        let r = mul255(uint32(R), a)
        let g = mul255(uint32(G), a)
        let b = mul255(uint32(B), a)
        return r | (g << 8) | (b << 16) | (a << 24)
    }

}

/// x * y / 255, rounded, for x and y in 0...255.
func mul255(_ x: uint32, _ y: uint32) -> uint32 {
    let t = x * y + 128
    return (t + (t >> 8)) >> 8
}

