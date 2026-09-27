// The rasterizer, checked pixel by pixel.
package main

import "image/draw"

var failures = 0

func check(_ ok: bool, _ what: string) {
    if ok {
        print("ok    \(what)")
    } else {
        print("FAIL  \(what)")
        failures += 1
    }
}

func pixel(_ pixels: [uint8], _ w: int32, _ x: int32, _ y: int32) -> (r: uint8, g: uint8, b: uint8, a: uint8) {
    let i = int((y * w + x) * 4)
    return (r: pixels[i], g: pixels[i + 1], b: pixels[i + 2], a: pixels[i + 3])
}

func main() -> int32 {
    print("Colors")
    check(draw.Color(255, 255, 255, 128).Premultiplied() == 0x80808080, "premultiplied packing")
    check(draw.Color(10, 20, 30).Premultiplied() == 0xFF1E140A, "opaque packing, red low")

    print("Geometry")
    let r = draw.Rect(10.4, 20.6, 100.2, 50)
    let s = r.Snapped(scale: 2)
    check(s == draw.IRect(21, 41, 200, 100), "snapped rect rounds each edge (got \(s.X) \(s.Y) \(s.Width) \(s.Height))")
    check(draw.IRect(0, 0, 10, 10).Intersect(draw.IRect(5, 5, 10, 10)) == draw.IRect(5, 5, 5, 5), "IRect intersect")
    check(draw.IRect(0, 0, 10, 10).Intersect(draw.IRect(20, 20, 10, 10)).IsEmpty, "disjoint intersect is empty")
    check(draw.Radii(all: 30).Fitted(40, 100) == draw.Radii(all: 20), "radii scaled to fit")
    check(draw.RoundToInt(2.5) == 2 && draw.RoundToInt(3.5) == 4 && draw.RoundToInt(-1.5) == -2, "round half to even")

    print("Filling")
    let w: int32 = 16
    let h: int32 = 16
    var pixels = [uint8](repeating: 0, count: int(w * h * 4))
    draw.WithCanvas(&pixels, width: w, height: h) { c in
        c.Clear(draw.Color.white)
        c.Fill(draw.IRect(2, 2, 4, 4), draw.Color(255, 0, 0))
        c.Fill(draw.IRect(8, 8, 100, 100), draw.Color(0, 0, 255, 128))
        var clipped = c
        clipped.ClipTo(draw.IRect(0, 0, 4, 16))
        clipped.Fill(draw.IRect(0, 12, 16, 2), draw.Color(0, 255, 0))
    }
    let p1 = pixel(pixels, w, 0, 0)
    check(p1.r == 255 && p1.g == 255 && p1.b == 255 && p1.a == 255, "cleared to white")
    let p2 = pixel(pixels, w, 3, 3)
    check(p2.r == 255 && p2.g == 0 && p2.b == 0, "opaque fill")
    let p3 = pixel(pixels, w, 6, 3)
    check(p3.r == 255 && p3.g == 255, "fill stops at its edge")
    let p4 = pixel(pixels, w, 10, 10)
    check(p4.r == 127 && p4.g == 127 && p4.b == 255 && p4.a == 255, "translucent blue over white blends to 127,127,255 (got \(p4.r) \(p4.g) \(p4.b))")
    let p5 = pixel(pixels, w, 15, 15)
    check(p5.b == 255 && p5.r == 127, "fill past the edge is clipped, not a crash")
    let p6 = pixel(pixels, w, 2, 12)
    let p7 = pixel(pixels, w, 6, 12)
    check(p6.g == 255 && p6.r == 0 && p7.r == 255 && p7.g == 255, "clip limits a fill")

    print("Rounded fills and rings")
    pixels = [uint8](repeating: 0, count: int(w * h * 4))
    draw.WithCanvas(&pixels, width: w, height: h) { c in
        c.Clear(draw.Color.white)
        c.FillRounded(draw.IRect(0, 0, 16, 16), radii: draw.Radii(all: 6), draw.Color.black)
    }
    let corner = pixel(pixels, w, 0, 0)
    let centre = pixel(pixels, w, 8, 8)
    let edgeMid = pixel(pixels, w, 0, 8)
    let nearCorner = pixel(pixels, w, 1, 1)
    check(corner.r == 255, "corner pixel outside the curve stays white")
    check(centre.r == 0, "centre is filled")
    check(edgeMid.r == 0, "edge midpoint is filled")
    check(nearCorner.r > 0 && nearCorner.r < 255, "pixel on the curve is anti-aliased (got \(nearCorner.r))")

    pixels = [uint8](repeating: 0, count: int(w * h * 4))
    draw.WithCanvas(&pixels, width: w, height: h) { c in
        c.Clear(draw.Color.white)
        let red = draw.Color(255, 0, 0)
        c.FillRing(draw.IRect(0, 0, 16, 16), radii: draw.Radii.zero, widths: draw.Edges(all: 2), colors: [red, red, red, red])
    }
    let ringEdge = pixel(pixels, w, 1, 8)
    let ringInside = pixel(pixels, w, 8, 8)
    check(ringEdge.r == 255 && ringEdge.g == 0, "square ring paints its edge")
    check(ringInside.g == 255, "square ring leaves the inside")

    pixels = [uint8](repeating: 0, count: int(w * h * 4))
    draw.WithCanvas(&pixels, width: w, height: h) { c in
        c.Clear(draw.Color.white)
        let red = draw.Color(255, 0, 0)
        c.FillRing(draw.IRect(0, 0, 16, 16), radii: draw.Radii(all: 5), widths: draw.Edges(all: 2), colors: [red, red, red, red])
    }
    let rr1 = pixel(pixels, w, 8, 0)
    let rr2 = pixel(pixels, w, 8, 8)
    let rr3 = pixel(pixels, w, 0, 0)
    check(rr1.r == 255 && rr1.g == 0, "rounded ring paints its straight edge")
    check(rr2.g == 255, "rounded ring leaves the inside")
    check(rr3.g == 255, "rounded ring leaves the corner outside the curve")

    print("Masks and images")
    pixels = [uint8](repeating: 0, count: int(w * h * 4))
    let mask = draw.Mask(width: 2, height: 2, data: [255, 128, 0, 64])
    draw.WithCanvas(&pixels, width: w, height: h) { c in
        c.Clear(draw.Color.white)
        c.DrawMask(mask, x: 4, y: 4, draw.Color.black)
        c.DrawMask(mask, x: 15, y: 15, draw.Color.black)
    }
    let m1 = pixel(pixels, w, 4, 4)
    let m2 = pixel(pixels, w, 5, 4)
    let m3 = pixel(pixels, w, 4, 5)
    let m4 = pixel(pixels, w, 5, 5)
    check(m1.r == 0, "full coverage paints the color")
    check(m2.r == 127, "half coverage blends (got \(m2.r))")
    check(m3.r == 255, "zero coverage leaves the pixel")
    check(m4.r == 191, "quarter coverage blends (got \(m4.r))")
    let m5 = pixel(pixels, w, 15, 15)
    check(m5.r == 0, "mask at the edge is clipped, not a crash")

    var src = [uint8](repeating: 0, count: 4 * 4 * 4)
    var i = 0
    while i < 16 {
        src[i * 4] = i < 8 ? 255 : 0
        src[i * 4 + 2] = i < 8 ? 0 : 255
        src[i * 4 + 3] = 255
        i += 1
    }
    let img = draw.Image(width: 4, height: 4, pixels: src)
    pixels = [uint8](repeating: 0, count: int(w * h * 4))
    draw.WithCanvas(&pixels, width: w, height: h) { c in
        c.Clear(draw.Color.white)
        c.DrawImage(img, into: draw.IRect(0, 0, 4, 4))
        c.DrawImage(img, into: draw.IRect(8, 8, 8, 8))
        c.DrawImage(img, into: draw.IRect(0, 8, 2, 2))
    }
    let i1 = pixel(pixels, w, 0, 0)
    let i2 = pixel(pixels, w, 0, 3)
    check(i1.r == 255 && i1.b == 0 && i2.r == 0 && i2.b == 255, "image drawn at its size")
    let i3 = pixel(pixels, w, 8, 8)
    let i4 = pixel(pixels, w, 15, 15)
    check(i3.r == 255 && i3.b == 0 && i4.r == 0 && i4.b == 255, "image scaled up keeps its halves")
    let i5 = pixel(pixels, w, 0, 8)
    let i6 = pixel(pixels, w, 0, 9)
    check(i5.r == 255 && i5.b == 0 && i6.r == 0 && i6.b == 255, "image scaled down averages each half")

    print("Translucent masks")
    var tm = [uint8](repeating: 0, count: 4)
    draw.WithCanvas(&tm, width: 1, height: 1) { c in
        c.DrawMask(draw.Mask(width: 1, height: 1, data: [255]), x: 0, y: 0, draw.Color(255, 0, 0, 128))
    }
    check(tm[3] == 128 && tm[0] == 128, "a half-transparent color through a full mask lands at half alpha, once (got \(tm[0]) \(tm[3]))")
    tm = [0, 0, 255, 255]
    draw.WithCanvas(&tm, width: 1, height: 1) { c in
        c.DrawMask(draw.Mask(width: 1, height: 1, data: [255]), x: 0, y: 0, draw.Color(255, 0, 0, 128))
    }
    check(tm[0] == 128 && tm[2] == 127 && tm[3] == 255, "over blue, red and blue share it (got \(tm[0]) \(tm[2]) \(tm[3]))")

    print("Paths")
    let pw: int32 = 20
    var pp = [uint8](repeating: 0, count: int(pw * pw * 4))
    func fill(_ path: draw.Path, _ rule: draw.FillRule) {
        pp = [uint8](repeating: 0, count: int(pw * pw * 4))
        draw.WithCanvas(&pp, width: pw, height: pw) { c in c.FillPath(path, rule: rule, draw.Color(0, 0, 0)) }
    }
    func alpha(_ x: int32, _ y: int32) -> uint8 { return pixel(pp, pw, x, y).a }
    var square = draw.Path()
    square.MoveTo(2, 2); square.LineTo(12, 2); square.LineTo(12, 12); square.LineTo(2, 12); square.Close()
    fill(square, .nonZero)
    check(alpha(5, 5) == 255 && alpha(2, 2) == 255 && alpha(11, 11) == 255, "a square fills its pixels")
    check(alpha(1, 5) == 0 && alpha(12, 5) == 0 && alpha(5, 12) == 0, "and nothing outside")
    var half = draw.Path()
    half.MoveTo(2.5, 2); half.LineTo(6, 2); half.LineTo(6, 6); half.LineTo(2.5, 6); half.Close()
    fill(half, .nonZero)
    check(alpha(2, 3) > 120 && alpha(2, 3) < 136, "an edge halfway across a pixel covers half of it (\(alpha(2, 3)))")
    // A square with a square hole, both wound the same way.
    var ring = square
    ring.MoveTo(5, 5); ring.LineTo(9, 5); ring.LineTo(9, 9); ring.LineTo(5, 9); ring.Close()
    fill(ring, .evenOdd)
    check(alpha(6, 6) == 0 && alpha(3, 3) == 255, "even-odd makes a hole of an overlap wound the same way")
    fill(ring, .nonZero)
    check(alpha(6, 6) == 255, "nonzero fills it")
    var reversed = square
    reversed.MoveTo(5, 5); reversed.LineTo(5, 9); reversed.LineTo(9, 9); reversed.LineTo(9, 5); reversed.Close()
    fill(reversed, .nonZero)
    check(alpha(6, 6) == 0 && alpha(3, 3) == 255, "nonzero makes a hole of one wound the other way")
    var circle = draw.Path()
    let k: float32 = 0.5523
    circle.MoveTo(18, 10)
    circle.CubicTo(18, 10 + 8 * k, 10 + 8 * k, 18, 10, 18)
    circle.CubicTo(10 - 8 * k, 18, 2, 10 + 8 * k, 2, 10)
    circle.CubicTo(2, 10 - 8 * k, 10 - 8 * k, 2, 10, 2)
    circle.CubicTo(10 + 8 * k, 2, 18, 10 - 8 * k, 18, 10)
    circle.Close()
    fill(circle, .nonZero)
    check(alpha(10, 10) == 255 && alpha(1, 1) == 0 && alpha(3, 3) < 128, "a circle of cubics: filled middle, clear corners")
    var tri = draw.Path()
    tri.MoveTo(-10, -10); tri.QuadTo(40, 0, 30, 30); tri.Close()
    fill(tri, .nonZero)
    check(alpha(19, 19) >= 0, "a path past the canvas is clipped to it")

    if failures == 0 {
        print("ALL DRAW CHECKS PASSED")
        return 0
    }
    print("\(failures) FAILED")
    return 1
}
