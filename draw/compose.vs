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
}

extension Layer {
    /// Scales each pixel by a coverage from 0 to 255: what is outside a
    /// mask goes, what is at its edge fades.
    public func Mask(_ coverage: (int32, int32) -> int32) {
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
    public func MaskRounded(_ r: IRect, radii: Radii) {
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
    public func MaskPolygon(_ points: [Point]) {
        if points.count < 3 {
            Mask { _, _ in 0 }
            return
        }
        func inside(_ px: float32, _ py: float32) -> bool {
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
    public func MaskGradient(_ r: IRect, _ g: LinearGradient) {
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

    /// Fills the layer with what a canvas shows over the layer's
    /// rectangle: the backdrop a backdrop-filter works on.
    public func CopyFrom(_ c: Canvas) {
        let area = Rect.Intersect(c.Bounds)
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
func blendPixel(_ s: uint32, _ d: uint32, _ mode: BlendMode) -> uint32 {
    let sa = float32(s >> 24) / 255
    let da = float32(d >> 24) / 255
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

func blendChannel(_ cs: float32, _ cd: float32, _ mode: BlendMode) -> float32 {
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
