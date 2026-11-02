package draw

import "math"

/// A 3D transform with perspective, column by column as CSS's matrix3d
/// lists it: a point (x, y, z, 1) goes to
/// (M[0]x + M[4]y + M[8]z + M[12], M[1]x + M[5]y + M[9]z + M[13],
///  M[2]x + M[6]y + M[10]z + M[14], M[3]x + M[7]y + M[11]z + M[15]).
public struct Matrix4: Equatable {
    public var M: [float32]

    public init(m: [float32]) { M = m }

    public static let identity = Matrix4(m: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])

    public init(affine a: Affine) {
        M = [a.A, a.B, 0, 0, a.C, a.D, 0, 0, 0, 0, 1, 0, a.E, a.F, 0, 1]
    }

    public static func translate(x: float32, y: float32, z: float32 = 0) -> Matrix4 {
        return Matrix4(m: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1])
    }

    public static func scale(x: float32, y: float32, z: float32) -> Matrix4 {
        return Matrix4(m: [x, 0, 0, 0, 0, y, 0, 0, 0, 0, z, 0, 0, 0, 0, 1])
    }

    /// A turn of radians about an axis, clockwise looking along it.
    public static func rotate(x: float32, y: float32, z: float32, radians: float32) -> Matrix4 {
        let len = math.Sqrt(x * x + y * y + z * z)
        if len == 0 { return identity }
        let ux = x / len
        let uy = y / len
        let uz = z / len
        let c = math.Cos(radians)
        let s = math.Sin(radians)
        let t = 1 - c
        return Matrix4(m: [t * ux * ux + c, t * ux * uy + s * uz, t * ux * uz - s * uy, 0,
                           t * ux * uy - s * uz, t * uy * uy + c, t * uy * uz + s * ux, 0,
                           t * ux * uz + s * uy, t * uy * uz - s * ux, t * uz * uz + c, 0,
                           0, 0, 0, 1])
    }

    /// CSS's perspective(d): the viewer d in front of the plane z = 0.
    public static func perspective(d: float32) -> Matrix4 {
        if d <= 0 { return identity }
        return Matrix4(m: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, -1 / d, 0, 0, 0, 1])
    }

    /// This transform after another: other first, then self.
    public func Concat(o: Matrix4) -> Matrix4 {
        var out = [float32](repeating: 0, count: 16)
        var c = 0
        while c < 4 {
            var r = 0
            while r < 4 {
                var sum: float32 = 0
                var k = 0
                while k < 4 {
                    sum += M[k * 4 + r] * o.M[c * 4 + k]
                    k += 1
                }
                out[c * 4 + r] = sum
                r += 1
            }
            c += 1
        }
        return Matrix4(m: out)
    }

    /// Where a point of the plane z = 0 goes, before the divide by W.
    public func Apply(x: float32, y: float32) -> (x: float32, y: float32, z: float32, w: float32) {
        return (x: M[0] * x + M[4] * y + M[12], y: M[1] * x + M[5] * y + M[13],
                z: M[2] * x + M[6] * y + M[14], w: M[3] * x + M[7] * y + M[15])
    }

    /// The plane's determinant as drawn: below zero, it shows its back.
    var planeDeterminant: float32 {
        let a = M[0]; let b = M[4]; let c = M[12]
        let d = M[1]; let e = M[5]; let f = M[13]
        let g = M[3]; let h = M[7]; let i = M[15]
        return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    }

    /// Whether the plane z = 0 is seen from its front.
    public var FacesViewer: bool { return planeDeterminant >= 0 }

    /// Takes a point on the screen back to the plane z = 0, or nil where
    /// the transform flattens the plane or the point is behind the viewer.
    public func Unproject(x: float32, y: float32) -> (x: float32, y: float32)? {
        guard let inv = planeInverse() else { return nil }
        let w = inv[6] * x + inv[7] * y + inv[8]
        if w == 0 { return nil }
        let px = (inv[0] * x + inv[1] * y + inv[2]) / w
        let py = (inv[3] * x + inv[4] * y + inv[5]) / w
        if Apply(px, py).w <= 0 { return nil }
        return (x: px, y: py)
    }

    /// The inverse of the plane's 3x3, row by row.
    func planeInverse() -> [float32]? {
        let a = M[0]; let b = M[4]; let c = M[12]
        let d = M[1]; let e = M[5]; let f = M[13]
        let g = M[3]; let h = M[7]; let i = M[15]
        let det = planeDeterminant
        if det > -1e-9 && det < 1e-9 { return nil }
        return [(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det,
                (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
                (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]
    }
}

/// A plane of a 3D context, on its way to a canvas.
public struct DepthPlane {
    public let Plane: Layer
    public let Matrix: Matrix4
    public let Blend: BlendMode

    public init(plane: Layer, matrix: Matrix4, blend: BlendMode) {
        Plane = plane
        Matrix = matrix
        Blend = blend
    }
}

/// The planes of a 3D context onto a canvas, given the farthest first. Planes
/// whose depths don't overlap go down whole; where they might cross, each
/// pixel takes its planes by their depths there.
public func CompositePlanes(planes: [DepthPlane], onto c: Canvas) {
    var inverses: [[float32]] = []
    var kept: [DepthPlane] = []
    var areas: [IRect] = []
    var content: [IRect] = []
    var lows: [float32] = []
    var highs: [float32] = []
    for p in planes {
        guard let inv = p.Matrix.planeInverse() else { continue }
        let drawn = p.Plane.contentBounds()
        if drawn.IsEmpty { continue }
        var low: float32 = 1e9
        var high: float32 = -1e9
        var area = c.Clip
        var x0: float32 = 1e9
        var y0: float32 = 1e9
        var x1: float32 = -1e9
        var y1: float32 = -1e9
        var behind = false
        let corners = [(float32(drawn.X), float32(drawn.Y)), (float32(drawn.Right), float32(drawn.Y)),
                       (float32(drawn.X), float32(drawn.Bottom)), (float32(drawn.Right), float32(drawn.Bottom))]
        for corner in corners {
            let q = p.Matrix.Apply(corner.0, corner.1)
            if q.w <= 0 {
                behind = true
                continue
            }
            low = math.Min(low, q.z / q.w)
            high = math.Max(high, q.z / q.w)
            x0 = math.Min(x0, q.x / q.w)
            y0 = math.Min(y0, q.y / q.w)
            x1 = math.Max(x1, q.x / q.w)
            y1 = math.Max(y1, q.y / q.w)
        }
        if !behind { area = IRect(int32(math.Floor(x0)), int32(math.Floor(y0)), int32(math.Ceil(x1 - x0)) + 2, int32(math.Ceil(y1 - y0)) + 2).Intersect(c.Clip) }
        if behind {
            low = -1e9
            high = 1e9
        }
        if area.IsEmpty { continue }
        inverses.append(inv)
        kept.append(p)
        areas.append(area)
        content.append(drawn)
        lows.append(low)
        highs.append(high)
    }
    // Whether two planes that share any pixels share depths too.
    var crossing = false
    var i = 0
    while i < kept.count && !crossing {
        var j = i + 1
        while j < kept.count {
            if !areas[i].Intersect(areas[j]).IsEmpty && lows[j] < highs[i] && lows[i] < highs[j] {
                crossing = true
                break
            }
            j += 1
        }
        i += 1
    }
    if !crossing {
        for p in kept { p.Plane.Composite(onto: c, matrix: p.Matrix, blend: p.Blend) }
        return
    }
    var union = IRect.zero
    for a in areas { union = union.Union(a) }
    var depths = [float32](repeating: 0, count: kept.count)
    var colors = [uint32](repeating: 0, count: kept.count)
    var modes = [int](repeating: 0, count: kept.count)
    var y = union.Y
    while y < union.Bottom {
        var dst = c.rowPointer(y) + int(union.X)
        var x = union.X
        while x < union.Right {
            var n = 0
            var k = 0
            while k < kept.count {
                if areas[k].Contains(x, y) {
                    let inv = inverses[k]
                    let sx = float32(x) + 0.5
                    let sy = float32(y) + 0.5
                    let w = inv[6] * sx + inv[7] * sy + inv[8]
                    if w != 0 {
                        let px = (inv[0] * sx + inv[1] * sy + inv[2]) / w
                        let py = (inv[3] * sx + inv[4] * sy + inv[5]) / w
                        let s = kept[k].Plane.sample(px - 0.5, py - 0.5)
                        if (s >> 24) != 0 {
                            let q = kept[k].Matrix.Apply(px, py)
                            if q.w > 0 {
                                // In by depth, the farthest first; ties stay in order.
                                let z = q.z / q.w
                                var at = n
                                while at > 0 && depths[at - 1] > z {
                                    depths[at] = depths[at - 1]
                                    colors[at] = colors[at - 1]
                                    modes[at] = modes[at - 1]
                                    at -= 1
                                }
                                depths[at] = z
                                colors[at] = s
                                modes[at] = k
                                n += 1
                            }
                        }
                    }
                }
                k += 1
            }
            k = 0
            while k < n {
                let s = colors[k]
                let blend = kept[modes[k]].Blend
                if blend != .normal {
                    dst.pointee = blendPixel(s, dst.pointee, blend)
                } else if (s >> 24) == 255 {
                    dst.pointee = s
                } else {
                    dst.pointee = s &+ scalePacked(dst.pointee, 255 - (s >> 24))
                }
                k += 1
            }
            dst = dst + 1
            x += 1
        }
        y += 1
    }
}

extension Layer {
    /// The rectangle round what's been drawn in the layer.
    func contentBounds() -> IRect {
        var x0 = Rect.Right
        var y0 = Rect.Bottom
        var x1 = Rect.X
        var y1 = Rect.Y
        var y = Rect.Y
        var p = pixels
        while y < Rect.Bottom {
            var x = Rect.X
            while x < Rect.Right {
                if (p.pointee >> 24) != 0 {
                    if x < x0 { x0 = x }
                    if x >= x1 { x1 = x + 1 }
                    if y < y0 { y0 = y }
                    if y >= y1 { y1 = y + 1 }
                }
                p = p + 1
                x += 1
            }
            y += 1
        }
        if x1 <= x0 || y1 <= y0 { return IRect(Rect.X, Rect.Y, 0, 0) }
        return IRect(x0, y0, x1 - x0, y1 - y0)
    }

    /// Paints the layer onto a canvas through a 3D transform of the
    /// canvas's own pixel coordinates, with perspective, each pixel
    /// sampling the layer bilinearly. What falls behind the viewer is cut.
    public func Composite(onto c: Canvas, matrix m: Matrix4, blend: BlendMode = .normal) {
        guard let inv = m.planeInverse() else { return }
        var area = c.Clip
        let corners = [(float32(Rect.X), float32(Rect.Y)), (float32(Rect.Right), float32(Rect.Y)),
                       (float32(Rect.X), float32(Rect.Bottom)), (float32(Rect.Right), float32(Rect.Bottom))]
        var x0: float32 = 1e9
        var y0: float32 = 1e9
        var x1: float32 = -1e9
        var y1: float32 = -1e9
        var behind = false
        for corner in corners {
            let p = m.Apply(corner.0, corner.1)
            if p.w <= 0 {
                behind = true
                continue
            }
            x0 = math.Min(x0, p.x / p.w)
            y0 = math.Min(y0, p.y / p.w)
            x1 = math.Max(x1, p.x / p.w)
            y1 = math.Max(y1, p.y / p.w)
        }
        if !behind {
            area = IRect(int32(math.Floor(x0)), int32(math.Floor(y0)), int32(math.Ceil(x1 - x0)) + 2, int32(math.Ceil(y1 - y0)) + 2).Intersect(c.Clip)
        }
        if area.IsEmpty { return }
        var y = area.Y
        while y < area.Bottom {
            var dst = c.rowPointer(y) + int(area.X)
            var x = area.X
            while x < area.Right {
                let sx = float32(x) + 0.5
                let sy = float32(y) + 0.5
                let w = inv[6] * sx + inv[7] * sy + inv[8]
                if w != 0 {
                    let px = (inv[0] * sx + inv[1] * sy + inv[2]) / w
                    let py = (inv[3] * sx + inv[4] * sy + inv[5]) / w
                    if !behind || m.Apply(px, py).w > 0 {
                        let s = sample(px - 0.5, py - 0.5)
                        let sa = s >> 24
                        if blend != .normal {
                            if sa != 0 { dst.pointee = blendPixel(s, dst.pointee, blend) }
                        } else if sa == 255 {
                            dst.pointee = s
                        } else if sa > 0 {
                            dst.pointee = s &+ scalePacked(dst.pointee, 255 - sa)
                        }
                    }
                }
                dst = dst + 1
                x += 1
            }
            y += 1
        }
    }
}
