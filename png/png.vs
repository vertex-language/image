// Package png reads and writes PNG images (RFC 2083, PNG 1.2): every
// color type and bit depth, palettes with transparency, and Adam7
// interlacing on the way in; 8-bit RGB or RGBA with per-row filters and
// zlib compression on the way out. Pure Vertex, no I/O.
package png

import "image"
import "crypto/crc32"

/// PngError is why bytes could not be decoded.
public enum PngError: Error {
    case notPNG
    case truncated
    case badChunk(string)
    case badData(string)
    case unsupported(string)
}

func signature() -> [uint8] { return [137, 80, 78, 71, 13, 10, 26, 10] }

// --- encode ---

/// Encode writes an image as a PNG. Opaque images are stored as RGB,
/// others as RGBA with the color un-premultiplied.
public func Encode(_ img: image.RGBA) -> [uint8] {
    let opaque = img.IsOpaque
    let bpp = opaque ? 3 : 4
    let w = img.Width
    let h = img.Height
    let rowBytes = w * bpp

    var header: [uint8] = []
    appendU32(&header, uint32(w))
    appendU32(&header, uint32(h))
    header.append(8)                    // bit depth
    header.append(opaque ? 2 : 6)       // color type: RGB or RGBA
    header.append(0)                    // deflate
    header.append(0)                    // adaptive filtering
    header.append(0)                    // not interlaced

    // Straight (un-premultiplied) samples, one row at a time, each with
    // the filter that leaves the smallest sum of magnitudes.
    var raw = [uint8](repeating: 0, count: (rowBytes + 1) * h)
    var prior = [uint8](repeating: 0, count: rowBytes)
    var cur = [uint8](repeating: 0, count: rowBytes)
    var trial = [uint8](repeating: 0, count: rowBytes)
    var best = [uint8](repeating: 0, count: rowBytes)
    var y = 0
    while y < h {
        var x = 0
        var s = y * w * 4
        var d = 0
        while x < w {
            let a = uint32(img.Pixels[s + 3])
            if a == 255 || a == 0 {
                cur[d] = img.Pixels[s]; cur[d + 1] = img.Pixels[s + 1]; cur[d + 2] = img.Pixels[s + 2]
            } else {
                cur[d] = uint8(truncatingIfNeeded: (uint32(img.Pixels[s]) * 255 + a / 2) / a)
                cur[d + 1] = uint8(truncatingIfNeeded: (uint32(img.Pixels[s + 1]) * 255 + a / 2) / a)
                cur[d + 2] = uint8(truncatingIfNeeded: (uint32(img.Pixels[s + 2]) * 255 + a / 2) / a)
            }
            if !opaque { cur[d + 3] = uint8(truncatingIfNeeded: a) }
            x += 1
            s += 4
            d += bpp
        }
        var bestFilter = 0
        var bestScore = -1
        var f = 0
        while f < 5 {
            let score = filterRow(f, cur, prior, bpp, &trial)
            if bestScore < 0 || score < bestScore {
                bestScore = score
                bestFilter = f
                var i = 0
                while i < rowBytes { best[i] = trial[i]; i += 1 }
            }
            f += 1
        }
        let o = y * (rowBytes + 1)
        raw[o] = uint8(bestFilter)
        var i = 0
        while i < rowBytes { raw[o + 1 + i] = best[i]; i += 1 }
        let t = prior
        prior = cur
        cur = t
        y += 1
    }

    var out = signature()
    writeChunk(&out, "IHDR", header)
    writeChunk(&out, "IDAT", deflateZlib(raw))
    writeChunk(&out, "IEND", [])
    return out
}

// filterRow applies filter f to cur (the row above is prior) into out and
// returns the sum of the output bytes read as signed magnitudes.
func filterRow(_ f: int, _ cur: [uint8], _ prior: [uint8], _ bpp: int, _ out: inout [uint8]) -> int {
    let n = cur.count
    var score = 0
    var i = 0
    while i < n {
        let x = int(cur[i])
        let a = i >= bpp ? int(cur[i - bpp]) : 0
        let b = int(prior[i])
        let c = i >= bpp ? int(prior[i - bpp]) : 0
        var v = x
        switch f {
        case 1: v = x - a
        case 2: v = x - b
        case 3: v = x - (a + b) / 2
        case 4: v = x - paeth(a, b, c)
        default: v = x
        }
        let byte = v & 0xFF
        out[i] = uint8(byte)
        score += byte < 128 ? byte : 256 - byte
        i += 1
    }
    return score
}

func paeth(_ a: int, _ b: int, _ c: int) -> int {
    let p = a + b - c
    var pa = p - a
    var pb = p - b
    var pc = p - c
    if pa < 0 { pa = -pa }
    if pb < 0 { pb = -pb }
    if pc < 0 { pc = -pc }
    if pa <= pb && pa <= pc { return a }
    if pb <= pc { return b }
    return c
}

func appendU32(_ out: inout [uint8], _ v: uint32) {
    out.append(uint8(truncatingIfNeeded: v >> 24))
    out.append(uint8(truncatingIfNeeded: v >> 16))
    out.append(uint8(truncatingIfNeeded: v >> 8))
    out.append(uint8(truncatingIfNeeded: v))
}

func writeChunk(_ out: inout [uint8], _ type: string, _ data: [uint8]) {
    appendU32(&out, uint32(data.count))
    var typeBytes: [uint8] = []
    for b in type.utf8 { typeBytes.append(b) }
    for b in typeBytes { out.append(b) }
    for b in data { out.append(b) }
    let crc = crc32.Update(crc32.Update(0, typeBytes), data)
    appendU32(&out, crc)
}

// --- decode ---

/// Config is what the header says about an image.
public struct Config {
    public var Width: int
    public var Height: int
    public var BitDepth: int
    public var ColorType: int
    public var Interlaced: bool
}

/// DecodeConfig reads only the header.
public func DecodeConfig(_ data: [uint8]) throws -> Config {
    let sig = signature()
    if data.count < 33 { throw PngError.truncated }
    var i = 0
    while i < 8 { if data[i] != sig[i] { throw PngError.notPNG }; i += 1 }
    if readU32(data, 12) != 0x49484452 { throw PngError.badChunk("first chunk is not IHDR") }
    let w = int(readU32(data, 16))
    let h = int(readU32(data, 20))
    return Config(Width: w, Height: h, BitDepth: int(data[24]), ColorType: int(data[25]), Interlaced: data[28] == 1)
}

/// Decode reads a PNG into premultiplied RGBA. 16-bit samples keep their
/// high byte; gamma and color profiles are not applied.
public func Decode(_ data: [uint8]) throws -> image.RGBA {
    let cfg = try DecodeConfig(data)
    let w = cfg.Width
    let h = cfg.Height
    let depth = cfg.BitDepth
    let ct = cfg.ColorType
    if w <= 0 || h <= 0 || w > 1 << 24 || h > 1 << 24 { throw PngError.badChunk("bad dimensions") }
    let channels = channelsOf(ct)
    if channels == 0 { throw PngError.badChunk("bad color type \(ct)") }
    if !depthAllowed(ct, depth) { throw PngError.badChunk("bit depth \(depth) with color type \(ct)") }

    var palette: [uint8] = []            // RGBA per entry
    var trns: [uint8] = []
    var idat: [uint8] = []
    var pos = 8
    var sawEnd = false
    while pos + 8 <= data.count {
        let len = int(readU32(data, pos))
        let type = readU32(data, pos + 4)
        let body = pos + 8
        if len < 0 || body + len + 4 > data.count { throw PngError.truncated }
        switch type {
        case 0x504C5445:   // PLTE
            var i = 0
            while i + 2 < len {
                palette.append(data[body + i]); palette.append(data[body + i + 1]); palette.append(data[body + i + 2])
                palette.append(255)
                i += 3
            }
        case 0x74524E53:   // tRNS
            var i = 0
            while i < len { trns.append(data[body + i]); i += 1 }
        case 0x49444154:   // IDAT
            var i = 0
            while i < len { idat.append(data[body + i]); i += 1 }
        case 0x49454E44:   // IEND
            sawEnd = true
        default:
            // Unknown critical chunks (uppercase first letter) can't be skipped.
            if (type >> 24) & 0x20 == 0 && type != 0x49484452 {
                throw PngError.unsupported("critical chunk")
            }
        }
        pos = body + len + 4
        if sawEnd { break }
    }
    if idat.count == 0 { throw PngError.badChunk("no image data") }
    if ct == 3 {
        if palette.count == 0 { throw PngError.badChunk("indexed image without a palette") }
        var i = 0
        while i < trns.count && i * 4 + 3 < palette.count { palette[i * 4 + 3] = trns[i]; i += 1 }
    }

    let bitsPerPixel = channels * depth
    let bpp = bitsPerPixel >= 8 ? bitsPerPixel / 8 : 1
    var expected = 0
    if cfg.Interlaced {
        var p = 0
        while p < 7 {
            let (pw, ph) = passSize(p, w, h)
            if pw > 0 && ph > 0 { expected += ((pw * bitsPerPixel + 7) / 8 + 1) * ph }
            p += 1
        }
    } else {
        expected = ((w * bitsPerPixel + 7) / 8 + 1) * h
    }
    let raw = try inflateZlib(idat, sizeHint: expected)
    if raw.count < expected { throw PngError.badData("image data too short") }

    var out = image.RGBA(width: w, height: h)
    var src = 0
    if cfg.Interlaced {
        var p = 0
        while p < 7 {
            let (pw, ph) = passSize(p, w, h)
            if pw > 0 && ph > 0 {
                let rowBytes = (pw * bitsPerPixel + 7) / 8
                let rows = try unfilter(raw, src, rowBytes, ph, bpp)
                src += (rowBytes + 1) * ph
                let (x0, y0, dx, dy) = passGeometry(p)
                var ry = 0
                while ry < ph {
                    var rx = 0
                    while rx < pw {
                        putPixel(&out, (x0 + rx * dx) + (y0 + ry * dy) * w, rows, ry * rowBytes, rx, ct, depth, palette, trns)
                        rx += 1
                    }
                    ry += 1
                }
            }
            p += 1
        }
    } else {
        let rowBytes = (w * bitsPerPixel + 7) / 8
        let rows = try unfilter(raw, 0, rowBytes, h, bpp)
        var y = 0
        while y < h {
            var x = 0
            while x < w {
                putPixel(&out, y * w + x, rows, y * rowBytes, x, ct, depth, palette, trns)
                x += 1
            }
            y += 1
        }
    }
    return out
}

func channelsOf(_ ct: int) -> int {
    switch ct {
    case 0: return 1
    case 2: return 3
    case 3: return 1
    case 4: return 2
    case 6: return 4
    default: return 0
    }
}

func depthAllowed(_ ct: int, _ d: int) -> bool {
    switch ct {
    case 0: return d == 1 || d == 2 || d == 4 || d == 8 || d == 16
    case 3: return d == 1 || d == 2 || d == 4 || d == 8
    default: return d == 8 || d == 16
    }
}

func passGeometry(_ p: int) -> (int, int, int, int) {
    switch p {
    case 0: return (0, 0, 8, 8)
    case 1: return (4, 0, 8, 8)
    case 2: return (0, 4, 4, 8)
    case 3: return (2, 0, 4, 4)
    case 4: return (0, 2, 2, 4)
    case 5: return (1, 0, 2, 2)
    default: return (0, 1, 1, 2)
    }
}

func passSize(_ p: int, _ w: int, _ h: int) -> (int, int) {
    let (x0, y0, dx, dy) = passGeometry(p)
    let pw = w > x0 ? (w - x0 + dx - 1) / dx : 0
    let ph = h > y0 ? (h - y0 + dy - 1) / dy : 0
    return (pw, ph)
}

// unfilter undoes the per-row filters of rows at raw[start...] and returns
// the rows packed without their filter bytes.
func unfilter(_ raw: [uint8], _ start: int, _ rowBytes: int, _ rows: int, _ bpp: int) throws -> [uint8] {
    var out = [uint8](repeating: 0, count: rowBytes * rows)
    var y = 0
    while y < rows {
        let f = raw[start + y * (rowBytes + 1)]
        let s = start + y * (rowBytes + 1) + 1
        let d = y * rowBytes
        var i = 0
        while i < rowBytes {
            let x = int(raw[s + i])
            let a = i >= bpp ? int(out[d + i - bpp]) : 0
            let b = y > 0 ? int(out[d - rowBytes + i]) : 0
            let c = (y > 0 && i >= bpp) ? int(out[d - rowBytes + i - bpp]) : 0
            var v = x
            switch f {
            case 0: v = x
            case 1: v = x + a
            case 2: v = x + b
            case 3: v = x + (a + b) / 2
            case 4: v = x + paeth(a, b, c)
            default: throw PngError.badData("bad filter type \(f)")
            }
            out[d + i] = uint8(v & 0xFF)
            i += 1
        }
        y += 1
    }
    return out
}

// sample reads the n-th sample of depth bits from a packed row.
func sample(_ rows: [uint8], _ rowStart: int, _ n: int, _ depth: int) -> int {
    switch depth {
    case 8: return int(rows[rowStart + n])
    case 16: return int(rows[rowStart + n * 2])   // high byte
    default:
        let bit = n * depth
        let byte = int(rows[rowStart + bit / 8])
        let shift = 8 - depth - (bit % 8)
        return (byte >> shift) & ((1 << depth) - 1)
    }
}

// sample16 is a 16-bit sample, for comparing against tRNS keys.
func sample16(_ rows: [uint8], _ rowStart: int, _ n: int) -> int {
    return (int(rows[rowStart + n * 2]) << 8) | int(rows[rowStart + n * 2 + 1])
}

func scaleTo8(_ v: int, _ depth: int) -> int {
    switch depth {
    case 1: return v * 255
    case 2: return v * 85
    case 4: return v * 17
    default: return v
    }
}

func putPixel(_ img: inout image.RGBA, _ index: int, _ rows: [uint8], _ rowStart: int, _ x: int,
              _ ct: int, _ depth: int, _ palette: [uint8], _ trns: [uint8]) {
    var r = 0
    var g = 0
    var b = 0
    var a = 255
    switch ct {
    case 0:
        let v = sample(rows, rowStart, x, depth)
        r = scaleTo8(v, depth); g = r; b = r
        if trns.count >= 2 {
            let key = (int(trns[0]) << 8) | int(trns[1])
            let raw = depth == 16 ? sample16(rows, rowStart, x) : v
            if raw == key { a = 0 }
        }
    case 2:
        r = sample(rows, rowStart, x * 3, depth)
        g = sample(rows, rowStart, x * 3 + 1, depth)
        b = sample(rows, rowStart, x * 3 + 2, depth)
        if trns.count >= 6 {
            if depth == 16 {
                if sample16(rows, rowStart, x * 3) == (int(trns[0]) << 8 | int(trns[1]))
                    && sample16(rows, rowStart, x * 3 + 1) == (int(trns[2]) << 8 | int(trns[3]))
                    && sample16(rows, rowStart, x * 3 + 2) == (int(trns[4]) << 8 | int(trns[5])) { a = 0 }
            } else if r == int(trns[1]) && g == int(trns[3]) && b == int(trns[5]) {
                a = 0
            }
        }
    case 3:
        let i = sample(rows, rowStart, x, depth) * 4
        if i + 3 < palette.count {
            r = int(palette[i]); g = int(palette[i + 1]); b = int(palette[i + 2]); a = int(palette[i + 3])
        } else {
            r = 0; g = 0; b = 0
        }
    case 4:
        r = sample(rows, rowStart, x * 2, depth); g = r; b = r
        a = sample(rows, rowStart, x * 2 + 1, depth)
    default:
        r = sample(rows, rowStart, x * 4, depth)
        g = sample(rows, rowStart, x * 4 + 1, depth)
        b = sample(rows, rowStart, x * 4 + 2, depth)
        a = sample(rows, rowStart, x * 4 + 3, depth)
    }
    let o = index * 4
    if a == 255 {
        img.Pixels[o] = uint8(r); img.Pixels[o + 1] = uint8(g); img.Pixels[o + 2] = uint8(b)
    } else {
        img.Pixels[o] = uint8((r * a + 127) / 255)
        img.Pixels[o + 1] = uint8((g * a + 127) / 255)
        img.Pixels[o + 2] = uint8((b * a + 127) / 255)
    }
    img.Pixels[o + 3] = uint8(a)
}

func readU32(_ d: [uint8], _ at: int) -> uint32 {
    return (uint32(d[at]) << 24) | (uint32(d[at + 1]) << 16) | (uint32(d[at + 2]) << 8) | uint32(d[at + 3])
}
