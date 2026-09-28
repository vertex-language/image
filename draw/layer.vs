package draw

import "math"

/// Pixels painted apart from a canvas and then put back onto it, for
/// effects that apply to what's drawn as a whole, like a blur. A layer
/// covers a rectangle of the canvas it was made for, and its Canvas
/// takes the same coordinates, so drawing into it needs no offset.
public struct Layer {
    let pixels: UnsafeMutablePointer<uint32>
    public let Rect: IRect
    public var Canvas: Canvas

    /// A transparent layer over r, which must not be empty.
    public init(_ r: IRect) {
        Rect = r
        let count = int(r.Width) * int(r.Height)
        pixels = UnsafeMutablePointer<uint32>.allocate(capacity: count)
        var i = 0
        while i < count {
            (pixels + i).pointee = 0
            i += 1
        }
        // The canvas's origin sits where the rectangle's top left would
        // be, so it addresses the layer in the parent's coordinates; its
        // clip keeps every access inside the layer.
        let stride = r.Width * 4
        let bytes = UnsafeMutablePointer<uint8>(UnsafeMutableRawPointer(pixels))
        let origin = bytes + (-int(r.Y * stride + r.X * 4))
        Canvas = draw.Canvas(base: origin, width: r.Right, height: r.Bottom, stride: stride)
        Canvas.Clip = r
    }

    /// Gives the layer's memory back; it isn't used after.
    public func Free() {
        pixels.deallocate()
    }

    /// Blurs the layer as a Gaussian of standard deviation sigma pixels
    /// would, near enough: three box blurs each way.
    public func Blur(_ sigma: float32) {
        if sigma < 0.5 { return }
        let w = int(Rect.Width)
        let h = int(Rect.Height)
        // Box sizes whose three passes have the Gaussian's variance.
        let ideal = math.Sqrt(4 * sigma * sigma + 1)
        var radius = int((ideal - 1) / 2)
        if radius < 1 { radius = 1 }
        let longest = w > h ? w : h
        let line = UnsafeMutablePointer<uint32>.allocate(capacity: longest)
        var pass = 0
        while pass < 3 {
            var y = 0
            while y < h {
                blurLine(pixels + y * w, step: 1, count: w, radius: radius, scratch: line)
                y += 1
            }
            var x = 0
            while x < w {
                blurLine(pixels + x, step: w, count: h, radius: radius, scratch: line)
                x += 1
            }
            pass += 1
        }
        line.deallocate()
    }

    /// Paints the layer onto a canvas, over what's there, inside its clip.
    public func Composite(onto c: Canvas) {
        let area = Rect.Intersect(c.Clip)
        if area.IsEmpty { return }
        var y = area.Y
        while y < area.Bottom {
            var src = pixels + int((y - Rect.Y) * Rect.Width + (area.X - Rect.X))
            var dst = c.rowPointer(y) + int(area.X)
            var x = area.X
            while x < area.Right {
                let s = src.pointee
                let sa = s >> 24
                if sa == 255 {
                    dst.pointee = s
                } else if sa > 0 {
                    dst.pointee = s &+ scalePacked(dst.pointee, 255 - sa)
                }
                src = src + 1
                dst = dst + 1
                x += 1
            }
            y += 1
        }
    }
}

/// One box blur along a row or column of premultiplied pixels: each
/// becomes the mean of those within radius, the edges treated as
/// transparent.
func blurLine(_ p: UnsafeMutablePointer<uint32>, step: int, count: int, radius: int, scratch: UnsafeMutablePointer<uint32>) {
    var i = 0
    while i < count {
        (scratch + i).pointee = (p + i * step).pointee
        i += 1
    }
    let window = uint32(2 * radius + 1)
    var r: uint32 = 0
    var g: uint32 = 0
    var b: uint32 = 0
    var a: uint32 = 0
    // The window's sum starts over the first radius pixels.
    i = 0
    while i < radius && i < count {
        let v = (scratch + i).pointee
        r += v & 0xFF
        g += (v >> 8) & 0xFF
        b += (v >> 16) & 0xFF
        a += v >> 24
        i += 1
    }
    i = 0
    while i < count {
        let enter = i + radius
        if enter < count {
            let v = (scratch + enter).pointee
            r += v & 0xFF
            g += (v >> 8) & 0xFF
            b += (v >> 16) & 0xFF
            a += v >> 24
        }
        let leave = i - radius - 1
        if leave >= 0 {
            let v = (scratch + leave).pointee
            r -= v & 0xFF
            g -= (v >> 8) & 0xFF
            b -= (v >> 16) & 0xFF
            a -= v >> 24
        }
        let half = window / 2
        (p + i * step).pointee = ((r + half) / window) | (((g + half) / window) << 8) | (((b + half) / window) << 16) | (((a + half) / window) << 24)
        i += 1
    }
}
