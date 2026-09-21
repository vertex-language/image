// check-png decodes the fixtures gen.py writes (every color type, bit
// depth and interlace) and compares them to the expected pixels, then
// round-trips images through Encode and Decode.
// Run from this directory: check-png testdata
package main

import "image"
import "image/png"
import "fs"

var failures = 0

func check(_ ok: bool, _ what: string) {
    if !ok {
        failures += 1
        print("FAIL: \(what)")
    }
}

func same(_ a: [uint8], _ b: [uint8]) -> int {
    if a.count != b.count { return 0 }
    var i = 0
    while i < a.count {
        if a[i] != b[i] { return i }
        i += 1
    }
    return -1
}

// fixtureNames lists what gen.py writes: ct<color type>-d<depth>-i<interlace>.
func fixtureNames() -> [string] {
    var out: [string] = []
    let types: [int] = [0, 2, 3, 4, 6]
    for ct in types {
        var depths: [int] = [8, 16]
        if ct == 0 { depths = [1, 2, 4, 8, 16] }
        if ct == 3 { depths = [1, 2, 4, 8] }
        for d in depths {
            out.append("ct\(ct)-d\(d)-i0")
            out.append("ct\(ct)-d\(d)-i1")
        }
    }
    return out
}

func roundTrip(_ img: image.RGBA, _ what: string) {
    let bytes = png.Encode(img)
    do {
        let back = try png.Decode(bytes)
        check(back.Width == img.Width && back.Height == img.Height, "\(what): size")
        // Un-premultiplying and premultiplying again loses a little at low alpha.
        var worst = 0
        var i = 0
        while i < img.Pixels.count {
            var d = int(back.Pixels[i]) - int(img.Pixels[i])
            if d < 0 { d = -d }
            if d > worst { worst = d }
            i += 1
        }
        check(worst <= 1, "\(what): pixels differ by \(worst)")
        print("ok  \(what): \(img.Width)x\(img.Height) -> \(bytes.count) bytes")
    } catch {
        check(false, "\(what): decode: \(error)")
    }
}

func main() -> int32 {
    let args = CommandLine.arguments
    let dir = args.count > 1 ? args[1] : "testdata"
    do {
        var decoded = 0
        for n in fixtureNames() {
            let data = try fs.ReadFile(fs.Path(dir + "/" + n + ".png"))
            let want = try fs.ReadFile(fs.Path(dir + "/" + n + ".rgba"))
            do {
                let img = try png.Decode(data)
                let at = same(img.Pixels, want)
                check(at < 0, "\(n): pixels differ at byte \(at)")
                decoded += 1
            } catch {
                check(false, "\(n): \(error)")
            }
        }
        print("ok  decoded \(decoded) fixtures")
    } catch {
        check(false, "reading fixtures from \(dir): \(error)")
    }

    // Opaque gradient: stored as RGB.
    var opaque = image.RGBA(width: 300, height: 200)
    var y = 0
    while y < 200 {
        var x = 0
        while x < 300 {
            let o = (y * 300 + x) * 4
            opaque.Pixels[o] = uint8(x % 256)
            opaque.Pixels[o + 1] = uint8(y % 256)
            opaque.Pixels[o + 2] = uint8((x + y) % 256)
            opaque.Pixels[o + 3] = 255
            x += 1
        }
        y += 1
    }
    roundTrip(opaque, "opaque gradient")

    // Translucent: stored as RGBA, un-premultiplied.
    var clear = image.RGBA(width: 64, height: 64)
    var i = 0
    while i < 64 * 64 {
        let a = uint32(i % 256)
        clear.Pixels[i * 4] = uint8(200 * a / 255)
        clear.Pixels[i * 4 + 1] = uint8(100 * a / 255)
        clear.Pixels[i * 4 + 2] = uint8(50 * a / 255)
        clear.Pixels[i * 4 + 3] = uint8(a)
        i += 1
    }
    roundTrip(clear, "translucent")

    // A flat screen-like image should compress hard.
    var flat = image.RGBA(width: 1024, height: 768)
    i = 0
    while i < 1024 * 768 {
        flat.Pixels[i * 4] = 0; flat.Pixels[i * 4 + 1] = 120; flat.Pixels[i * 4 + 2] = 215; flat.Pixels[i * 4 + 3] = 255
        i += 1
    }
    let flatBytes = png.Encode(flat)
    check(flatBytes.count < 20000, "flat 1024x768 compresses to \(flatBytes.count) bytes")
    roundTrip(flat, "flat 1024x768")

    // Garbage is rejected, not crashed on.
    do {
        let _ = try png.Decode([1, 2, 3])
        check(false, "garbage decoded")
    } catch {}

    if failures > 0 {
        print("\(failures) failures")
        return 1
    }
    print("all passed")
    return 0
}
