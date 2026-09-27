package draw

/// One color of a gradient, at a fraction of its length.
public struct GradientStop {
    public var Color: Color
    public var Position: float32

    public init(_ color: Color, at position: float32) {
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

    public init(angle: float32, stops: [GradientStop]) {
        Angle = angle
        Stops = stops
    }
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
    public func Scaled(_ k: float32) -> RadialShape {
        var r = self
        r.SizeX *= k
        r.SizeY *= k
        r.OffsetX *= k
        r.OffsetY *= k
        return r
    }

    /// The centre and the ending shape's two radii within a rectangle.
    func resolve(_ x: float32, _ y: float32, _ w: float32, _ h: float32) -> (cx: float32, cy: float32, rx: float32, ry: float32) {
        let cx = x + w * CenterX + OffsetX
        let cy = y + h * CenterY + OffsetY
        let left = absf(cx - x)
        let right = absf(x + w - cx)
        let top = absf(cy - y)
        let bottom = absf(y + h - cy)
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
                let d = c_sqrtf(sx * sx + sy * sy)
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

@_silgen_name("sinf")
func c_sinf(_ x: float32) -> float32
@_silgen_name("cosf")
func c_cosf(_ x: float32) -> float32

extension Canvas {
    /// Fills a rectangle, its corners rounded, with a linear gradient.
    /// The gradient line runs through the rectangle's centre at the
    /// angle, long enough that the first stop touches one corner and
    /// the last the opposite, as CSS lays it.
    public func FillGradient(_ r: IRect, radii: Radii, _ g: LinearGradient) {
        if r.IsEmpty || g.Stops.isEmpty { return }
        if g.Stops.count == 1 {
            FillRounded(r, radii: radii, g.Stops[0].Color)
            return
        }
        let clipped = r.Intersect(Clip)
        if clipped.IsEmpty { return }
        if let shape = g.Radial {
            fillRadial(r, clipped: clipped, radii: radii, g, shape)
            return
        }
        let rad = g.Angle * 3.14159265 / 180
        let dx = c_sinf(rad)
        let dy = -c_cosf(rad)
        let w = float32(r.Width)
        let h = float32(r.Height)
        let length = absf(w * dx) + absf(h * dy)
        if length <= 0 { return }
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
                var t = (px * dx + py * dy) / length + 0.5
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
                        p.pointee = scalePacked(table[idx], a) &+ scalePacked(p.pointee, 255 - a)
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
    func fillRadial(_ r: IRect, clipped: IRect, radii: Radii, _ g: LinearGradient, _ radial: RadialShape) {
        let w = float32(r.Width)
        let h = float32(r.Height)
        let geo = radial.resolve(float32(r.X), float32(r.Y), w, h)
        // A degenerate shape has the last color everywhere.
        let rx = geo.rx > 0.01 ? geo.rx : 0.01
        let ry = geo.ry > 0.01 ? geo.ry : 0.01
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
                var t = c_sqrtf(dx * dx + dy * dy)
                if t > 1 { t = 1 }
                let idx = int(t * float32(steps - 1))
                var cov: int32 = 255
                if rounded { cov = shape.coverage(x, y) }
                if cov > 0 {
                    let a = mul255(alphas[idx], uint32(cov))
                    if a == 255 {
                        p.pointee = table[idx]
                    } else if a > 0 {
                        p.pointee = scalePacked(table[idx], a) &+ scalePacked(p.pointee, 255 - a)
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
func colorAt(_ stops: [GradientStop], _ t: float32) -> Color {
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

func mix(_ a: Color, _ b: Color, _ f: float32) -> Color {
    let g = 1 - f
    return Color(uint8(float32(a.R) * g + float32(b.R) * f + 0.5),
                 uint8(float32(a.G) * g + float32(b.G) * f + 0.5),
                 uint8(float32(a.B) * g + float32(b.B) * f + 0.5),
                 uint8(float32(a.A) * g + float32(b.A) * f + 0.5))
}
