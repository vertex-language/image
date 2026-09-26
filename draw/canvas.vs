package draw

/// An 8-bit coverage mask: a glyph, or any shape to paint in one color.
public struct Mask {
    public var Width: int32
    public var Height: int32
    public var Data: [uint8]

    public init(width: int32, height: int32, data: [uint8]) {
        Width = width
        Height = height
        Data = data
    }
}

/// Pixels of an image: premultiplied RGBA, red first, top row first.
public final class Image {
    public let Width: int32
    public let Height: int32
    public var Pixels: [uint8]

    public init(width: int32, height: int32, pixels: [uint8]) {
        Width = width
        Height = height
        Pixels = pixels
    }
}

/// Somewhere to draw: premultiplied RGBA8 pixels, red first, top row
/// first, which is what a window surface presents. A canvas borrows its
/// pixels for the length of one `WithCanvas`; everything drawn is kept to
/// its `Clip`, which starts as the whole surface.
public struct Canvas {
    let base: UnsafeMutablePointer<uint8>
    public let Width: int32
    public let Height: int32
    /// Bytes from one row to the next.
    public let Stride: int32
    public var Clip: IRect

    public init(base: UnsafeMutablePointer<uint8>, width: int32, height: int32, stride: int32) {
        self.base = base
        Width = width
        Height = height
        Stride = stride
        Clip = IRect(0, 0, width, height)
    }

    public var Bounds: IRect { return IRect(0, 0, Width, Height) }

    /// Narrows the clip to its intersection with r.
    public mutating func ClipTo(_ r: IRect) {
        Clip = Clip.Intersect(r)
    }

    // MARK: - Pixels

    func rowPointer(_ y: int32) -> UnsafeMutablePointer<uint32> {
        return UnsafeMutablePointer<uint32>(UnsafeMutableRawPointer(base + int(y * Stride)))
    }

    /// The pixel at (x, y), or 0 outside the canvas.
    public func Pixel(_ x: int32, _ y: int32) -> uint32 {
        if x < 0 || y < 0 || x >= Width || y >= Height { return 0 }
        return (rowPointer(y) + int(x)).pointee
    }

    // MARK: - Filling

    /// Paints every pixel the color, clip and all.
    public func Clear(_ color: Color) {
        fillSpanRect(IRect(0, 0, Width, Height), color)
    }

    /// Fills a rectangle, blending where the color is translucent.
    public func Fill(_ r: IRect, _ color: Color) {
        if color.A == 0 { return }
        fillSpanRect(r.Intersect(Clip), color)
    }

    func fillSpanRect(_ r: IRect, _ color: Color) {
        if r.IsEmpty { return }
        let pixel = color.Premultiplied()
        var y = r.Y
        if color.A == 255 {
            var pattern = pixel
            while y < r.Bottom {
                let row = rowPointer(y) + int(r.X)
                _ = c_memset_pattern4(UnsafeMutableRawPointer(row), &pattern, int(r.Width) * 4)
                y += 1
            }
            return
        }
        let inv = 255 - uint32(color.A)
        while y < r.Bottom {
            var p = rowPointer(y) + int(r.X)
            var n = r.Width
            while n > 0 {
                p.pointee = pixel &+ scalePacked(p.pointee, inv)
                p = p + 1
                n -= 1
            }
            y += 1
        }
    }

    /// Fills a rectangle whose corners are rounded, with the curves
    /// anti-aliased. Radii are in device pixels.
    public func FillRounded(_ r: IRect, radii: Radii, _ color: Color) {
        if color.A == 0 || r.IsEmpty { return }
        let fitted = radii.Fitted(float32(r.Width), float32(r.Height))
        if fitted.IsZero {
            Fill(r, color)
            return
        }
        let shape = RoundedRect(rect: r, radii: fitted)
        let clipped = r.Intersect(Clip)
        if clipped.IsEmpty { return }
        let pixel = color.Premultiplied()
        let a = uint32(color.A)
        var y = clipped.Y
        while y < clipped.Bottom {
            var p = rowPointer(y) + int(clipped.X)
            var x = clipped.X
            while x < clipped.Right {
                let c = shape.coverage(x, y)
                if c >= 255 {
                    // The stretch of this row between the curves is solid.
                    var end = shape.solidEnd(y)
                    if end > clipped.Right { end = clipped.Right }
                    if end <= x { end = x + 1 }
                    if a == 255 {
                        var pattern = pixel
                        _ = c_memset_pattern4(UnsafeMutableRawPointer(p), &pattern, int(end - x) * 4)
                        p = p + int(end - x)
                    } else {
                        let inv = 255 - a
                        while x < end {
                            p.pointee = pixel &+ scalePacked(p.pointee, inv)
                            p = p + 1
                            x += 1
                        }
                        continue
                    }
                    x = end
                    continue
                }
                if c > 0 {
                    let ae = mul255(a, uint32(c))
                    p.pointee = scalePacked(pixel, ae) &+ scalePacked(p.pointee, 255 - ae)
                }
                p = p + 1
                x += 1
            }
            y += 1
        }
    }

    /// Fills the area inside `outer` and outside `inner`, both rounded:
    /// a border. Colors one side at a time: the part of the ring nearest
    /// each edge takes that edge's color, meeting the next on the
    /// diagonal, as CSS joins borders of different colors.
    public func FillRing(_ outer: IRect, radii: Radii, widths: Edges, colors: [Color]) {
        if outer.IsEmpty { return }
        let w = widths
        let inner = IRect(outer.X + int32(w.Left), outer.Y + int32(w.Top),
                          outer.Width - int32(w.Left + w.Right), outer.Height - int32(w.Top + w.Bottom))
        let sameColor = colors[0] == colors[1] && colors[1] == colors[2] && colors[2] == colors[3]
        let fitted = radii.Fitted(float32(outer.Width), float32(outer.Height))
        if fitted.IsZero {
            // Four rectangles. With one color the joins do not show; with
            // several, the top and bottom own the corners, which is how
            // most pages' borders look anyway.
            let top = IRect(outer.X, outer.Y, outer.Width, int32(w.Top))
            let bottom = IRect(outer.X, outer.Bottom - int32(w.Bottom), outer.Width, int32(w.Bottom))
            let left = IRect(outer.X, outer.Y + int32(w.Top), int32(w.Left), outer.Height - int32(w.Top + w.Bottom))
            let right = IRect(outer.Right - int32(w.Right), outer.Y + int32(w.Top), int32(w.Right), outer.Height - int32(w.Top + w.Bottom))
            Fill(top, colors[0])
            Fill(right, colors[1])
            Fill(bottom, colors[2])
            Fill(left, colors[3])
            return
        }
        let outerShape = RoundedRect(rect: outer, radii: fitted)
        let innerShape = RoundedRect(rect: inner, radii: fitted.Inset(w))
        let clipped = outer.Intersect(Clip)
        if clipped.IsEmpty { return }
        let cx = float32(outer.X) + float32(outer.Width) / 2
        let cy = float32(outer.Y) + float32(outer.Height) / 2
        var y = clipped.Y
        while y < clipped.Bottom {
            var p = rowPointer(y) + int(clipped.X)
            var x = clipped.X
            while x < clipped.Right {
                let co = outerShape.coverage(x, y)
                if co > 0 {
                    let ci = inner.IsEmpty ? 0 : innerShape.coverage(x, y)
                    if ci < co {
                        let c = co - ci
                        var color = colors[0]
                        if !sameColor {
                            color = colors[sideOf(float32(x) + 0.5 - cx, float32(y) + 0.5 - cy,
                                                  float32(outer.Width), float32(outer.Height), w)]
                        }
                        if color.A > 0 {
                            let ae = mul255(uint32(color.A), uint32(c))
                            p.pointee = scalePacked(color.Premultiplied(), ae) &+ scalePacked(p.pointee, 255 - ae)
                        }
                    } else if ci >= 255 {
                        // Inside the inner curve: skip to where it ends.
                        var end = innerShape.solidEnd(y)
                        if end > clipped.Right { end = clipped.Right }
                        if end <= x { end = x + 1 }
                        p = p + int(end - x)
                        x = end
                        continue
                    }
                }
                p = p + 1
                x += 1
            }
            y += 1
        }
    }

    // MARK: - Masks and images

    /// Blends a color through a mask, whose top-left corner lands at (x, y).
    public func DrawMask(_ m: Mask, x: int32, y: int32, _ color: Color) {
        if color.A == 0 || m.Width <= 0 || m.Height <= 0 { return }
        let target = IRect(x, y, m.Width, m.Height).Intersect(Clip)
        if target.IsEmpty { return }
        let pixel = color.Premultiplied()
        let a = uint32(color.A)
        m.Data.withUnsafeBytes { mp in
            let mbase = UnsafePointer<uint8>(mp.baseAddress!)
            var row = target.Y
            while row < target.Bottom {
                var src = mbase + int((row - y) * m.Width + (target.X - x))
                var dst = rowPointer(row) + int(target.X)
                var n = target.Width
                while n > 0 {
                    let c = uint32(src.pointee)
                    if c == 255 && a == 255 {
                        dst.pointee = pixel
                    } else if c > 0 {
                        let ae = mul255(a, c)
                        dst.pointee = scalePacked(pixel, ae) &+ scalePacked(dst.pointee, 255 - ae)
                    }
                    src = src + 1
                    dst = dst + 1
                    n -= 1
                }
                row += 1
            }
        }
    }

    /// Draws an image into a rectangle, resampling where the sizes
    /// differ: box-filtered when shrinking, bilinear when growing. With
    /// a shape, only the part of the image inside that rounded
    /// rectangle shows, its curves anti-aliased.
    public func DrawImage(_ img: Image, into dst: IRect, opacity: float32 = 1, shape: IRect? = nil, radii: Radii? = nil) {
        if img.Width <= 0 || img.Height <= 0 || dst.IsEmpty { return }
        var target = dst.Intersect(Clip)
        var shapeRect = dst
        if let sh = shape {
            target = target.Intersect(sh)
            shapeRect = sh
        }
        if target.IsEmpty { return }
        let alpha = opacity >= 1 ? uint32(255) : uint32(clamp01(opacity) * 255 + 0.5)
        if alpha == 0 { return }
        let sameSize = dst.Width == img.Width && dst.Height == img.Height
        var shapeRadii = Radii(0, 0, 0, 0)
        if let r = radii { shapeRadii = r }
        let rounded = shape != nil && !shapeRadii.IsZero
        let curve = RoundedRect(rect: shapeRect, radii: shapeRadii.Fitted(float32(shapeRect.Width), float32(shapeRect.Height)))
        img.Pixels.withUnsafeBytes { ip in
            let ibase = UnsafePointer<uint32>(UnsafeRawPointer(ip.baseAddress!))
            var y = target.Y
            while y < target.Bottom {
                var p = rowPointer(y) + int(target.X)
                var x = target.X
                while x < target.Right {
                    var s: uint32 = 0
                    if sameSize {
                        s = (ibase + int((y - dst.Y) * img.Width + (x - dst.X))).pointee
                    } else {
                        s = sample(ibase, img.Width, img.Height, x - dst.X, y - dst.Y, dst.Width, dst.Height)
                    }
                    if alpha < 255 { s = scalePacked(s, alpha) }
                    if rounded {
                        let cov = curve.coverage(x, y)
                        if cov <= 0 { s = 0 } else if cov < 255 { s = scalePacked(s, uint32(cov)) }
                    }
                    let sa = s >> 24
                    if sa == 255 {
                        p.pointee = s
                    } else if sa > 0 {
                        p.pointee = s &+ scalePacked(p.pointee, 255 - sa)
                    }
                    p = p + 1
                    x += 1
                }
                y += 1
            }
        }
    }
}

/// Runs body with a canvas over pixels, which must hold width * height
/// premultiplied RGBA pixels.
public func WithCanvas(_ pixels: inout [uint8], width: int32, height: int32, _ body: (Canvas) -> Void) {
    if width <= 0 || height <= 0 || pixels.count < int(width) * int(height) * 4 { return }
    pixels.withUnsafeMutableBytes { bp in
        let canvas = Canvas(base: UnsafeMutablePointer<uint8>(bp.baseAddress!), width: width, height: height, stride: width * 4)
        body(canvas)
    }
}

@_silgen_name("memset_pattern4")
func c_memset_pattern4(_ dst: UnsafeMutableRawPointer, _ pattern: UnsafePointer<uint32>, _ len: int) -> UnsafeMutableRawPointer

/// Every channel of a packed pixel multiplied by f / 255, two at a time.
func scalePacked(_ p: uint32, _ f: uint32) -> uint32 {
    var rb = (p & 0x00FF00FF) &* f
    rb = ((rb &+ ((rb >> 8) & 0x00FF00FF) &+ 0x00800080) >> 8) & 0x00FF00FF
    var ga = ((p >> 8) & 0x00FF00FF) &* f
    ga = (ga &+ ((ga >> 8) & 0x00FF00FF) &+ 0x00800080) & 0xFF00FF00
    return rb | ga
}

/// The side of a box a point in its border belongs to -- 0 top, 1 right,
/// 2 bottom, 3 left -- by which edge the point is nearest, measured in
/// widths of each border.
func sideOf(_ dx: float32, _ dy: float32, _ w: float32, _ h: float32, _ e: Edges) -> int {
    let hw = w / 2
    let hh = h / 2
    let toRight = e.Right > 0 ? (hw - dx) / e.Right : 1e9
    let toLeft = e.Left > 0 ? (hw + dx) / e.Left : 1e9
    let toBottom = e.Bottom > 0 ? (hh - dy) / e.Bottom : 1e9
    let toTop = e.Top > 0 ? (hh + dy) / e.Top : 1e9
    var side = 0
    var best = toTop
    if toRight < best { best = toRight; side = 1 }
    if toBottom < best { best = toBottom; side = 2 }
    if toLeft < best { best = toLeft; side = 3 }
    return side
}

/// A rectangle with rounded corners, answering how much of each pixel
/// it covers. Pixels away from the corners are all in or all out; a pixel
/// in a corner's square is covered by how far its centre lies inside
/// that corner's circle.
struct RoundedRect {
    let rect: IRect
    let radii: Radii

    func coverage(_ x: int32, _ y: int32) -> int32 {
        if x < rect.X || y < rect.Y || x >= rect.Right || y >= rect.Bottom { return 0 }
        let px = float32(x) + 0.5
        let py = float32(y) + 0.5
        let left = float32(rect.X)
        let top = float32(rect.Y)
        let right = float32(rect.Right)
        let bottom = float32(rect.Bottom)
        var r: float32 = 0
        var cx: float32 = 0
        var cy: float32 = 0
        if px < left + radii.TopLeft && py < top + radii.TopLeft {
            r = radii.TopLeft; cx = left + r; cy = top + r
        } else if px > right - radii.TopRight && py < top + radii.TopRight {
            r = radii.TopRight; cx = right - r; cy = top + r
        } else if px > right - radii.BottomRight && py > bottom - radii.BottomRight {
            r = radii.BottomRight; cx = right - r; cy = bottom - r
        } else if px < left + radii.BottomLeft && py > bottom - radii.BottomLeft {
            r = radii.BottomLeft; cx = left + r; cy = bottom - r
        } else {
            return 255
        }
        let dx = px - cx
        let dy = py - cy
        let d = c_sqrtf(dx * dx + dy * dy)
        let inside = r - d + 0.5
        if inside >= 1 { return 255 }
        if inside <= 0 { return 0 }
        return int32(inside * 255 + 0.5)
    }

    /// The first x on row y past which the row is no longer solid: the
    /// start of the right-hand curve, or the right edge.
    func solidEnd(_ y: int32) -> int32 {
        let py = float32(y) + 0.5
        let top = float32(rect.Y)
        let bottom = float32(rect.Bottom)
        var inset: float32 = 0
        if py < top + radii.TopRight { inset = radii.TopRight }
        if py > bottom - radii.BottomRight && radii.BottomRight > inset { inset = radii.BottomRight }
        return rect.Right - int32(inset + 1)
    }
}

@_silgen_name("sqrtf")
func c_sqrtf(_ x: float32) -> float32

/// One pixel of an image resampled into a destination of another size:
/// a box average of the source pixels the destination pixel covers when
/// shrinking, and the bilinear blend of the four nearest when growing.
func sample(_ src: UnsafePointer<uint32>, _ sw: int32, _ sh: int32,
            _ dx: int32, _ dy: int32, _ dw: int32, _ dh: int32) -> uint32 {
    let fx = float32(sw) / float32(dw)
    let fy = float32(sh) / float32(dh)
    if fx > 1 || fy > 1 {
        var x0 = int32(float32(dx) * fx)
        var x1 = int32(float32(dx + 1) * fx)
        var y0 = int32(float32(dy) * fy)
        var y1 = int32(float32(dy + 1) * fy)
        if x1 <= x0 { x1 = x0 + 1 }
        if y1 <= y0 { y1 = y0 + 1 }
        if x0 >= sw { x0 = sw - 1 }
        if y0 >= sh { y0 = sh - 1 }
        if x1 > sw { x1 = sw }
        if y1 > sh { y1 = sh }
        var r: uint32 = 0
        var g: uint32 = 0
        var b: uint32 = 0
        var a: uint32 = 0
        var n: uint32 = 0
        var y = y0
        while y < y1 {
            var x = x0
            while x < x1 {
                let p = (src + int(y * sw + x)).pointee
                r += p & 0xFF
                g += (p >> 8) & 0xFF
                b += (p >> 16) & 0xFF
                a += p >> 24
                n += 1
                x += 1
            }
            y += 1
        }
        if n == 0 { return 0 }
        return (r / n) | ((g / n) << 8) | ((b / n) << 16) | ((a / n) << 24)
    }
    let sx = (float32(dx) + 0.5) * fx - 0.5
    let sy = (float32(dy) + 0.5) * fy - 0.5
    var x0 = int32(c_floorf(sx))
    var y0 = int32(c_floorf(sy))
    let tx = sx - float32(x0)
    let ty = sy - float32(y0)
    if x0 < 0 { x0 = 0 }
    if y0 < 0 { y0 = 0 }
    let x1 = x0 + 1 < sw ? x0 + 1 : x0
    let y1 = y0 + 1 < sh ? y0 + 1 : y0
    let wx1 = uint32(tx * 256)
    let wx0 = 256 - wx1
    let wy1 = uint32(ty * 256)
    let wy0 = 256 - wy1
    let p00 = (src + int(y0 * sw + x0)).pointee
    let p10 = (src + int(y0 * sw + x1)).pointee
    let p01 = (src + int(y1 * sw + x0)).pointee
    let p11 = (src + int(y1 * sw + x1)).pointee
    var out: uint32 = 0
    var shift: uint32 = 0
    while shift < 32 {
        let c00 = (p00 >> shift) & 0xFF
        let c10 = (p10 >> shift) & 0xFF
        let c01 = (p01 >> shift) & 0xFF
        let c11 = (p11 >> shift) & 0xFF
        let top = c00 * wx0 + c10 * wx1
        let bot = c01 * wx0 + c11 * wx1
        let v = (top * wy0 + bot * wy1) >> 16
        out |= (v & 0xFF) << shift
        shift += 8
    }
    return out
}

@_silgen_name("floorf")
func c_floorf(_ x: float32) -> float32
