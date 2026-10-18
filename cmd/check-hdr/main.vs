// check-hdr decodes RGBE images built here byte by byte (flat quads and
// run-length scanlines) and checks the values; given a file, it also
// decodes that and says how long it took.
//
//     vsc run check-hdr [-- sky.hdr]
package main

import (
    "fs"
    "image/hdr"
    "time"
)

var failures = 0

func check(_ ok: bool, _ what: string) {
    if !ok {
        failures += 1
        print("FAIL: \(what)")
    } else {
        print("ok   \(what)")
    }
}

func header(_ w: int, _ h: int) -> [uint8] {
    return [uint8]("#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y \(h) +X \(w)\n".utf8)
}

func near(_ a: float32, _ b: float32) -> bool { return a > b * 0.99 && a < b * 1.01 }

func main() -> int32 {
    // Flat: two texels, (128, 64, 32, e=129) is (1.0, 0.5, 0.25) give or
    // take the half-step; a zero exponent is black.
    var flat = header(2, 1)
    flat += [128, 64, 32, 129, 200, 10, 10, 0]
    do {
        let img = try hdr.Decode(flat)
        check(img.Width == 2 && img.Height == 1, "flat: size")
        let (r, g, b) = img.At(0, 0)
        check(near(r, 1.0039) && near(g, 0.5039) && near(b, 0.2539), "flat: values \(r) \(g) \(b)")
        let (r2, _, _) = img.At(1, 0)
        check(r2 == 0, "flat: zero exponent is black")
    } catch {
        check(false, "flat: \(error)")
    }

    // Run-length: 8 texels a row, two rows. Each component: a run of 8
    // (count 136) of one value, except blue as literals.
    var rle = header(8, 2)
    for y in 0..<2 {
        rle += [2, 2, 0, 8]
        rle += [136, uint8(100 + y)]                 // red
        rle += [136, 50]                             // green
        rle += [8, 0, 10, 20, 30, 40, 50, 60, 70]    // blue, literal
        rle += [136, 130]                            // exponent: ×4/256
    }
    do {
        let img = try hdr.Decode(rle)
        check(img.Width == 8 && img.Height == 2, "rle: size")
        let (r, g, b) = img.At(3, 1)
        check(near(r, 101.5 * 4 / 256) && near(g, 50.5 * 4 / 256) && near(b, 30.5 * 4 / 256), "rle: values \(r) \(g) \(b)")
    } catch {
        check(false, "rle: \(error)")
    }

    do {
        _ = try hdr.Decode([uint8]("not an image".utf8))
        check(false, "rejects what isn't RGBE")
    } catch {
        check(true, "rejects what isn't RGBE")
    }

    let args = CommandLine.arguments
    if args.count > 1 {
        do {
            let bytes = try fs.ReadFile(fs.Path(args[1]))
            let t0 = time.Instant.Now()
            let img = try hdr.Decode(bytes)
            let ms = t0.Elapsed().AsMilliseconds()
            var peak: float32 = 0
            var px = 0
            for i in 0..<(img.Width * img.Height) {
                let l = img.Pixels[i * 3] + img.Pixels[i * 3 + 1] + img.Pixels[i * 3 + 2]
                if l > peak { peak = l; px = i }
            }
            print("\(args[1]): \(img.Width)×\(img.Height) in \(ms) ms; brightest \(peak) at \(px % img.Width), \(px / img.Width)")
        } catch {
            check(false, "\(args[1]): \(error)")
        }
    }
    return failures == 0 ? 0 : 1
}
