package draw

import "math"

// Compositing beyond a plain "over": masks that keep a layer only where
// a shape or a gradient's alpha covers it (CSS clip-path and
// mask-image), blend modes (mix-blend-mode), and reading back what a
// canvas already shows (backdrop-filter).

/// How a layer mixes with what is under it, as CSS's mix-blend-mode
/// names them.
public enum BlendMode: Equatable {
    case normal
    case multiply
    case screen
    case overlay
    case darken
    case lighten
    case colorDodge
    case colorBurn
    case hardLight
    case softLight
    case difference
    case exclusion
    case hue
    case saturation
    case color
    case luminosity
    case plusLighter
}

/// One step of CSS's filter: blur in pixels, an amount for the rest
/// (1 is unchanged for brightness, contrast, saturate and opacity, and
/// full for grayscale, invert and sepia), hue-rotate in degrees, and a
/// drop shadow's offset, blur and color.
public enum Filter: Equatable {
    case blur(float32)
    case brightness(float32)
    case contrast(float32)
    case grayscale(float32)
    case hueRotate(float32)
    case invert(float32)
    case opacity(float32)
    case saturate(float32)
    case sepia(float32)
    case dropShadow(float32, float32, float32, Color)

    /// The filter with its lengths at a canvas's scale.
    public func Scaled(s: float32) -> Filter {
        switch self {
        case .blur(let r): return .blur(r * s)
        case .dropShadow(let x, let y, let r, let c): return .dropShadow(x * s, y * s, r * s, c)
        default: return self
        }
    }

    /// How far past a box the filter can paint, in the filter's own units.
    public var Reach: float32 {
        switch self {
        case .blur(let r): return r * 3
        case .dropShadow(let x, let y, let r, _): return math.Max(math.Abs(x), math.Abs(y)) + r * 3
        default: return 0
        }
    }
}

extension Layer {
    /// Colors the layer: each pixel takes the color asked of its position,
    /// scaled by the pixel's own alpha. A gradient over a shape drawn white.
    public func Shade(color: (int32, int32) -> Color) {
        var y = Rect.Y
        while y < Rect.Bottom {
            var p = pixels + int((y - Rect.Y) * Rect.Width)
            var x = Rect.X
            while x < Rect.Right {
                let a = p.pointee >> 24
                if a != 0 { p.pointee = scalePacked(color(x, y).Premultiplied(), a) }
                p = p + 1
                x += 1
            }
            y += 1
        }
    }

    /// Runs filters over the layer, in order.
    public func Apply(filters: [Filter]) {
        for f in filters {
            switch f {
            case .blur(let r): Blur(r)
            case .dropShadow(let x, let y, let r, let c): dropShadow(x, y, r, c)
            default:
                if let m = matrixOf(f) { applyMatrix(m) }
            }
        }
    }

    /// Multiplies each pixel's unpremultiplied color by a matrix of four
    /// rows of five (r g b a and an offset), alpha by the last row.
    func applyMatrix(m: [float32]) {
        var p = pixels
        let count = int(Rect.Width) * int(Rect.Height)
        var i = 0
        while i < count {
            let v = p.pointee
            let a = float32(v >> 24) / 255
            if a > 0 {
                let r = float32(v & 0xFF) / 255 / a
                let g = float32((v >> 8) & 0xFF) / 255 / a
                let b = float32((v >> 16) & 0xFF) / 255 / a
                let na = math.Clamp(m[15] * r + m[16] * g + m[17] * b + m[18] * a + m[19], 0, 1)
                let nr = math.Clamp(m[0] * r + m[1] * g + m[2] * b + m[3] * a + m[4], 0, 1) * na
                let ng = math.Clamp(m[5] * r + m[6] * g + m[7] * b + m[8] * a + m[9], 0, 1) * na
                let nb = math.Clamp(m[10] * r + m[11] * g + m[12] * b + m[13] * a + m[14], 0, 1) * na
                p.pointee = uint32(nr * 255 + 0.5) | uint32(ng * 255 + 0.5) << 8 | uint32(nb * 255 + 0.5) << 16 | uint32(na * 255 + 0.5) << 24
            }
            p = p + 1
            i += 1
        }
    }

    /// Puts a blurred, tinted copy of the layer's alpha under it, moved
    /// by an offset. What is moved past the layer's edge is lost.
    func dropShadow(x: float32, y: float32, r: float32, c: Color) {
        let shadow = Layer(Rect)
        let tint = c.Premultiplied()
        let ox = RoundToInt(x)
        let oy = RoundToInt(y)
        var py = Rect.Y
        while py < Rect.Bottom {
            var px = Rect.X
            while px < Rect.Right {
                let sx = px - ox
                let sy = py - oy
                if Rect.Contains(sx, sy) {
                    let a = at(sx, sy) >> 24
                    if a > 0 { (shadow.pixels + int((py - Rect.Y) * Rect.Width + (px - Rect.X))).pointee = scalePacked(tint, a) }
                }
                px += 1
            }
            py += 1
        }
        shadow.Blur(r)
        // The layer over its shadow.
        var p = pixels
        var q = shadow.pixels
        let count = int(Rect.Width) * int(Rect.Height)
        var i = 0
        while i < count {
            let s = p.pointee
            p.pointee = s &+ scalePacked(q.pointee, 255 - (s >> 24))
            p = p + 1
            q = q + 1
            i += 1
        }
        shadow.Free()
    }
    /// Scales each pixel by a coverage from 0 to 255: what is outside a
    /// mask goes, what is at its edge fades.
    public func Mask(coverage: (int32, int32) -> int32) {
        var y = Rect.Y
        while y < Rect.Bottom {
            var p = pixels + int((y - Rect.Y) * Rect.Width)
            var x = Rect.X
            while x < Rect.Right {
                let v = p.pointee
                if v != 0 {
                    let c = coverage(x, y)
                    if c <= 0 { p.pointee = 0 } else if c < 255 { p.pointee = scalePacked(v, uint32(c)) }
                }
                p = p + 1
                x += 1
            }
            y += 1
        }
    }

    /// Keeps the layer inside a rounded rectangle.
    public func MaskRounded(r: IRect, radii: Radii) {
        let shape = RoundedRect(rect: r, radii: radii.Fitted(float32(r.Width), float32(r.Height)))
        Mask { x, y in shape.coverage(x, y) }
    }

    /// Keeps the layer inside an ellipse, its edge smoothed over a pixel.
    public func MaskEllipse(cx: float32, cy: float32, rx: float32, ry: float32) {
        if rx <= 0 || ry <= 0 {
            Mask { _, _ in 0 }
            return
        }
        let edge = math.Min(rx, ry)
        Mask { x, y in
            let dx = (float32(x) + 0.5 - cx) / rx
            let dy = (float32(y) + 0.5 - cy) / ry
            let d = math.Sqrt(dx * dx + dy * dy)
            // Distance past the edge, in pixels, near enough.
            let past = (d - 1) * edge
            if past <= -0.5 { return 255 }
            if past >= 0.5 { return 0 }
            return int32((0.5 - past) * 255)
        }
    }

    /// Keeps the layer inside a polygon (nonzero winding), each pixel
    /// sampled at four points for a smooth edge.
    public func MaskPolygon(points: [Point]) {
        if points.count < 3 {
            Mask { _, _ in 0 }
            return
        }
        func inside(px: float32, py: float32) -> bool {
            var winding = 0
            var i = 0
            while i < points.count {
                let a = points[i]
                let b = points[(i + 1) % points.count]
                if a.Y <= py {
                    if b.Y > py && (b.X - a.X) * (py - a.Y) - (px - a.X) * (b.Y - a.Y) > 0 { winding += 1 }
                } else if b.Y <= py && (b.X - a.X) * (py - a.Y) - (px - a.X) * (b.Y - a.Y) < 0 {
                    winding -= 1
                }
                i += 1
            }
            return winding != 0
        }
        Mask { x, y in
            var n: int32 = 0
            let fx = float32(x)
            let fy = float32(y)
            if inside(fx + 0.25, fy + 0.25) { n += 1 }
            if inside(fx + 0.75, fy + 0.25) { n += 1 }
            if inside(fx + 0.25, fy + 0.75) { n += 1 }
            if inside(fx + 0.75, fy + 0.75) { n += 1 }
            return n * 255 / 4
        }
    }

    /// Keeps the layer as much as a gradient over r is opaque: a
    /// mask-image of linear-gradient(black, transparent) fades it out.
    /// Outside r nothing is kept.
    public func MaskGradient(r: IRect, g: LinearGradient) {
        let area = r.Intersect(Rect)
        if area.IsEmpty {
            Mask { _, _ in 0 }
            return
        }
        let alpha = Layer(area)
        alpha.Canvas.FillGradient(r, radii: Radii.zero, g)
        Mask { x, y in
            if !area.Contains(x, y) { return 0 }
            return int32(alpha.at(x, y) >> 24)
        }
        alpha.Free()
    }

    /// Keeps the layer as much as another layer is opaque at each pixel:
    /// a mask image drawn into a layer of its own. Outside that layer
    /// nothing is kept.
    public func MaskBy(alpha: Layer) {
        Mask { x, y in
            if !alpha.Rect.Contains(x, y) { return 0 }
            return int32(alpha.at(x, y) >> 24)
        }
    }

    /// Keeps the layer as much as another layer is bright at each pixel
    /// (its luminance, premultiplied: dark or transparent hides): a
    /// mask in mask-mode: luminance.
    public func MaskByLuminance(m: Layer) {
        Mask { x, y in
            if !m.Rect.Contains(x, y) { return 0 }
            let v = m.at(x, y)
            let r = float32(v & 0xFF)
            let g = float32((v >> 8) & 0xFF)
            let b = float32((v >> 16) & 0xFF)
            return int32(0.2126 * r + 0.7152 * g + 0.0722 * b + 0.5)
        }
    }

    /// Fills the layer with what a canvas shows over the layer's
    /// rectangle, within the canvas's clip: the backdrop a
    /// backdrop-filter works on. (A layer's own canvas addresses only
    /// its clip.)
    public func CopyFrom(c: Canvas) {
        let area = Rect.Intersect(c.Clip)
        if area.IsEmpty { return }
        var y = area.Y
        while y < area.Bottom {
            var src = c.rowPointer(y) + int(area.X)
            var dst = pixels + int((y - Rect.Y) * Rect.Width + (area.X - Rect.X))
            var x = area.X
            while x < area.Right {
                dst.pointee = src.pointee
                src = src + 1
                dst = dst + 1
                x += 1
            }
            y += 1
        }
    }

    /// Paints the layer onto a canvas through a transform, mixed with
    /// what is there by a blend mode.
    public func Composite(onto c: Canvas, transform t: Affine, blend: BlendMode) {
        if blend == .normal {
            Composite(onto: c, transform: t)
            return
        }
        guard let inv = t.Inverted() else { return }
        let src = draw.Rect(float32(Rect.X), float32(Rect.Y), float32(Rect.Width), float32(Rect.Height))
        let b = t.Bounds(src)
        let area = IRect(int32(math.Floor(b.X)), int32(math.Floor(b.Y)), int32(math.Ceil(b.Right)) - int32(math.Floor(b.X)),
                         int32(math.Ceil(b.Bottom)) - int32(math.Floor(b.Y))).Intersect(c.Clip)
        if area.IsEmpty { return }
        let plain = t.IsIdentity
        var y = area.Y
        while y < area.Bottom {
            var dst = c.rowPointer(y) + int(area.X)
            var x = area.X
            while x < area.Right {
                var s: uint32 = 0
                if plain {
                    s = at(x, y)
                } else {
                    let p = inv.Apply(float32(x) + 0.5, float32(y) + 0.5)
                    s = sample(p.x - 0.5, p.y - 0.5)
                }
                if s >> 24 != 0 { dst.pointee = blendPixel(s, dst.pointee, blend) }
                dst = dst + 1
                x += 1
            }
            y += 1
        }
    }
}

/// A premultiplied source pixel over a premultiplied destination, mixed
/// by a blend mode: s(1-da) + d(1-sa) + B(cs, cd) sa da, channel by
/// channel.
func blendPixel(s: uint32, d: uint32, mode: BlendMode) -> uint32 {
    let sa = float32(s >> 24) / 255
    let da = float32(d >> 24) / 255
    if mode == .plusLighter {
        // s + d, each channel and alpha, clamped.
        var sum: uint32 = 0
        var at: uint32 = 0
        while at < 32 {
            let v = ((s >> at) & 0xFF) + ((d >> at) & 0xFF)
            sum |= (v > 255 ? 255 : v) << at
            at += 8
        }
        return sum
    }
    if mode == .hue || mode == .saturation || mode == .color || mode == .luminosity {
        return blendNonSeparable(s, d, sa, da, mode)
    }
    var out: uint32 = 0
    var shift: uint32 = 0
    while shift < 24 {
        let sc = float32((s >> shift) & 0xFF) / 255
        let dc = float32((d >> shift) & 0xFF) / 255
        // Unpremultiplied colors for the blend function.
        let cs = sa > 0 ? sc / sa : 0
        let cd = da > 0 ? dc / da : 0
        let mixed = blendChannel(cs, cd, mode)
        let v = sc * (1 - da) + dc * (1 - sa) + mixed * sa * da
        out |= uint32(math.Clamp(v, 0, 1) * 255 + 0.5) << shift
        shift += 8
    }
    let a = sa + da - sa * da
    out |= uint32(math.Clamp(a, 0, 1) * 255 + 0.5) << 24
    return out
}

/// The blend modes that mix a pixel's three channels together, as
/// Compositing and Blending names them.
func blendNonSeparable(s: uint32, d: uint32, sa: float32, da: float32, mode: BlendMode) -> uint32 {
    func channels(v: uint32, a: float32) -> (float32, float32, float32) {
        if a <= 0 { return (0, 0, 0) }
        return (float32(v & 0xFF) / 255 / a, float32((v >> 8) & 0xFF) / 255 / a, float32((v >> 16) & 0xFF) / 255 / a)
    }
    let cs = channels(s, sa)
    let cd = channels(d, da)
    var mixed = cs
    switch mode {
    case .hue: mixed = setLum(setSat(cs, satOf(cd)), lumOf(cd))
    case .saturation: mixed = setLum(setSat(cd, satOf(cs)), lumOf(cd))
    case .color: mixed = setLum(cs, lumOf(cd))
    default: mixed = setLum(cd, lumOf(cs))
    }
    func channel(shift: uint32, m: float32) -> uint32 {
        let sc = float32((s >> shift) & 0xFF) / 255
        let dc = float32((d >> shift) & 0xFF) / 255
        let v = sc * (1 - da) + dc * (1 - sa) + m * sa * da
        return uint32(math.Clamp(v, 0, 1) * 255 + 0.5) << shift
    }
    let a = sa + da - sa * da
    return channel(0, mixed.0) | channel(8, mixed.1) | channel(16, mixed.2) | uint32(math.Clamp(a, 0, 1) * 255 + 0.5) << 24
}

func lumOf(c: (float32, float32, float32)) -> float32 {
    return 0.3 * c.0 + 0.59 * c.1 + 0.11 * c.2
}

func satOf(c: (float32, float32, float32)) -> float32 {
    return math.Max(c.0, math.Max(c.1, c.2)) - math.Min(c.0, math.Min(c.1, c.2))
}

func setLum(c: (float32, float32, float32), l: float32) -> (float32, float32, float32) {
    let d = l - lumOf(c)
    return clipColor((c.0 + d, c.1 + d, c.2 + d))
}

func clipColor(c: (float32, float32, float32)) -> (float32, float32, float32) {
    let l = lumOf(c)
    let lo = math.Min(c.0, math.Min(c.1, c.2))
    let hi = math.Max(c.0, math.Max(c.1, c.2))
    var out = c
    if lo < 0 {
        let k = l / (l - lo)
        out = (l + (out.0 - l) * k, l + (out.1 - l) * k, l + (out.2 - l) * k)
    }
    if hi > 1 {
        let k = (1 - l) / (hi - l)
        out = (l + (out.0 - l) * k, l + (out.1 - l) * k, l + (out.2 - l) * k)
    }
    return out
}

func setSat(c: (float32, float32, float32), s: float32) -> (float32, float32, float32) {
    let lo = math.Min(c.0, math.Min(c.1, c.2))
    let hi = math.Max(c.0, math.Max(c.1, c.2))
    if hi <= lo { return (0, 0, 0) }
    let k = s / (hi - lo)
    return ((c.0 - lo) * k, (c.1 - lo) * k, (c.2 - lo) * k)
}

/// A filter's color matrix, as Filter Effects defines them; nil for blur
/// and drop-shadow.
func matrixOf(f: Filter) -> [float32]? {
    switch f {
    case .brightness(let k):
        return [k, 0, 0, 0, 0, 0, k, 0, 0, 0, 0, 0, k, 0, 0, 0, 0, 0, 1, 0]
    case .contrast(let k):
        let o = 0.5 - 0.5 * k
        return [k, 0, 0, 0, o, 0, k, 0, 0, o, 0, 0, k, 0, o, 0, 0, 0, 1, 0]
    case .invert(let k):
        let m = 1 - 2 * k
        return [m, 0, 0, 0, k, 0, m, 0, 0, k, 0, 0, m, 0, k, 0, 0, 0, 1, 0]
    case .opacity(let k):
        return [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, k, 0]
    case .grayscale(let amount):
        let k = 1 - amount
        return [0.2126 + 0.7874 * k, 0.7152 - 0.7152 * k, 0.0722 - 0.0722 * k, 0, 0,
                0.2126 - 0.2126 * k, 0.7152 + 0.2848 * k, 0.0722 - 0.0722 * k, 0, 0,
                0.2126 - 0.2126 * k, 0.7152 - 0.7152 * k, 0.0722 + 0.9278 * k, 0, 0,
                0, 0, 0, 1, 0]
    case .sepia(let amount):
        let k = 1 - amount
        return [0.393 + 0.607 * k, 0.769 - 0.769 * k, 0.189 - 0.189 * k, 0, 0,
                0.349 - 0.349 * k, 0.686 + 0.314 * k, 0.168 - 0.168 * k, 0, 0,
                0.272 - 0.272 * k, 0.534 - 0.534 * k, 0.131 + 0.869 * k, 0, 0,
                0, 0, 0, 1, 0]
    case .saturate(let k):
        return [0.213 + 0.787 * k, 0.715 - 0.715 * k, 0.072 - 0.072 * k, 0, 0,
                0.213 - 0.213 * k, 0.715 + 0.285 * k, 0.072 - 0.072 * k, 0, 0,
                0.213 - 0.213 * k, 0.715 - 0.715 * k, 0.072 + 0.928 * k, 0, 0,
                0, 0, 0, 1, 0]
    case .hueRotate(let degrees):
        let rad = degrees * 3.14159265 / 180
        let c = math.Cos(rad)
        let n = math.Sin(rad)
        return [0.213 + c * 0.787 - n * 0.213, 0.715 - c * 0.715 - n * 0.715, 0.072 - c * 0.072 + n * 0.928, 0, 0,
                0.213 - c * 0.213 + n * 0.143, 0.715 + c * 0.285 + n * 0.140, 0.072 - c * 0.072 - n * 0.283, 0, 0,
                0.213 - c * 0.213 - n * 0.787, 0.715 - c * 0.715 + n * 0.715, 0.072 + c * 0.928 + n * 0.072, 0, 0,
                0, 0, 0, 1, 0]
    default:
        return nil
    }
}

func blendChannel(cs: float32, cd: float32, mode: BlendMode) -> float32 {
    switch mode {
    case .multiply: return cs * cd
    case .screen: return cs + cd - cs * cd
    case .overlay: return blendChannel(cd, cs, .hardLight)
    case .darken: return math.Min(cs, cd)
    case .lighten: return math.Max(cs, cd)
    case .colorDodge:
        if cd == 0 { return 0 }
        if cs >= 1 { return 1 }
        return math.Min(1, cd / (1 - cs))
    case .colorBurn:
        if cd >= 1 { return 1 }
        if cs <= 0 { return 0 }
        return 1 - math.Min(1, (1 - cd) / cs)
    case .hardLight:
        return cs <= 0.5 ? cd * 2 * cs : blendChannel(2 * cs - 1, cd, .screen)
    case .softLight:
        if cs <= 0.5 { return cd - (1 - 2 * cs) * cd * (1 - cd) }
        let dd = cd <= 0.25 ? ((16 * cd - 12) * cd + 4) * cd : math.Sqrt(cd)
        return cd + (2 * cs - 1) * (dd - cd)
    case .difference: return math.Abs(cs - cd)
    case .exclusion: return cs + cd - 2 * cs * cd
    default: return cs
    }
}
