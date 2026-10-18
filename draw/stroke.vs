package draw

import "math"

/// How an open line's ends are drawn.
public enum LineCap: Equatable {
    /// Square, at the end itself.
    case butt
    /// A half circle past the end.
    case round
    /// Square, half the width past the end.
    case square
}

/// How a line's corners are drawn.
public enum LineJoin: Equatable {
    /// Pointed, or beveled where the point would be longer than the
    /// miter limit (times half the width).
    case miter
    case round
    case bevel
}

/// How a path is stroked: a line of width centered on it.
public struct Stroke: Equatable {
    public var Width: float32
    public var Cap: LineCap
    public var Join: LineJoin
    public var MiterLimit: float32

    public init(width: float32, cap: LineCap = .butt, join: LineJoin = .miter, miterLimit: float32 = 4) {
        Width = width
        Cap = cap
        Join = join
        MiterLimit = miterLimit
    }
}

extension Path {
    /// The area a stroke of the path covers, as a path to fill with the
    /// nonzero rule: a quadrilateral per segment, and the joins and caps,
    /// all wound the same way so their overlaps fill once.
    public func Stroked(_ s: Stroke) -> Path {
        var out = Path()
        let hw = s.Width / 2
        if hw <= 0 { return out }
        var c = 0
        while c < Starts.count {
            let first = Starts[c]
            let end = c + 1 < Starts.count ? Starts[c + 1] : Points.count
            let closed = c < Closed.count && Closed[c]
            // The contour's points, without repeats.
            var pts: [Point] = []
            var i = first
            while i < end {
                let p = Points[i]
                if pts.isEmpty || distance(pts[pts.count - 1], p) > 0.001 { pts.append(p) }
                i += 1
            }
            if closed && pts.count > 1 && distance(pts[0], pts[pts.count - 1]) <= 0.001 { pts.removeLast() }
            c += 1
            if pts.isEmpty { continue }
            if pts.count == 1 {
                // A dot: what a zero-length line's caps draw.
                if s.Cap == .round { out.addCircle(pts[0], hw) }
                if s.Cap == .square { out.addPolygon([Point(pts[0].X - hw, pts[0].Y - hw), Point(pts[0].X + hw, pts[0].Y - hw),
                                                      Point(pts[0].X + hw, pts[0].Y + hw), Point(pts[0].X - hw, pts[0].Y + hw)]) }
                continue
            }
            let n = pts.count
            let segs = closed ? n : n - 1
            var k = 0
            while k < segs {
                let a = pts[k]
                let b = pts[(k + 1) % n]
                let nrm = normal(a, b, hw)
                out.addPolygon([Point(a.X + nrm.X, a.Y + nrm.Y), Point(b.X + nrm.X, b.Y + nrm.Y),
                                Point(b.X - nrm.X, b.Y - nrm.Y), Point(a.X - nrm.X, a.Y - nrm.Y)])
                k += 1
            }
            // Joins: at every corner of a closed contour, the inner ones of
            // an open one.
            var j = closed ? 0 : 1
            let lastJoin = closed ? n : n - 1
            while j < lastJoin {
                let prev = pts[(j - 1 + n) % n]
                let at = pts[j]
                let next = pts[(j + 1) % n]
                out.addJoin(prev, at, next, s, hw)
                j += 1
            }
            if !closed {
                out.addCap(pts[1], pts[0], s.Cap, hw)
                out.addCap(pts[n - 2], pts[n - 1], s.Cap, hw)
            }
        }
        return out
    }

    /// A closed polygon, wound counterclockwise (in y-down pixels) so all
    /// of a stroke's pieces add up.
    mutating func addPolygon(_ p: [Point]) {
        if p.count < 3 { return }
        var area: float32 = 0
        var i = 0
        while i < p.count {
            let a = p[i]
            let b = p[(i + 1) % p.count]
            area += a.X * b.Y - b.X * a.Y
            i += 1
        }
        if area < 0 {
            MoveTo(p[p.count - 1].X, p[p.count - 1].Y)
            var k = p.count - 2
            while k >= 0 {
                LineTo(p[k].X, p[k].Y)
                k -= 1
            }
        } else {
            MoveTo(p[0].X, p[0].Y)
            var k = 1
            while k < p.count {
                LineTo(p[k].X, p[k].Y)
                k += 1
            }
        }
        Close()
    }

    mutating func addCircle(_ c: Point, _ r: float32) {
        let steps = max(8, min(48, int(r * 3)))
        var p: [Point] = []
        var i = 0
        while i < steps {
            let t = float32(i) / float32(steps) * 2 * float32(math.Pi)
            p.append(Point(c.X + r * math.Cos(t), c.Y + r * math.Sin(t)))
            i += 1
        }
        addPolygon(p)
    }

    mutating func addJoin(_ prev: Point, _ at: Point, _ next: Point, _ s: Stroke, _ hw: float32) {
        if s.Join == .round {
            addCircle(at, hw)
            return
        }
        let n1 = normal(prev, at, hw)
        let n2 = normal(at, next, hw)
        // The outer side is the one the line turns away from.
        let d1x = at.X - prev.X
        let d1y = at.Y - prev.Y
        let d2x = next.X - at.X
        let d2y = next.Y - at.Y
        let cross = d1x * d2y - d1y * d2x
        if abs(cross) < 0.0001 { return }
        let sign: float32 = cross > 0 ? -1 : 1
        let a = Point(at.X + n1.X * sign, at.Y + n1.Y * sign)
        let b = Point(at.X + n2.X * sign, at.Y + n2.Y * sign)
        if s.Join == .miter {
            // Where the two outer edges meet.
            let l1 = math.Sqrt(d1x * d1x + d1y * d1y)
            let l2 = math.Sqrt(d2x * d2x + d2y * d2y)
            let cosTheta = -(d1x * d2x + d1y * d2y) / (l1 * l2)
            let ratio = 1 / math.Sqrt(max(0.000001, (1 - cosTheta) / 2))
            if ratio <= s.MiterLimit {
                let mx = (a.X + b.X) / 2 - at.X
                let my = (a.Y + b.Y) / 2 - at.Y
                let ml = math.Sqrt(mx * mx + my * my)
                if ml > 0.0001 {
                    let reach = hw * ratio
                    let m = Point(at.X + mx / ml * reach, at.Y + my / ml * reach)
                    addPolygon([at, a, m, b])
                    return
                }
            }
        }
        addPolygon([at, a, b])
    }

    /// A cap at end, the line arriving from from.
    mutating func addCap(_ from: Point, _ end: Point, _ cap: LineCap, _ hw: float32) {
        switch cap {
        case .butt:
            return
        case .round:
            addCircle(end, hw)
        case .square:
            let dx = end.X - from.X
            let dy = end.Y - from.Y
            let l = math.Sqrt(dx * dx + dy * dy)
            if l <= 0 { return }
            let ux = dx / l * hw
            let uy = dy / l * hw
            let nrm = normal(from, end, hw)
            addPolygon([Point(end.X + nrm.X, end.Y + nrm.Y), Point(end.X + nrm.X + ux, end.Y + nrm.Y + uy),
                        Point(end.X - nrm.X + ux, end.Y - nrm.Y + uy), Point(end.X - nrm.X, end.Y - nrm.Y)])
        }
    }
}

/// A segment's normal, hw long.
func normal(_ a: Point, _ b: Point, _ hw: float32) -> Point {
    let dx = b.X - a.X
    let dy = b.Y - a.Y
    let l = math.Sqrt(dx * dx + dy * dy)
    if l <= 0 { return Point(0, 0) }
    return Point(-dy / l * hw, dx / l * hw)
}

extension Canvas {
    /// Strokes a path in a color, anti-aliased, kept to the clip.
    public func StrokePath(_ path: Path, _ stroke: Stroke, _ color: Color) {
        FillPath(path.Stroked(stroke), rule: .nonZero, color)
    }
}
