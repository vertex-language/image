package draw

import "math"

/// One color of a gradient, at a fraction of its length.
public struct GradientStop {
    public var Color: Color
    /// A fraction of the gradient line, -1 for none given (spread between
    /// its neighbours).
    public var Position: float32
    /// Pixels added to Position along the line: a stop at `20px`, or
    /// `calc(100% - 20px)`. Resolved once the line's length is known.
    public var Length: float32 = 0

    public init(color: Color, at position: float32) {
        self.Color = color
        Position = position
    }
}

/// A linear gradient as CSS describes one: an angle in degrees, where 0
/// points up and 90 to the right, and stops from 0 to 1. With Radial
/// set it's a radial gradient instead, the stops running from its
/// centre out to its ending shape.
public struct LinearGradient {
    public var Angle: float32
    public var Stops: [GradientStop]
    public var Radial: RadialShape? = nil
    /// A conic gradient's centre and starting angle: colors go round
    /// the centre, clockwise from Angle (0 up).
    public var Conic: ConicShape? = nil
    /// Whether the stops repeat past the last and before the first, as
    /// repeating-linear-gradient() and the rest do.
    public var Repeating: bool = false
    /// Some stop has a Length: its positions are fixed up (FixStops) only
    /// when the gradient is drawn and its line's length is known.
    public var Unresolved: bool = false

    public init(angle: float32, stops: [GradientStop]) {
        Angle = angle
        Stops = stops
    }

    /// The gradient for a canvas k device pixels to a CSS pixel: its
    /// shapes' and its stops' lengths scaled.
    public func Scaled(k: float32) -> LinearGradient {
        var g = self
        if let r = g.Radial { g.Radial = r.Scaled(k) }
        if let c = g.Conic { g.Conic = c.Scaled(k) }
        if g.Unresolved {
            var i = 0
            while i < g.Stops.count {
                g.Stops[i].Length *= k
                i += 1
            }
        }
        return g
    }

    /// The stops placed on a gradient line `length` pixels long: each
    /// stop's Length taken into its Position, then fixed up as CSS does.
    public func ResolvedFor(length: float32) -> LinearGradient {
        if !Unresolved { return self }
        var g = self
        g.Unresolved = false
        let line = length > 0.0001 ? length : 0.0001
        var i = 0
        while i < g.Stops.count {
            if g.Stops[i].Length != 0 {
                g.Stops[i].Position = (g.Stops[i].Position < 0 ? 0 : g.Stops[i].Position) + g.Stops[i].Length / line
                g.Stops[i].Length = 0
            }
            i += 1
        }
        FixStops(&g.Stops)
        return g
    }
}

/// CSS's fix-ups of stop positions: the first defaults to 0 and the last
/// to 1, the ones between without a position spread evenly between their
/// neighbours, and none before the one before it.
public func FixStops(stops: inout [GradientStop]) {
    if stops.isEmpty { return }
    if stops[0].Position < 0 { stops[0].Position = 0 }
    if stops[stops.count - 1].Position < 0 { stops[stops.count - 1].Position = 1 }
    var i = 1
    while i < stops.count - 1 {
        if stops[i].Position < 0 {
            var j = i + 1
            while j < stops.count && stops[j].Position < 0 { j += 1 }
            let from = stops[i - 1].Position
            let to = stops[j].Position
            let n = float32(j - i + 1)
            var m = i
            while m < j {
                stops[m].Position = from + (to - from) * float32(m - i + 1) / n
                m += 1
            }
            i = j
        } else {
            i += 1
        }
    }
    i = 1
    while i < stops.count {
        if stops[i].Position < stops[i - 1].Position { stops[i].Position = stops[i - 1].Position }
        i += 1
    }
}

/// Where a conic gradient's centre is: a fraction of the rectangle's
/// size, then moved by pixels.
public struct ConicShape {
    public var CenterX: float32 = 0.5
    public var CenterY: float32 = 0.5
    public var OffsetX: float32 = 0
    public var OffsetY: float32 = 0

    public init() {}

    public func Scaled(k: float32) -> ConicShape {
        var c = self
        c.OffsetX *= k
        c.OffsetY *= k
        return c
    }
}

/// t taken into the stops' span where the gradient repeats.
func wrapped(g: LinearGradient, t: float32) -> float32 {
    if !g.Repeating || g.Stops.count < 2 { return t }
    let lo = g.Stops[0].Position
    let span = g.Stops[g.Stops.count - 1].Position - lo
    if span <= 0.0001 { return t }
    return lo + math.FloorMod(t - lo, span)
}

/// How big a radial gradient's ending shape is, as CSS names it.
public enum RadialExtent: Equatable {
    case closestSide
    case closestCorner
    case farthestSide
    case farthestCorner
    /// SizeX and SizeY, in pixels.
    case sized
}

/// A radial gradient's centre and ending shape, resolved against the
/// rectangle it fills: the centre at a fraction of its size and then
/// moved by pixels, as background positions are.
public struct RadialShape {
    public var Circle: bool = false
    public var Extent: RadialExtent = .farthestCorner
    public var SizeX: float32 = 0
    public var SizeY: float32 = 0
    public var CenterX: float32 = 0.5
    public var CenterY: float32 = 0.5
    public var OffsetX: float32 = 0
    public var OffsetY: float32 = 0

    public init() {}

    /// The same shape at a scale: its pixel lengths multiplied.
    public func Scaled(k: float32) -> RadialShape {
        var r = self
        r.SizeX *= k
        r.SizeY *= k
        r.OffsetX *= k
        r.OffsetY *= k
        return r
    }

    /// The centre and the ending shape's two radii within a rectangle.
    func resolve(x: float32, y: float32, w: float32, h: float32) -> (cx: float32, cy: float32, rx: float32, ry: float32) {
        let cx = x + w * CenterX + OffsetX
        let cy = y + h * CenterY + OffsetY
        let left = math.Abs(cx - x)
        let right = math.Abs(x + w - cx)
        let top = math.Abs(cy - y)
        let bottom = math.Abs(y + h - cy)
        var sx: float32 = 0
        var sy: float32 = 0
        switch Extent {
        case .sized:
            return (cx: cx, cy: cy, rx: SizeX, ry: Circle ? SizeX : SizeY)
        case .closestSide, .closestCorner:
            sx = left < right ? left : right
            sy = top < bottom ? top : bottom
        case .farthestSide, .farthestCorner:
            sx = left > right ? left : right
            sy = top > bottom ? top : bottom
        }
        let corner = Extent == .closestCorner || Extent == .farthestCorner
        if Circle {
            if corner {
                let d = math.Sqrt(sx * sx + sy * sy)
                return (cx: cx, cy: cy, rx: d, ry: d)
            }
            let side = Extent == .closestSide ? (sx < sy ? sx : sy) : (sx > sy ? sx : sy)
            return (cx: cx, cy: cy, rx: side, ry: side)
        }
        // An ellipse through the corner keeps the sides' proportions.
        if corner { return (cx: cx, cy: cy, rx: sx * 1.41421356, ry: sy * 1.41421356) }
        return (cx: cx, cy: cy, rx: sx, ry: sy)
    }
}

extension Canvas {
    /// Fills a rectangle, its corners rounded, with a linear gradient.
    /// The gradient line runs through the rectangle's centre at the
    /// angle, long enough that the first stop touches one corner and
    /// the last the opposite, as CSS lays it.
    public func FillGradient(r: IRect, radii: Radii, gradient: LinearGradient) {
        if r.IsEmpty || gradient.Stops.isEmpty { return }
        if gradient.Stops.count == 1 {
            FillRounded(r, radii: radii, gradient.Stops[0].Color)
            return
        }
        let clipped = r.Intersect(Clip)
        if clipped.IsEmpty { return }
        if let shape = gradient.Radial {
            fillRadial(r, clipped: clipped, radii: radii, gradient, shape)
            return
        }
        if let conic = gradient.Conic {
            fillConic(r, clipped: clipped, radii: radii, gradient.ResolvedFor(1), conic)
            return
        }
        let rad = gradient.Angle * 3.14159265 / 180
        let dx = math.Sin(rad)
        let dy = -math.Cos(rad)
        let w = float32(r.Width)
        let h = float32(r.Height)
        let length = math.Abs(w * dx) + math.Abs(h * dy)
        if length <= 0 { return }
        // Stops at lengths, placed on this line.
        let g = gradient.ResolvedFor(length)
        let cx = float32(r.X) + w / 2
        let cy = float32(r.Y) + h / 2
        let fitted = radii.Fitted(w, h)
        let shape = RoundedRect(rect: r, radii: fitted)
        let rounded = !fitted.IsZero
        // Colors are looked up through a small table along the line.
        let steps = 256
        var table: [uint32] = []
        var alphas: [uint32] = []
        var i = 0
        while i < steps {
            let t = float32(i) / float32(steps - 1)
            let c = colorAt(g.Stops, t)
            table.append(c.Premultiplied())
            alphas.append(uint32(c.A))
            i += 1
        }
        var y = clipped.Y
        while y < clipped.Bottom {
            var p = rowPointer(y) + int(clipped.X)
            var x = clipped.X
            let py = float32(y) + 0.5 - cy
            while x < clipped.Right {
                let px = float32(x) + 0.5 - cx
                var t = wrapped(g, (px * dx + py * dy) / length + 0.5)
                if t < 0 { t = 0 }
                if t > 1 { t = 1 }
                let idx = int(t * float32(steps - 1))
                var cov: int32 = 255
                if rounded { cov = shape.coverage(x, y) }
                if cov > 0 {
                    let a = mul255(alphas[idx], uint32(cov))
                    if a == 255 {
                        p.pointee = table[idx]
                    } else if a > 0 {
                        p.pointee = scalePacked(table[idx], uint32(cov)) &+ scalePacked(p.pointee, 255 - a)
                    }
                }
                p = p + 1
                x += 1
            }
            y += 1
        }
    }
}

extension Canvas {
    /// A radial gradient: each pixel takes the color at its distance
    /// from the centre, as a fraction of the ending shape's radius, and
    /// past the shape the last stop's.
    func fillRadial(r: IRect, clipped: IRect, radii: Radii, gradient: LinearGradient, radial: RadialShape) {
        let w = float32(r.Width)
        let h = float32(r.Height)
        let geo = radial.resolve(float32(r.X), float32(r.Y), w, h)
        // A degenerate shape has the last color everywhere.
        let rx = geo.rx > 0.01 ? geo.rx : 0.01
        let ry = geo.ry > 0.01 ? geo.ry : 0.01
        // Stops at lengths, along the ray to the ending shape's edge.
        let g = gradient.ResolvedFor(rx)
        let fitted = radii.Fitted(w, h)
        let shape = RoundedRect(rect: r, radii: fitted)
        let rounded = !fitted.IsZero
        let steps = 256
        var table: [uint32] = []
        var alphas: [uint32] = []
        var i = 0
        while i < steps {
            let c = colorAt(g.Stops, float32(i) / float32(steps - 1))
            table.append(c.Premultiplied())
            alphas.append(uint32(c.A))
            i += 1
        }
        let ix = 1 / rx
        let iy = 1 / ry
        var y = clipped.Y
        while y < clipped.Bottom {
            var p = rowPointer(y) + int(clipped.X)
            var x = clipped.X
            let dy = (float32(y) + 0.5 - geo.cy) * iy
            while x < clipped.Right {
                let dx = (float32(x) + 0.5 - geo.cx) * ix
                var t = wrapped(g, math.Sqrt(dx * dx + dy * dy))
                if t > 1 { t = 1 }
                let idx = int(t * float32(steps - 1))
                var cov: int32 = 255
                if rounded { cov = shape.coverage(x, y) }
                if cov > 0 {
                    let a = mul255(alphas[idx], uint32(cov))
                    if a == 255 {
                        p.pointee = table[idx]
                    } else if a > 0 {
                        p.pointee = scalePacked(table[idx], uint32(cov)) &+ scalePacked(p.pointee, 255 - a)
                    }
                }
                p = p + 1
                x += 1
            }
            y += 1
        }
    }
}

extension Canvas {
    /// A conic gradient: each pixel takes the color at its angle round
    /// the centre, clockwise from the gradient's starting angle, as a
    /// fraction of a turn.
    func fillConic(r: IRect, clipped: IRect, radii: Radii, g: LinearGradient, conic: ConicShape) {
        let w = float32(r.Width)
        let h = float32(r.Height)
        let cx = float32(r.X) + w * conic.CenterX + conic.OffsetX
        let cy = float32(r.Y) + h * conic.CenterY + conic.OffsetY
        let fitted = radii.Fitted(w, h)
        let shape = RoundedRect(rect: r, radii: fitted)
        let rounded = !fitted.IsZero
        let steps = 512
        var table: [uint32] = []
        var alphas: [uint32] = []
        var i = 0
        while i < steps {
            let c = colorAt(g.Stops, float32(i) / float32(steps - 1))
            table.append(c.Premultiplied())
            alphas.append(uint32(c.A))
            i += 1
        }
        let from = g.Angle / 360
        var y = clipped.Y
        while y < clipped.Bottom {
            var p = rowPointer(y) + int(clipped.X)
            var x = clipped.X
            let dy = float32(y) + 0.5 - cy
            while x < clipped.Right {
                let dx = float32(x) + 0.5 - cx
                // Clockwise from up: atan2 of x over -y, as a turn.
                var turn = math.Atan2(dx, -dy) / (2 * 3.14159265)
                if turn < 0 { turn += 1 }
                var t = wrapped(g, math.FloorMod(turn - from, 1))
                if t < 0 { t = 0 }
                if t > 1 { t = 1 }
                let idx = int(t * float32(steps - 1))
                var cov: int32 = 255
                if rounded { cov = shape.coverage(x, y) }
                if cov > 0 {
                    let a = mul255(alphas[idx], uint32(cov))
                    if a == 255 {
                        p.pointee = table[idx]
                    } else if a > 0 {
                        p.pointee = scalePacked(table[idx], uint32(cov)) &+ scalePacked(p.pointee, 255 - a)
                    }
                }
                p = p + 1
                x += 1
            }
            y += 1
        }
    }
}

/// The color a gradient has at a fraction of its length.
func colorAt(stops: [GradientStop], t: float32) -> Color {
    if t <= stops[0].Position { return stops[0].Color }
    let last = stops[stops.count - 1]
    if t >= last.Position { return last.Color }
    var i = 1
    while i < stops.count {
        let a = stops[i - 1]
        let b = stops[i]
        if t <= b.Position {
            let span = b.Position - a.Position
            let f = span > 0 ? (t - a.Position) / span : 0
            return mix(a.Color, b.Color, f)
        }
        i += 1
    }
    return last.Color
}

func mix(a: Color, b: Color, f: float32) -> Color {
    let g = 1 - f
    return Color(uint8(float32(a.R) * g + float32(b.R) * f + 0.5),
                 uint8(float32(a.G) * g + float32(b.G) * f + 0.5),
                 uint8(float32(a.B) * g + float32(b.B) * f + 0.5),
                 uint8(float32(a.A) * g + float32(b.A) * f + 0.5))
}
