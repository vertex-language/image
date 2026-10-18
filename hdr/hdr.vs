// Package hdr reads Radiance RGBE images (.hdr, .pic): the format sky
// and studio light probes are shipped in. Pixels come out as linear
// float32 RGB, three floats a texel, top row first. Pure Vertex, no I/O.
//
// Read: the "#?RADIANCE" / "#?RGBE" header, FORMAT=32-bit_rle_rgbe,
// "-Y h +X w" (the usual orientation), and both scanline encodings:
// flat RGBE quads and the adaptive run-length form (each of the four
// components run-length coded on its own).
package hdr

/// HdrError is why bytes could not be decoded.
public enum HdrError: Error {
    case notHDR
    case truncated
    case unsupported(string)
}

/// Image is a decoded high dynamic range image: Width × Height texels of
/// linear RGB, three float32s each, top row first.
public struct Image {
    public let Width: int
    public let Height: int
    public var Pixels: [float32]

    public init(width: int, height: int, pixels: [float32]) {
        Width = width
        Height = height
        Pixels = pixels
    }

    /// At is the texel at (x, y), clamped to the image.
    public func At(_ x: int, _ y: int) -> (float32, float32, float32) {
        let cx = max(0, min(Width - 1, x)), cy = max(0, min(Height - 1, y))
        let i = (cy * Width + cx) * 3
        return (Pixels[i], Pixels[i + 1], Pixels[i + 2])
    }
}

/// Decode reads an RGBE image.
public func Decode(_ b: [uint8]) throws -> Image {
    if b.count < 11 { throw HdrError.notHDR }
    // "#?" then a program name ("RADIANCE", "RGBE"), then header lines up
    // to a blank one, then the resolution line.
    if b[0] != 35 || b[1] != 63 { throw HdrError.notHDR }
    var at = 0
    var format = ""
    while true {
        let line = readLine(b, &at)
        guard let l = line else { throw HdrError.truncated }
        if l.isEmpty { break }
        if l.hasPrefix("FORMAT=") { format = string(l.dropFirst(7)) }
    }
    if !format.isEmpty && format != "32-bit_rle_rgbe" { throw HdrError.unsupported("format \(format)") }
    guard let res = readLine(b, &at) else { throw HdrError.truncated }
    let parts = res.split(separator: " ")
    if parts.count != 4 || parts[0] != "-Y" || parts[2] != "+X" { throw HdrError.unsupported("orientation \(res)") }
    guard let h = Int(string(parts[1])), let w = Int(string(parts[3])), w > 0, h > 0 else { throw HdrError.unsupported("size \(res)") }

    var out = [float32](repeating: 0, count: w * h * 3)
    let scale = exponents()
    var row = [uint8](repeating: 0, count: w * 4)
    for y in 0..<h {
        try scanline(b, &at, &row, w)
        var o = y * w * 3
        var i = 0
        for _ in 0..<w {
            let e = int(row[i + 3])
            if e != 0 {
                let f = scale[e]
                out[o] = (float32(row[i]) + 0.5) * f
                out[o + 1] = (float32(row[i + 1]) + 0.5) * f
                out[o + 2] = (float32(row[i + 2]) + 0.5) * f
            }
            o += 3
            i += 4
        }
    }
    return Image(width: w, height: h, pixels: out)
}

// exponents is 2^(e - 136) for every exponent byte: a mantissa byte times
// it is the component's value (2^(e-128) / 256).
func exponents() -> [float32] {
    var t = [float32](repeating: 0, count: 256)
    var v: float64 = 1
    for _ in 0..<136 { v /= 2 }
    for e in 0..<256 {
        t[e] = float32(v)
        v *= 2
    }
    return t
}

// scanline reads one row of w texels as RGBE quads into row.
func scanline(_ b: [uint8], _ at: inout int, _ row: inout [uint8], _ w: int) throws {
    if at + 4 > b.count { throw HdrError.truncated }
    // The run-length form starts 2, 2, then the width in two bytes; widths
    // outside 8…32767 are always flat.
    let rle = w >= 8 && w < 32768 && b[at] == 2 && b[at + 1] == 2 && (b[at + 2] & 0x80) == 0
    if !rle {
        // Flat quads (old-style runs of 1,1,1,n aren't written by anything
        // current; read them as repeats all the same).
        var x = 0
        var shift = 0
        while x < w {
            if at + 4 > b.count { throw HdrError.truncated }
            if b[at] == 1 && b[at + 1] == 1 && b[at + 2] == 1 && x > 0 {
                let n = int(b[at + 3]) << shift
                for _ in 0..<n where x < w {
                    for k in 0..<4 { row[x * 4 + k] = row[(x - 1) * 4 + k] }
                    x += 1
                }
                shift += 8
            } else {
                for k in 0..<4 { row[x * 4 + k] = b[at + k] }
                x += 1
                shift = 0
            }
            at += 4
        }
        return
    }
    let width = (int(b[at + 2]) << 8) | int(b[at + 3])
    if width != w { throw HdrError.unsupported("scanline width \(width) of \(w)") }
    at += 4
    // Each component in turn, across the row: runs (count > 128 repeats
    // the next byte count - 128 times) and literals.
    for c in 0..<4 {
        var x = 0
        while x < w {
            if at >= b.count { throw HdrError.truncated }
            var n = int(b[at])
            at += 1
            if n > 128 {
                n -= 128
                if at >= b.count || x + n > w { throw HdrError.truncated }
                let v = b[at]
                at += 1
                for _ in 0..<n {
                    row[x * 4 + c] = v
                    x += 1
                }
            } else {
                if n == 0 || at + n > b.count || x + n > w { throw HdrError.truncated }
                for _ in 0..<n {
                    row[x * 4 + c] = b[at]
                    at += 1
                    x += 1
                }
            }
        }
    }
}

// readLine reads up to a newline (not included); nil at the end.
func readLine(_ b: [uint8], _ at: inout int) -> string? {
    if at >= b.count { return nil }
    let start = at
    while at < b.count && b[at] != 10 { at += 1 }
    let line = string(decoding: b[start..<at], as: UTF8.self)
    if at < b.count { at += 1 }
    return line
}
