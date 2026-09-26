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
/// points up and 90 to the right, and stops from 0 to 1.
public struct LinearGradient {
    public var Angle: float32
    public var Stops: [GradientStop]

    public init(angle: float32, stops: [GradientStop]) {
        Angle = angle
        Stops = stops
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
