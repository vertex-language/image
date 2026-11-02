// Package format decodes an image whose format isn't known ahead of time:
// it sniffs the bytes and hands them to the right decoder. PNG decodes in
// pure Vertex (image/png); JPEG, GIF, WebP, HEIC, TIFF and BMP go through
// the platform's decoders until pure ones exist.
package format

import (
    "image"
    "image/png"
)

/// Kind is an image file format, as recognised from its first bytes.
public enum Kind {
    case png
    case jpeg
    case gif
    case webp
    case bmp
    case unknown
}

/// Sniff names the format of an image's bytes.
public func Sniff(b: [uint8]) -> Kind {
    if b.count >= 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47 { return .png }
    if b.count >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF { return .jpeg }
    if b.count >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x38 { return .gif }
    if b.count >= 12 && b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46
        && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50 { return .webp }
    if b.count >= 2 && b[0] == 0x42 && b[1] == 0x4D { return .bmp }
    return .unknown
}

/// An image with frames of its own: animated GIF, WebP or PNG.
public final class AnimatedImage {
    public let Frames: [image.RGBA]
    /// How long each shows, in seconds.
    public let Delays: [float64]
    public let Total: float64

    init(frames: [image.RGBA], delays: [float64]) {
        Frames = frames
        Delays = delays
        var sum: float64 = 0
        for d in delays { sum += d }
        Total = sum
    }

    /// Which frame shows at a time, going round for good.
    public func FrameIndex(at time: float64) -> int {
        if Total <= 0 { return 0 }
        var t = time - Total * float64(int64(time / Total))
        var i = 0
        while i < Delays.count {
            if t < Delays[i] { return i }
            t -= Delays[i]
            i += 1
        }
        return Delays.count - 1
    }
}

/// An image's frames, where it has more than one; nil where it hasn't, or
/// the platform can't read them.
public func DecodeAnimated(bytes: [uint8]) -> AnimatedImage? {
    if bytes.isEmpty { return nil }
    let count = bytes.withUnsafeBufferPointer { bp in platformFrameCount(UnsafePointer<uint8>(bp.baseAddress!), int32(bytes.count)) }
    if count < 2 { return nil }
    var frames: [image.RGBA] = []
    var delays: [float64] = []
    var i: int32 = 0
    while i < count {
        var w: int32 = 0
        var h: int32 = 0
        var delay: float64 = 0
        let need = bytes.withUnsafeBufferPointer { bp in platformDecodeFrame(UnsafePointer<uint8>(bp.baseAddress!), int32(bytes.count), i, &w, &h, nil, 0, &delay) }
        if need <= 0 { return nil }
        var pixels = [uint8](repeating: 0, count: int(need))
        _ = bytes.withUnsafeBufferPointer { bp in
            pixels.withUnsafeMutableBufferPointer { out in
                platformDecodeFrame(UnsafePointer<uint8>(bp.baseAddress!), int32(bytes.count), i, &w, &h, out.baseAddress, need, &delay)
            }
        }
        frames.append(image.RGBA(width: int(w), height: int(h), pixels: pixels))
        // As browsers do: what says it shows for almost no time shows for a tenth.
        delays.append(delay < 0.011 ? 0.1 : delay)
        i += 1
    }
    return AnimatedImage(frames: frames, delays: delays)
}

/// Decode decodes an image's bytes into premultiplied RGBA. Nil where the
/// bytes are not an image anything here reads.
public func Decode(bytes: [uint8]) -> image.RGBA? {
    if bytes.isEmpty { return nil }
    if Sniff(bytes) == .png {
        do {
            return try png.Decode(bytes)
        } catch {
            // Fall through: the platform may read what we don't.
        }
    }
    return decodePlatform(bytes)
}

func decodePlatform(bytes: [uint8]) -> image.RGBA? {
    var width: int32 = 0
    var height: int32 = 0
    let need = bytes.withUnsafeBytes { bp in
        platformDecode(UnsafePointer<uint8>(bp.baseAddress!), int32(bytes.count), &width, &height, nil, 0)
    }
    if need <= 0 || width <= 0 || height <= 0 { return nil }
    var pixels = [uint8](repeating: 0, count: int(need))
    let got = bytes.withUnsafeBytes { bp in
        pixels.withUnsafeMutableBufferPointer { pp in
            platformDecode(UnsafePointer<uint8>(bp.baseAddress!), int32(bytes.count), &width, &height, pp.baseAddress!, int32(pp.count))
        }
    }
    if got != need { return nil }
    return image.RGBA(width: int(width), height: int(height), pixels: pixels)
}

/// DecodeDataURL decodes a `data:` URL's image, base64 or plain.
public func DecodeDataURL(url: string) -> image.RGBA? {
    guard let payload = DataURLBytes(url) else { return nil }
    return Decode(payload)
}

/// DataURLBytes is what a `data:` URL holds: its payload base64-decoded,
/// or percent-decoded where it is plain (`data:image/svg+xml,%3Csvg…`).
public func DataURLBytes(url: string) -> [uint8]? {
    let b = [uint8](url.utf8)
    if b.count < 6 { return nil }
    var comma = 0
    while comma < b.count && b[comma] != 44 { comma += 1 }
    if comma >= b.count { return nil }
    // ";base64" right before the comma.
    let marker: [uint8] = [59, 98, 97, 115, 101, 54, 52]
    var base64 = comma >= marker.count
    var i = 0
    while base64 && i < marker.count {
        if b[comma - marker.count + i] != marker[i] { base64 = false }
        i += 1
    }
    var payload: [uint8] = []
    i = comma + 1
    while i < b.count { payload.append(b[i]); i += 1 }
    if base64 { return base64Decode(payload) }
    // %XX escapes.
    var out: [uint8] = []
    i = 0
    while i < payload.count {
        if payload[i] == 37 && i + 2 < payload.count, let hi = hexDigit(payload[i + 1]), let lo = hexDigit(payload[i + 2]) {
            out.append(hi << 4 | lo)
            i += 3
        } else {
            out.append(payload[i])
            i += 1
        }
    }
    return out
}

func hexDigit(c: uint8) -> uint8? {
    if c >= 48 && c <= 57 { return c - 48 }
    if c >= 65 && c <= 70 { return c - 55 }
    if c >= 97 && c <= 102 { return c - 87 }
    return nil
}

// base64Decode takes standard or URL-safe base64 and skips anything else
// (whitespace, padding), as data: URLs in the wild need.
func base64Decode(input: [uint8]) -> [uint8] {
    var out: [uint8] = []
    var bits: uint32 = 0
    var count = 0
    for c in input {
        var v: int32 = -1
        if c >= 65 && c <= 90 { v = int32(c) - 65 }
        else if c >= 97 && c <= 122 { v = int32(c) - 97 + 26 }
        else if c >= 48 && c <= 57 { v = int32(c) - 48 + 52 }
        else if c == 43 || c == 45 { v = 62 }
        else if c == 47 || c == 95 { v = 63 }
        else { continue }
        bits = (bits << 6) | uint32(v)
        count += 6
        if count >= 8 {
            count -= 8
            out.append(uint8((bits >> uint32(count)) & 0xFF))
        }
    }
    return out
}
