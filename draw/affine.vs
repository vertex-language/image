package draw

import "math"

/// A 2D affine transform: a point (x, y) goes to
/// (A*x + C*y + E, B*x + D*y + F), as CSS's matrix(a, b, c, d, e, f).
public struct Affine: Equatable {
    public var A: float32
    public var B: float32
    public var C: float32
    public var D: float32
    public var E: float32
    public var F: float32

    public init(_ a: float32, _ b: float32, _ c: float32, _ d: float32, _ e: float32, _ f: float32) {
        A = a
        B = b
        C = c
        D = d
        E = e
        F = f
    }

    public static let identity = Affine(1, 0, 0, 1, 0, 0)

    public static func translate(_ x: float32, _ y: float32) -> Affine { return Affine(1, 0, 0, 1, x, y) }
    public static func scale(_ x: float32, _ y: float32) -> Affine { return Affine(x, 0, 0, y, 0, 0) }

    /// A rotation by radians, clockwise on a y-down canvas.
    public static func rotate(_ radians: float32) -> Affine {
        let c = math.Cos(radians)
        let s = math.Sin(radians)
        return Affine(c, s, -s, c, 0, 0)
    }

    /// A skew by angles in radians along x and y.
    public static func skew(_ x: float32, _ y: float32) -> Affine {
        return Affine(1, math.Tan(y), math.Tan(x), 1, 0, 0)
    }

    public var IsIdentity: bool { return self == Affine.identity }

    /// This transform after o: the point goes through o, then this.
    public func Concat(_ o: Affine) -> Affine {
        return Affine(A * o.A + C * o.B, B * o.A + D * o.B,
                      A * o.C + C * o.D, B * o.C + D * o.D,
                      A * o.E + C * o.F + E, B * o.E + D * o.F + F)
    }

    public var Determinant: float32 { return A * D - B * C }

    /// The inverse, or nil where the transform flattens the plane.
    public func Inverted() -> Affine? {
        let det = Determinant
        if det == 0 { return nil }
        let a = D / det
        let b = -B / det
        let c = -C / det
        let d = A / det
        return Affine(a, b, c, d, -(a * E + c * F), -(b * E + d * F))
    }

    public func Apply(_ x: float32, _ y: float32) -> (x: float32, y: float32) {
        return (x: A * x + C * y + E, y: B * x + D * y + F)
    }

    /// The bounds of a rectangle once transformed.
    public func Bounds(_ r: Rect) -> Rect {
        let p0 = Apply(r.X, r.Y)
        let p1 = Apply(r.Right, r.Y)
        let p2 = Apply(r.X, r.Bottom)
        let p3 = Apply(r.Right, r.Bottom)
        let x0 = math.Min(math.Min(p0.x, p1.x), math.Min(p2.x, p3.x))
        let y0 = math.Min(math.Min(p0.y, p1.y), math.Min(p2.y, p3.y))
        let x1 = math.Max(math.Max(p0.x, p1.x), math.Max(p2.x, p3.x))
        let y1 = math.Max(math.Max(p0.y, p1.y), math.Max(p2.y, p3.y))
        return Rect(x0, y0, x1 - x0, y1 - y0)
    }
}

extension Layer {
    /// Paints the layer onto a canvas through a transform of the
    /// canvas's own pixel coordinates, over what's there, inside its
    /// clip: each pixel it covers samples the layer bilinearly.
    public func Composite(onto c: Canvas, transform t: Affine) {
        if t.IsIdentity {
            Composite(onto: c)
            return
        }
        guard let inv = t.Inverted() else { return }
        let src = draw.Rect(float32(Rect.X), float32(Rect.Y), float32(Rect.Width), float32(Rect.Height))
        let b = t.Bounds(src)
        let x0 = int32(math.Floor(b.X))
        let y0 = int32(math.Floor(b.Y))
        let x1 = int32(math.Ceil(b.Right))
        let y1 = int32(math.Ceil(b.Bottom))
        let area = IRect(x0, y0, x1 - x0, y1 - y0).Intersect(c.Clip)
        if area.IsEmpty { return }
        var y = area.Y
        while y < area.Bottom {
            var dst = c.rowPointer(y) + int(area.X)
            var x = area.X
            while x < area.Right {
                // The layer's point under this pixel's center.
                let p = inv.Apply(float32(x) + 0.5, float32(y) + 0.5)
                let s = sample(p.x - 0.5, p.y - 0.5)
                let sa = s >> 24
                if sa == 255 {
                    dst.pointee = s
                } else if sa > 0 {
                    dst.pointee = s &+ scalePacked(dst.pointee, 255 - sa)
                }
                dst = dst + 1
                x += 1
            }
            y += 1
        }
    }

    /// The layer's pixel at canvas coordinates (x, y), between pixel
    /// centers blended bilinearly; transparent outside it.
    func sample(_ x: float32, _ y: float32) -> uint32 {
        let fx = math.Floor(x)
        let fy = math.Floor(y)
        let ix = int32(fx)
        let iy = int32(fy)
        let wx = uint32((x - fx) * 256)
        let wy = uint32((y - fy) * 256)
        let p00 = at(ix, iy)
        let p10 = at(ix + 1, iy)
        let p01 = at(ix, iy + 1)
        let p11 = at(ix + 1, iy + 1)
        if (p00 | p10 | p01 | p11) == 0 { return 0 }
        let top = lerpPacked(p00, p10, wx)
        let bottom = lerpPacked(p01, p11, wx)
        return lerpPacked(top, bottom, wy)
    }

    func at(_ x: int32, _ y: int32) -> uint32 {
        if x < Rect.X || y < Rect.Y || x >= Rect.Right || y >= Rect.Bottom { return 0 }
        return (pixels + int((y - Rect.Y) * Rect.Width + (x - Rect.X))).pointee
    }
}

/// a and b blended, w/256 of the way to b, channel by channel.
func lerpPacked(_ a: uint32, _ b: uint32, _ w: uint32) -> uint32 {
    if w == 0 { return a }
    if w >= 256 { return b }
    let iw = 256 - w
    let rb = (((a & 0x00FF00FF) &* iw &+ (b & 0x00FF00FF) &* w) >> 8) & 0x00FF00FF
    let ga = ((((a >> 8) & 0x00FF00FF) &* iw &+ ((b >> 8) & 0x00FF00FF) &* w) >> 8) & 0x00FF00FF
    return rb | (ga << 8)
}
