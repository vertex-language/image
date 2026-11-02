package draw

import "math"

// An SVG <filter> as what it is: primitives that take named inputs and leave
// named results, each cut to a region, worked out in a color space of its own.

/// Where a filter primitive's input comes from.
public enum FilterInput: Equatable {
    case previous
    case source
    case sourceAlpha
    case named(string)
    case none
}

public enum CompositeOp: Equatable {
    case over
    case in_
    case out
    case atop
    case xor
    case lighter
    case arithmetic(float32, float32, float32, float32)
}

/// One color channel's feFunc.
public enum ChannelTransfer: Equatable {
    case identity
    case table([float32])
    case discrete([float32])
    case linear(float32, float32)
    case gamma(float32, float32, float32)
}

public enum LightSource: Equatable {
    /// Azimuth and elevation, in radians.
    case distant(float32, float32)
    case point(float32, float32, float32)
    /// Where it is, what it points at, its specular exponent and its cone's
    /// half angle in radians, or a negative number for none.
    case spot(float32, float32, float32, float32, float32, float32, float32, float32)
}

public enum FilterOp: Equatable {
    case blur(float32, float32)
    /// Any of the single-input filters CSS has too.
    case simple(Filter)
    case flood(Color)
    case blend(BlendMode)
    case composite(CompositeOp)
    case merge([FilterInput])
    case transfer(ChannelTransfer, ChannelTransfer, ChannelTransfer, ChannelTransfer)
    /// x and y radii, and whether it dilates.
    case morphology(float32, float32, bool)
    case tile
    /// Base frequencies x and y, octaves, seed, and whether it's fractal noise.
    case turbulence(float32, float32, int32, int32, bool)
    /// Scale, and which channels of the map move x and y (0 r, 1 g, 2 b, 3 a).
    case displacement(float32, int32, int32)
    /// Columns, rows, the kernel, divisor, bias, target column and row, and
    /// whether alpha stays as it was.
    case convolve(int32, int32, [float32], float32, float32, int32, int32, bool)
    /// Surface scale, constant, the light's color, the light, and for
    /// specular light its exponent; a negative one means diffuse.
    case lighting(float32, float32, Color, LightSource, float32)
}

public struct FilterStep: Equatable {
    public var Op: FilterOp
    public var In: FilterInput = .previous
    public var In2: FilterInput = .none
    public var Result: string = ""
    /// The primitive's subregion, as far as it says; in user units, or
    /// fractions of the box under primitiveUnits="objectBoundingBox".
    public var X: float32? = nil
    public var Y: float32? = nil
    public var Width: float32? = nil
    public var Height: float32? = nil
    /// color-interpolation-filters: linearRGB, which is its default.
    public var Linear: bool = true

    public init(op: FilterOp) {
        Op = op
    }

    /// The step with its lengths multiplied.
    func lengthsScaled(s: float32) -> FilterStep {
        var out = self
        switch Op {
        case .blur(let x, let y): out.Op = .blur(x * s, y * s)
        case .simple(let f): out.Op = .simple(f.Scaled(s))
        case .morphology(let x, let y, let dilate): out.Op = .morphology(x * s, y * s, dilate)
        case .displacement(let k, let x, let y): out.Op = .displacement(k * s, x, y)
        case .lighting(let k, let c, let color, let light, let e):
            var moved = light
            switch light {
            case .point(let x, let y, let z): moved = .point(x * s, y * s, z * s)
            case .spot(let x, let y, let z, let tx, let ty, let tz, let f, let cone):
                moved = .spot(x * s, y * s, z * s, tx * s, ty * s, tz * s, f, cone)
            default: break
            }
            out.Op = .lighting(k * s, c, color, moved, e)
        default: break
        }
        return out
    }
}

public struct FilterGraph: Equatable {
    public var Steps: [FilterStep] = []
    /// The filter region: fractions of the box, or under
    /// filterUnits="userSpaceOnUse", user units.
    public var X: float32 = -0.1
    public var Y: float32 = -0.1
    public var Width: float32 = 1.2
    public var Height: float32 = 1.2
    public var RegionInBox: bool = true
    public var StepsInBox: bool = false
    /// How many canvas pixels a user unit is.
    public var Scale: float32 = 1

    public init() {}

    func scaled(s: float32) -> FilterGraph {
        var out = self
        out.Scale = Scale * s
        if !RegionInBox {
            out.X = X * s
            out.Y = Y * s
            out.Width = Width * s
            out.Height = Height * s
        }
        if StepsInBox { return out }
        out.Steps = []
        for step in Steps {
            var scaledStep = step.lengthsScaled(s)
            if let v = step.X { scaledStep.X = v * s }
            if let v = step.Y { scaledStep.Y = v * s }
            if let v = step.Width { scaledStep.Width = v * s }
            if let v = step.Height { scaledStep.Height = v * s }
            out.Steps.append(scaledStep)
        }
        return out
    }

    /// The filter region on a canvas, for a box whose user space starts at an
    /// origin.
    func region(box: IRect, originX: float32, originY: float32) -> IRect {
        if RegionInBox {
            return roundedOut(float32(box.X) + X * float32(box.Width), float32(box.Y) + Y * float32(box.Height), Width * float32(box.Width), Height * float32(box.Height))
        }
        return roundedOut(originX + X, originY + Y, Width, Height)
    }

    /// A primitive's subregion: what it doesn't say is the filter region's.
    func subregion(step: FilterStep, of region: IRect, box: IRect, originX: float32, originY: float32) -> IRect {
        if step.X == nil && step.Y == nil && step.Width == nil && step.Height == nil { return region }
        var x = float32(region.X)
        var y = float32(region.Y)
        var w = float32(region.Width)
        var h = float32(region.Height)
        if StepsInBox {
            if let v = step.X { x = float32(box.X) + v * float32(box.Width) }
            if let v = step.Y { y = float32(box.Y) + v * float32(box.Height) }
            if let v = step.Width { w = v * float32(box.Width) }
            if let v = step.Height { h = v * float32(box.Height) }
        } else {
            if let v = step.X { x = originX + v }
            if let v = step.Y { y = originY + v }
            if let v = step.Width { w = v }
            if let v = step.Height { h = v }
        }
        return roundedOut(x, y, w, h).Intersect(region)
    }
}

func roundedOut(x: float32, y: float32, w: float32, h: float32) -> IRect {
    let x0 = int32(math.Floor(x))
    let y0 = int32(math.Floor(y))
    return IRect(x0, y0, int32(math.Ceil(x + w)) - x0, int32(math.Ceil(y + h)) - y0)
}

extension Filter {
    /// How far past a box the filter paints: a graph, to its region.
    public func ReachOver(box: IRect, originX: float32, originY: float32) -> float32 {
        guard case .graph(let g) = self else { return Reach }
        let r = g.region(box, originX: originX, originY: originY)
        var out: float32 = 0
        out = math.Max(out, float32(box.X - r.X))
        out = math.Max(out, float32(box.Y - r.Y))
        out = math.Max(out, float32(r.Right - box.Right))
        out = math.Max(out, float32(r.Bottom - box.Bottom))
        return out
    }
}

/// A primitive's result, and the region it was made for.
struct filterResult {
    let layer: Layer
    let region: IRect

    init(layer: Layer, region: IRect) {
        self.layer = layer
        self.region = region
    }
}

func linearTable(toLinear: bool) -> [uint8] {
    var out: [uint8] = []
    var i = 0
    while i < 256 {
        let v = float32(i) / 255
        var m: float32 = 0
        if toLinear {
            m = v <= 0.04045 ? v / 12.92 : math.Pow((v + 0.055) / 1.055, 2.4)
        } else {
            m = v <= 0.0031308 ? v * 12.92 : 1.055 * math.Pow(v, 1 / 2.4) - 0.055
        }
        out.append(uint8(math.Clamp(m, 0, 1) * 255 + 0.5))
        i += 1
    }
    return out
}

func unpremultiplied(v: uint32) -> (r: float32, g: float32, b: float32, a: float32) {
    let a = float32(v >> 24) / 255
    if a <= 0 { return (r: 0, g: 0, b: 0, a: 0) }
    func channel(c: uint32) -> float32 { return math.Min(float32(c) / 255 / a, 1) }
    return (r: channel(v & 0xFF), g: channel((v >> 8) & 0xFF), b: channel((v >> 16) & 0xFF), a: a)
}

func premultiplied(r: float32, g: float32, b: float32, a: float32) -> uint32 {
    func bits(c: float32) -> uint32 { return uint32(math.Clamp(c, 0, 1) * a * 255 + 0.5) }
    return bits(r) | bits(g) << 8 | bits(b) << 16 | uint32(math.Clamp(a, 0, 1) * 255 + 0.5) << 24
}

extension Layer {
    func copyOf() -> Layer {
        let out = Layer(Rect)
        out.takePixels(of: self)
        return out
    }

    func takePixels(of o: Layer) {
        let count = int(Rect.Width) * int(Rect.Height)
        var i = 0
        while i < count {
            (pixels + i).pointee = (o.pixels + i).pointee
            i += 1
        }
    }

    func put(x: int32, y: int32, v: uint32) {
        (pixels + int((y - Rect.Y) * Rect.Width + (x - Rect.X))).pointee = v
    }

    /// Clears everything outside a rectangle.
    func keepOnly(area: IRect) {
        var y = Rect.Y
        while y < Rect.Bottom {
            var x = Rect.X
            while x < Rect.Right {
                if !area.Contains(x, y) { put(x, y, 0) }
                x += 1
            }
            y += 1
        }
    }

    /// Each color channel through a table, by its unpremultiplied value.
    func mapped(table: [uint8]) -> Layer {
        let out = Layer(Rect)
        let count = int(Rect.Width) * int(Rect.Height)
        var i = 0
        while i < count {
            let v = (pixels + i).pointee
            let a = v >> 24
            if a > 0 {
                func one(c: uint32) -> uint32 {
                    let u = c * 255 / a
                    return (uint32(table[u > 255 ? 255 : int(u)]) * a + 127) / 255
                }
                (out.pixels + i).pointee = one(v & 0xFF) | one((v >> 8) & 0xFF) << 8 | one((v >> 16) & 0xFF) << 16 | a << 24
            }
            i += 1
        }
        return out
    }

    /// Runs a filter graph over the layer. box is what's being filtered, on
    /// the same canvas, and its user space starts at the origin.
    func applyGraph(g: FilterGraph, box: IRect, originX: float32, originY: float32) {
        let region = g.region(box, originX: originX, originY: originY)
        if g.Steps.isEmpty {
            // A filter with nothing in it leaves nothing.
            keepOnly(IRect.zero)
            return
        }
        let source = copyOf()
        source.keepOnly(region)
        let alpha = Layer(Rect)
        let count = int(Rect.Width) * int(Rect.Height)
        var i = 0
        while i < count {
            (alpha.pixels + i).pointee = (source.pixels + i).pointee & 0xFF000000
            i += 1
        }
        let toLinear = linearTable(toLinear: true)
        let toSRGB = linearTable(toLinear: false)
        var made: [Layer] = [source, alpha]
        var named: [string: filterResult] = [:]
        var last = filterResult(layer: source, region: region)
        func resolved(input: FilterInput) -> filterResult {
            switch input {
            case .previous: return last
            case .source: return filterResult(layer: source, region: region)
            case .sourceAlpha: return filterResult(layer: alpha, region: region)
            case .named(let name):
                if let r = named[name] { return r }
                // A name nothing left means what came before.
                return last
            case .none: return last
            }
        }
        for step0 in g.Steps {
            // Lengths in fractions of the box: the box's own size now.
            let step = g.StepsInBox ? step0.lengthsScaled(float32(box.Width)) : step0
            let area = g.subregion(step, of: region, box: box, originX: originX, originY: originY)
            let a = resolved(step.In)
            let b = resolved(step.In2)
            var mergers: [filterResult] = []
            if case .merge(let inputs) = step.Op {
                for input in inputs { mergers.append(resolved(input)) }
            }
            var inLinear = step.Linear
            switch step.Op {
            case .flood(_), .tile, .morphology(_, _, _): inLinear = false
            case .simple(let f):
                if case .offset(_, _) = f { inLinear = false }
            default: break
            }
            var first = a.layer
            var second = b.layer
            var parts: [Layer] = []
            for m in mergers { parts.append(m.layer) }
            var temps: [Layer] = []
            if inLinear {
                first = a.layer.mapped(toLinear)
                second = b.layer.mapped(toLinear)
                temps.append(first)
                temps.append(second)
                var i = 0
                while i < parts.count {
                    let p = parts[i].mapped(toLinear)
                    temps.append(p)
                    parts[i] = p
                    i += 1
                }
            }
            var out = Layer(Rect)
            runStep(step.Op, in: first, in2: second, parts: parts, source: a, area: area, into: out, scale: g.Scale, originX: originX, originY: originY)
            if inLinear {
                let back = out.mapped(toSRGB)
                out.Free()
                out = back
            }
            for t in temps { t.Free() }
            out.keepOnly(area)
            made.append(out)
            last = filterResult(layer: out, region: area)
            if !step.Result.isEmpty { named[step.Result] = last }
        }
        takePixels(of: last.layer)
        for m in made { m.Free() }
    }

    func runStep(op: FilterOp, in first: Layer, in2 second: Layer, parts: [Layer], source: filterResult, area: IRect, into out: Layer, scale: float32, originX: float32, originY: float32) {
        let count = int(Rect.Width) * int(Rect.Height)
        switch op {
        case .blur(let x, let y):
            out.takePixels(of: first)
            out.Blur(x, y)
        case .simple(let f):
            out.takePixels(of: first)
            out.Apply([f])
        case .flood(let c):
            let v = c.Premultiplied()
            var i = 0
            while i < count {
                (out.pixels + i).pointee = v
                i += 1
            }
        case .blend(let mode):
            var i = 0
            while i < count {
                (out.pixels + i).pointee = blendPixel((first.pixels + i).pointee, (second.pixels + i).pointee, mode)
                i += 1
            }
        case .composite(let c):
            var i = 0
            while i < count {
                (out.pixels + i).pointee = compositePixel((first.pixels + i).pointee, (second.pixels + i).pointee, c)
                i += 1
            }
        case .merge(_):
            for p in parts {
                var i = 0
                while i < count {
                    (out.pixels + i).pointee = compositePixel((p.pixels + i).pointee, (out.pixels + i).pointee, .over)
                    i += 1
                }
            }
        case .transfer(let r, let g, let b, let a):
            out.takeTransfer(of: first, r, g, b, a)
        case .morphology(let x, let y, let dilate):
            out.takeMorphology(of: first, x, y, dilate)
        case .tile:
            out.takeTiles(of: first, tile: source.region, area: area)
        case .turbulence(let fx, let fy, let octaves, let seed, let fractal):
            out.fillTurbulence(fx, fy, octaves, seed, fractal, scale: scale, originX: originX, originY: originY)
        case .displacement(let k, let xc, let yc):
            out.takeDisplacement(of: first, map: second, k, xc, yc)
        case .convolve(let columns, let rows, let kernel, let divisor, let bias, let tx, let ty, let keepAlpha):
            out.takeConvolution(of: first, columns, rows, kernel, divisor, bias, tx, ty, keepAlpha)
        case .lighting(let height, let k, let color, let light, let exponent):
            out.fillLighting(heights: first, height, k, color, light, exponent, originX: originX, originY: originY)
        }
    }

    func takeTransfer(of o: Layer, r: ChannelTransfer, g: ChannelTransfer, b: ChannelTransfer, a: ChannelTransfer) {
        func table(t: ChannelTransfer) -> [float32] {
            var out: [float32] = []
            var i = 0
            while i < 256 {
                out.append(transferred(t, float32(i) / 255))
                i += 1
            }
            return out
        }
        let tr = table(r)
        let tg = table(g)
        let tb = table(b)
        let ta = table(a)
        let count = int(Rect.Width) * int(Rect.Height)
        var i = 0
        while i < count {
            let c = unpremultiplied((o.pixels + i).pointee)
            func look(t: [float32], v: float32) -> float32 { return t[int(v * 255 + 0.5)] }
            (pixels + i).pointee = premultiplied(look(tr, c.r), look(tg, c.g), look(tb, c.b), look(ta, c.a))
            i += 1
        }
    }

    func takeMorphology(of o: Layer, rx: float32, ry: float32, dilate: bool) {
        // A radius of nothing turns the primitive off.
        if rx <= 0 && ry <= 0 {
            takePixels(of: o)
            return
        }
        func pass(from: Layer, to: Layer, dx: int32, dy: int32, r: int32) {
            var y = Rect.Y
            while y < Rect.Bottom {
                var x = Rect.X
                while x < Rect.Right {
                    var out: [uint32] = [0, 0, 0, 0]
                    var shift = 0
                    while shift < 4 { out[shift] = dilate ? 0 : 255; shift += 1 }
                    var k = -r
                    while k <= r {
                        let v = from.at(x + k * dx, y + k * dy)
                        var c = 0
                        while c < 4 {
                            let part = (v >> uint32(c * 8)) & 0xFF
                            if dilate ? part > out[c] : part < out[c] { out[c] = part }
                            c += 1
                        }
                        k += 1
                    }
                    to.put(x, y, out[0] | out[1] << 8 | out[2] << 16 | out[3] << 24)
                    x += 1
                }
                y += 1
            }
        }
        let middle = Layer(Rect)
        pass(from: o, to: middle, dx: 1, dy: 0, r: int32(rx))
        pass(from: middle, to: self, dx: 0, dy: 1, r: int32(ry))
        middle.Free()
    }

    func takeTiles(of o: Layer, tile: IRect, area: IRect) {
        if tile.IsEmpty { return }
        var y = area.Y
        while y < area.Bottom {
            var x = area.X
            while x < area.Right {
                var dx = (x - tile.X) % tile.Width
                var dy = (y - tile.Y) % tile.Height
                if dx < 0 { dx += tile.Width }
                if dy < 0 { dy += tile.Height }
                put(x, y, o.at(tile.X + dx, tile.Y + dy))
                x += 1
            }
            y += 1
        }
    }

    func takeDisplacement(of o: Layer, map: Layer, k: float32, xc: int32, yc: int32) {
        var y = Rect.Y
        while y < Rect.Bottom {
            var x = Rect.X
            while x < Rect.Right {
                let m = unpremultiplied(map.at(x, y))
                func channel(c: int32) -> float32 {
                    switch c {
                    case 0: return m.r
                    case 1: return m.g
                    case 2: return m.b
                    default: return m.a
                    }
                }
                let sx = float32(x) + k * (channel(xc) - 0.5)
                let sy = float32(y) + k * (channel(yc) - 0.5)
                put(x, y, o.at(int32(math.Floor(sx + 0.5)), int32(math.Floor(sy + 0.5))))
                x += 1
            }
            y += 1
        }
    }

    func takeConvolution(of o: Layer, columns: int32, rows: int32, kernel: [float32], divisor: float32, bias: float32, tx: int32, ty: int32, keepAlpha: bool) {
        if int(columns * rows) != kernel.count || divisor == 0 { return }
        var y = Rect.Y
        while y < Rect.Bottom {
            var x = Rect.X
            while x < Rect.Right {
                var sum: [float32] = [0, 0, 0, 0]
                var row: int32 = 0
                while row < rows {
                    var column: int32 = 0
                    while column < columns {
                        let v = o.at(x + column - tx, y + row - ty)
                        // The kernel is written first to last, last pixel first.
                        let w = kernel[int((rows - 1 - row) * columns + (columns - 1 - column))]
                        if keepAlpha {
                            let c = unpremultiplied(v)
                            sum[0] += c.r * w
                            sum[1] += c.g * w
                            sum[2] += c.b * w
                        } else {
                            sum[0] += float32(v & 0xFF) / 255 * w
                            sum[1] += float32((v >> 8) & 0xFF) / 255 * w
                            sum[2] += float32((v >> 16) & 0xFF) / 255 * w
                            sum[3] += float32(v >> 24) / 255 * w
                        }
                        column += 1
                    }
                    row += 1
                }
                if keepAlpha {
                    let a = float32(o.at(x, y) >> 24) / 255
                    put(x, y, premultiplied(sum[0] / divisor + bias, sum[1] / divisor + bias, sum[2] / divisor + bias, a))
                } else {
                    let a = math.Clamp(sum[3] / divisor + bias, 0, 1)
                    func bits(c: float32) -> uint32 { return uint32(math.Clamp(c / divisor + bias * a, 0, a) * 255 + 0.5) }
                    put(x, y, bits(sum[0]) | bits(sum[1]) << 8 | bits(sum[2]) << 16 | uint32(a * 255 + 0.5) << 24)
                }
                x += 1
            }
            y += 1
        }
    }

    func fillTurbulence(fx: float32, fy: float32, octaves: int32, seed: int32, fractal: bool, scale: float32, originX: float32, originY: float32) {
        let noise = PerlinNoise(seed: seed)
        var py = Rect.Y
        while py < Rect.Bottom {
            var px = Rect.X
            while px < Rect.Right {
                let x = (float32(px) - originX) / scale
                let y = (float32(py) - originY) / scale
                func noiseOf(channel: int) -> float32 {
                    let v = noise.Turbulence(channel: channel, x: x, y: y, fx: fx, fy: fy, octaves: octaves, fractal: fractal)
                    return math.Clamp(fractal ? (v + 1) / 2 : v, 0, 1)
                }
                put(px, py, premultiplied(noiseOf(0), noiseOf(1), noiseOf(2), noiseOf(3)))
                px += 1
            }
            py += 1
        }
    }

    func fillLighting(heights: Layer, height: float32, k: float32, color: Color, light: LightSource, exponent: float32, originX: float32, originY: float32) {
        let lr = float32(color.R) / 255
        let lg = float32(color.G) / 255
        let lb = float32(color.B) / 255
        func h(x: int32, y: int32) -> float32 {
            let cx = math.Clamp(x, Rect.X, Rect.Right - 1)
            let cy = math.Clamp(y, Rect.Y, Rect.Bottom - 1)
            return float32(heights.at(cx, cy) >> 24) / 255
        }
        var y = Rect.Y
        while y < Rect.Bottom {
            var x = Rect.X
            while x < Rect.Right {
                // The surface's normal, by a Sobel of its alpha.
                let nx = -height * (h(x + 1, y - 1) + 2 * h(x + 1, y) + h(x + 1, y + 1) - h(x - 1, y - 1) - 2 * h(x - 1, y) - h(x - 1, y + 1)) / 4
                let ny = -height * (h(x - 1, y + 1) + 2 * h(x, y + 1) + h(x + 1, y + 1) - h(x - 1, y - 1) - 2 * h(x, y - 1) - h(x + 1, y - 1)) / 4
                let nl = math.Sqrt(nx * nx + ny * ny + 1)
                let z = height * h(x, y)
                // Which way the light is.
                var ldx: float32 = 0
                var ldy: float32 = 0
                var ldz: float32 = 1
                var strength: float32 = 1
                switch light {
                case .distant(let azimuth, let elevation):
                    ldx = math.Cos(azimuth) * math.Cos(elevation)
                    ldy = math.Sin(azimuth) * math.Cos(elevation)
                    ldz = math.Sin(elevation)
                case .point(let lx, let ly, let lz):
                    ldx = originX + lx - float32(x)
                    ldy = originY + ly - float32(y)
                    ldz = lz - z
                    let len = math.Sqrt(ldx * ldx + ldy * ldy + ldz * ldz)
                    if len > 0 {
                        ldx /= len
                        ldy /= len
                        ldz /= len
                    }
                case .spot(let lx, let ly, let lz, let tx, let ty, let tz, let focus, let cone):
                    ldx = originX + lx - float32(x)
                    ldy = originY + ly - float32(y)
                    ldz = lz - z
                    let len = math.Sqrt(ldx * ldx + ldy * ldy + ldz * ldz)
                    if len > 0 {
                        ldx /= len
                        ldy /= len
                        ldz /= len
                    }
                    var sx = tx - lx
                    var sy = ty - ly
                    var sz = tz - lz
                    let s = math.Sqrt(sx * sx + sy * sy + sz * sz)
                    if s > 0 {
                        sx /= s
                        sy /= s
                        sz /= s
                    }
                    let along = -(ldx * sx + ldy * sy + ldz * sz)
                    strength = along <= 0 ? 0 : math.Pow(along, focus)
                    if cone >= 0 && along < math.Cos(cone) { strength = 0 }
                }
                let lit = math.Max(0, (nx * ldx + ny * ldy + ldz) / nl)
                if exponent < 0 {
                    let d = k * lit * strength
                    put(x, y, premultiplied(lr * d, lg * d, lb * d, 1))
                } else {
                    // Halfway between the light and the viewer, straight out.
                    let hx = ldx
                    let hy = ldy
                    let hz = ldz + 1
                    let hl = math.Sqrt(hx * hx + hy * hy + hz * hz)
                    let along = hl > 0 ? math.Max(0, (nx * hx + ny * hy + hz) / (nl * hl)) : 0
                    let e = k * math.Pow(along, exponent) * strength
                    let r = math.Min(lr * e, 1)
                    let g = math.Min(lg * e, 1)
                    let b = math.Min(lb * e, 1)
                    let a = math.Max(r, math.Max(g, b))
                    func bits(c: float32) -> uint32 { return uint32(c * 255 + 0.5) }
                    put(x, y, bits(r) | bits(g) << 8 | bits(b) << 16 | bits(a) << 24)
                }
                x += 1
            }
            y += 1
        }
    }
}

func transferred(t: ChannelTransfer, v: float32) -> float32 {
    switch t {
    case .identity: return v
    case .table(let values):
        if values.isEmpty { return v }
        if values.count == 1 { return values[0] }
        let n = values.count - 1
        var k = int(v * float32(n))
        if k >= n { return values[n] }
        if k < 0 { k = 0 }
        return math.Clamp(values[k] + (v * float32(n) - float32(k)) * (values[k + 1] - values[k]), 0, 1)
    case .discrete(let values):
        if values.isEmpty { return v }
        var k = int(v * float32(values.count))
        if k >= values.count { k = values.count - 1 }
        return values[k]
    case .linear(let slope, let intercept): return math.Clamp(slope * v + intercept, 0, 1)
    case .gamma(let amplitude, let exponent, let offset): return math.Clamp(amplitude * math.Pow(v, exponent) + offset, 0, 1)
    }
}

/// feComposite's source over or in or the rest of a backdrop: premultiplied.
func compositePixel(s: uint32, d: uint32, op: CompositeOp) -> uint32 {
    let sa = s >> 24
    let da = d >> 24
    switch op {
    case .over:
        if sa == 255 { return s }
        if sa == 0 { return d }
        return s &+ scalePacked(d, 255 - sa)
    case .in_: return scalePacked(s, da)
    case .out: return scalePacked(s, 255 - da)
    case .atop: return scalePacked(s, da) &+ scalePacked(d, 255 - sa)
    case .xor: return scalePacked(s, 255 - da) &+ scalePacked(d, 255 - sa)
    case .lighter: return blendPixel(s, d, .plusLighter)
    case .arithmetic(let k1, let k2, let k3, let k4):
        var out: uint32 = 0
        var alpha = (k1 * float32(sa) / 255 * float32(da) / 255) + k2 * float32(sa) / 255 + k3 * float32(da) / 255 + k4
        alpha = math.Clamp(alpha, 0, 1)
        var shift: uint32 = 0
        while shift < 24 {
            let a = float32((s >> shift) & 0xFF) / 255
            let b = float32((d >> shift) & 0xFF) / 255
            // A color stays within its alpha.
            out |= uint32(math.Clamp(k1 * a * b + k2 * a + k3 * b + k4, 0, alpha) * 255 + 0.5) << shift
            shift += 8
        }
        return out | uint32(alpha * 255 + 0.5) << 24
    }
}

/// The noise feTurbulence names, by its reference algorithm.
struct PerlinNoise {
    var lattice: [int32] = []
    var gradient: [float32] = []

    init(seed: int32) {
        let size = 256
        let m: int32 = 2147483647
        var s = seed
        if s <= 0 { s = -(s % (m - 1)) + 1 }
        if s > m - 1 { s = m - 1 }
        func next() -> int32 {
            var r = 16807 &* (s % 127773) &- 2836 &* (s / 127773)
            if r <= 0 { r = r &+ m }
            s = r
            return r
        }
        lattice = [int32](repeating: 0, count: 2 * size + 2)
        gradient = [float32](repeating: 0, count: 4 * (2 * size + 2) * 2)
        var k = 0
        while k < 4 {
            var i = 0
            while i < size {
                lattice[i] = int32(i)
                var a = float32((next() % int32(2 * size)) - int32(size)) / float32(size)
                var b = float32((next() % int32(2 * size)) - int32(size)) / float32(size)
                let len = math.Sqrt(a * a + b * b)
                if len > 0 {
                    a /= len
                    b /= len
                }
                gradient[(k * (2 * size + 2) + i) * 2] = a
                gradient[(k * (2 * size + 2) + i) * 2 + 1] = b
                i += 1
            }
            k += 1
        }
        var i = size - 1
        while i > 0 {
            let j = int(next() % int32(size))
            let t = lattice[i]
            lattice[i] = lattice[j]
            lattice[j] = t
            i -= 1
        }
        i = 0
        while i < size + 2 {
            lattice[size + i] = lattice[i]
            k = 0
            while k < 4 {
                gradient[(k * (2 * size + 2) + size + i) * 2] = gradient[(k * (2 * size + 2) + i) * 2]
                gradient[(k * (2 * size + 2) + size + i) * 2 + 1] = gradient[(k * (2 * size + 2) + i) * 2 + 1]
                k += 1
            }
            i += 1
        }
    }

    func noise2(channel: int, x: float32, y: float32) -> float32 {
        let size = 256
        let t = x + 4096
        let u = y + 4096
        let bx0 = int(t) & 255
        let bx1 = (bx0 + 1) & 255
        let rx0 = t - math.Floor(t)
        let rx1 = rx0 - 1
        let by0 = int(u) & 255
        let by1 = (by0 + 1) & 255
        let ry0 = u - math.Floor(u)
        let ry1 = ry0 - 1
        let i = int(lattice[bx0])
        let j = int(lattice[bx1])
        let b00 = int(lattice[i + by0])
        let b10 = int(lattice[j + by0])
        let b01 = int(lattice[i + by1])
        let b11 = int(lattice[j + by1])
        func curve(t: float32) -> float32 { return t * t * (3 - 2 * t) }
        func mix(t: float32, a: float32, b: float32) -> float32 { return a + t * (b - a) }
        func dot(b: int, rx: float32, ry: float32) -> float32 {
            let at = (channel * (2 * size + 2) + b) * 2
            return rx * gradient[at] + ry * gradient[at + 1]
        }
        let sx = curve(rx0)
        let sy = curve(ry0)
        let a = mix(sx, dot(b00, rx0, ry0), dot(b10, rx1, ry0))
        let b = mix(sx, dot(b01, rx0, ry1), dot(b11, rx1, ry1))
        return mix(sy, a, b)
    }

    func Turbulence(channel: int, x: float32, y: float32, fx: float32, fy: float32, octaves: int32, fractal: bool) -> float32 {
        var sum: float32 = 0
        var vx = x * fx
        var vy = y * fy
        var ratio: float32 = 1
        var o: int32 = 0
        while o < octaves {
            let n = noise2(channel, vx, vy)
            sum += (fractal ? n : math.Abs(n)) / ratio
            vx *= 2
            vy *= 2
            ratio *= 2
            o += 1
        }
        return sum
    }
}
