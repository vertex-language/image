package draw

/// Which parts of a path a fill covers where contours overlap: nonzero
/// winding (SVG's and canvas's default), or even-odd, which makes holes
/// of overlaps whichever way they wind.
public enum FillRule: Equatable {
    case nonZero
    case evenOdd
}

/// A shape of straight segments, in device pixels: curves are flattened
/// as they are added. Each contour is closed when filled.
public struct Path {
    /// The points, contour after contour.
    public var Points: [Point] = []
    /// Where each contour starts in Points.
    public var Starts: [int] = []
    var current = Point(0, 0)
    var start = Point(0, 0)

    public init() {}

    public var IsEmpty: bool { return Points.isEmpty }
    /// Where the pen is.
    public var Current: Point { return current }

    public mutating func MoveTo(_ x: float32, _ y: float32) {
        Starts.append(Points.count)
        Points.append(Point(x, y))
        current = Point(x, y)
        start = current
    }

    public mutating func LineTo(_ x: float32, _ y: float32) {
        if Starts.isEmpty { MoveTo(current.X, current.Y) }
        Points.append(Point(x, y))
        current = Point(x, y)
    }

    /// A quadratic Bézier curve to (x, y) with control point (cx, cy).
    public mutating func QuadTo(_ cx: float32, _ cy: float32, _ x: float32, _ y: float32) {
        let p0 = current
        let n = segments(p0, Point(x, y), [Point(cx, cy)])
        var i = 1
        while i <= n {
            let t = float32(i) / float32(n)
            let u = 1 - t
            LineTo(u * u * p0.X + 2 * u * t * cx + t * t * x, u * u * p0.Y + 2 * u * t * cy + t * t * y)
            i += 1
        }
    }

    /// A cubic Bézier curve to (x, y) with control points (c1x, c1y) and
    /// (c2x, c2y).
    public mutating func CubicTo(_ c1x: float32, _ c1y: float32, _ c2x: float32, _ c2y: float32, _ x: float32, _ y: float32) {
        let p0 = current
        let n = segments(p0, Point(x, y), [Point(c1x, c1y), Point(c2x, c2y)])
        var i = 1
        while i <= n {
            let t = float32(i) / float32(n)
            let u = 1 - t
            let a = u * u * u
            let b = 3 * u * u * t
            let c = 3 * u * t * t
            let d = t * t * t
            LineTo(a * p0.X + b * c1x + c * c2x + d * x, a * p0.Y + b * c1y + c * c2y + d * y)
            i += 1
        }
    }

    /// Ends the contour, back at its start.
    public mutating func Close() {
        if !Starts.isEmpty { current = start }
    }

    /// How many straight pieces a curve needs to stay within a quarter
    /// pixel: by the length of its control polygon.
    func segments(_ a: Point, _ b: Point, _ controls: [Point]) -> int {
        var len: float32 = 0
        var prev = a
        for c in controls {
            len += distance(prev, c)
            prev = c
        }
        len += distance(prev, b)
        let n = int(len / 3) + 2
        return n < 64 ? n : 64
    }

    /// Its bounds, in device pixels.
    public var Bounds: Rect {
        if Points.isEmpty { return Rect(0, 0, 0, 0) }
        var minX = Points[0].X
        var minY = Points[0].Y
        var maxX = minX
        var maxY = minY
        for p in Points {
            if p.X < minX { minX = p.X }
            if p.Y < minY { minY = p.Y }
            if p.X > maxX { maxX = p.X }
            if p.Y > maxY { maxY = p.Y }
        }
        return Rect(minX, minY, maxX - minX, maxY - minY)
    }
}

func distance(_ a: Point, _ b: Point) -> float32 {
    let dx = a.X - b.X
    let dy = a.Y - b.Y
    return sqrtf32(dx * dx + dy * dy)
}

@_silgen_name("sqrtf")
func sqrtf32(_ x: float32) -> float32

@_silgen_name("floorf")
func floorf32(_ x: float32) -> float32

/// Sub-rows sampled per pixel row: anti-aliasing across the edges is
/// exact horizontally and in quarters vertically.
let pathSamples: int = 4

extension Canvas {
    /// Fills a path in a color, anti-aliased, kept to the clip.
    public func FillPath(_ path: Path, rule: FillRule = .nonZero, _ color: Color) {
        if path.Points.count < 3 || color.A == 0 { return }
        let bounds = path.Bounds
        let x0 = int32(floorf32(bounds.X))
        let y0 = int32(floorf32(bounds.Y))
        let area = IRect(x0, y0, int32(floorf32(bounds.X + bounds.Width)) - x0 + 1, int32(floorf32(bounds.Y + bounds.Height)) - y0 + 1).Intersect(Clip)
        if area.IsEmpty { return }
        let w = int(area.Width)
        let h = int(area.Height)

        // The edges, closing each contour; horizontal ones cross no row.
        var ex0: [float32] = []
        var ey0: [float32] = []
        var ex1: [float32] = []
        var ey1: [float32] = []
        var edir: [int32] = []
        var c = 0
        while c < path.Starts.count {
            let first = path.Starts[c]
            let end = c + 1 < path.Starts.count ? path.Starts[c + 1] : path.Points.count
            var i = first
            while i < end {
                let a = path.Points[i]
                let b = i + 1 < end ? path.Points[i + 1] : path.Points[first]
                if a.Y != b.Y {
                    if a.Y < b.Y {
                        ex0.append(a.X); ey0.append(a.Y); ex1.append(b.X); ey1.append(b.Y); edir.append(1)
                    } else {
                        ex0.append(b.X); ey0.append(b.Y); ex1.append(a.X); ey1.append(a.Y); edir.append(-1)
                    }
                }
                i += 1
            }
            c += 1
        }
        let edges = ex0.count
        if edges == 0 { return }

        let acc = UnsafeMutablePointer<float32>.allocate(capacity: w + 1)
        let xs = UnsafeMutablePointer<float32>.allocate(capacity: edges)
        let ds = UnsafeMutablePointer<int32>.allocate(capacity: edges)
        var mask = [uint8](repeating: 0, count: w * h)
        let share: float32 = 1 / float32(pathSamples)
        let left = float32(area.X)
        let width = float32(w)
        mask.withUnsafeMutableBufferPointer { mp in
            let out = mp.baseAddress!
            var row = 0
            while row < h {
                var k = 0
                while k <= w {
                    acc[k] = 0
                    k += 1
                }
                var s = 0
                while s < pathSamples {
                    let sy = float32(area.Y) + float32(row) + (float32(s) + 0.5) * share
                    // Where this sub-row crosses the edges, sorted.
                    var n = 0
                    var e = 0
                    while e < edges {
                        if sy >= ey0[e] && sy < ey1[e] {
                            let x = ex0[e] + (sy - ey0[e]) * (ex1[e] - ex0[e]) / (ey1[e] - ey0[e])
                            var j = n
                            while j > 0 && xs[j - 1] > x {
                                xs[j] = xs[j - 1]
                                ds[j] = ds[j - 1]
                                j -= 1
                            }
                            xs[j] = x
                            ds[j] = edir[e]
                            n += 1
                        }
                        e += 1
                    }
                    // Walk them, covering what the rule calls inside.
                    var winding: int32 = 0
                    var spanStart: float32 = 0
                    var j = 0
                    while j < n {
                        let wasInside = rule == .nonZero ? winding != 0 : (winding & 1) != 0
                        winding += rule == .nonZero ? ds[j] : 1
                        let inside = rule == .nonZero ? winding != 0 : (winding & 1) != 0
                        if inside && !wasInside {
                            spanStart = xs[j]
                        } else if !inside && wasInside {
                            // Covers [spanStart, xs[j]) in this sub-row.
                            var a = spanStart - left
                            var b = xs[j] - left
                            if a < 0 { a = 0 }
                            if b > width { b = width }
                            if b > a {
                                let ia = int(a)
                                let ib = int(b)
                                if ia == ib {
                                    acc[ia] += (b - a) * share
                                } else {
                                    acc[ia] += (float32(ia + 1) - a) * share
                                    var m = ia + 1
                                    while m < ib {
                                        acc[m] += share
                                        m += 1
                                    }
                                    if ib < w { acc[ib] += (b - float32(ib)) * share }
                                }
                            }
                        }
                        j += 1
                    }
                    s += 1
                }
                var x = 0
                let line = out + row * w
                while x < w {
                    var v = acc[x]
                    if v > 1 { v = 1 }
                    line[x] = uint8(v * 255 + 0.5)
                    x += 1
                }
                row += 1
            }
        }
        acc.deallocate()
        xs.deallocate()
        ds.deallocate()
        DrawMask(Mask(width: int32(w), height: int32(h), data: mask), x: area.X, y: area.Y, color)
    }
}
