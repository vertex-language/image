package draw

import "math"

// An image cut into nine by four slice lines and drawn round a box:
// the corners into the corners, the edges along the sides, stretched or
// tiled, and the middle over the inside if wanted. CSS's border-image
// draws this way, and so does a skinned button.

/// How an edge's slice covers the length of its side.
public enum SliceRepeat: Equatable {
    /// One copy, stretched to the length.
    case stretch
    /// CSS's repeat: copies at the slice's scaled size, centred on the side, the ends
    /// cut off.
    case tile
    /// Copies resized so a whole number of them fits.
    case round
    /// As many whole copies as fit, the space left shared between them.
    case space
}

extension Image {
    /// The pixels of r, which is kept inside the image.
    public func Cropped(_ r: IRect) -> Image {
        let area = r.Intersect(IRect(0, 0, Width, Height))
        if area.IsEmpty { return Image(width: 0, height: 0, pixels: []) }
        var out = [uint8](repeating: 0, count: int(area.Width) * int(area.Height) * 4)
        let rowBytes = int(area.Width) * 4
        var y: int32 = 0
        while y < area.Height {
            let from = (int(area.Y + y) * int(Width) + int(area.X)) * 4
            let to = int(y) * rowBytes
            var i = 0
            while i < rowBytes {
                out[to + i] = Pixels[from + i]
                i += 1
            }
            y += 1
        }
        return Image(width: area.Width, height: area.Height, pixels: out)
    }
}

extension Canvas {
    /// Draws img cut at slice (in the image's pixels from each side)
    /// round area: each corner piece into a corner widths in from the
    /// sides, each edge piece along its side by the side's repeat, and
    /// the middle piece over the inside where fill is set. Widths too
    /// wide for the area are scaled down together.
    public func DrawNineSlice(_ img: Image, into area: Rect, slice: Edges, widths: Edges, fill: bool,
                              horizontal: SliceRepeat, vertical: SliceRepeat) {
        if img.Width <= 0 || img.Height <= 0 || area.Width <= 0 || area.Height <= 0 { return }
        let iw = float32(img.Width)
        let ih = float32(img.Height)
        let sl = math.Clamp(slice.Left, 0, iw)
        let sr = math.Clamp(slice.Right, 0, iw - sl)
        let st = math.Clamp(slice.Top, 0, ih)
        let sb = math.Clamp(slice.Bottom, 0, ih - st)
        var w = widths
        var f: float32 = 1
        if w.Left + w.Right > area.Width { f = math.Min(f, area.Width / (w.Left + w.Right)) }
        if w.Top + w.Bottom > area.Height { f = math.Min(f, area.Height / (w.Top + w.Bottom)) }
        w = Edges(w.Top * f, w.Right * f, w.Bottom * f, w.Left * f)
        let sx: [float32] = [0, sl, iw - sr, iw]
        let sy: [float32] = [0, st, ih - sb, ih]
        let dx: [float32] = [area.X, area.X + w.Left, area.Right - w.Right, area.Right]
        let dy: [float32] = [area.Y, area.Y + w.Top, area.Bottom - w.Bottom, area.Bottom]
        // The middle's copies scale as the top and left edges' do (or
        // the bottom and right, where those have no slice).
        let across = st > 0 ? w.Top / st : (sb > 0 ? w.Bottom / sb : 1)
        let down = sl > 0 ? w.Left / sl : (sr > 0 ? w.Right / sr : 1)
        var row = 0
        while row < 3 {
            var col = 0
            while col < 3 {
                if row == 1 && col == 1 && !fill { col += 1; continue }
                let src = IRect(RoundToInt(sx[col]), RoundToInt(sy[row]),
                                RoundToInt(sx[col + 1]) - RoundToInt(sx[col]), RoundToInt(sy[row + 1]) - RoundToInt(sy[row]))
                let dst = Rect(dx[col], dy[row], dx[col + 1] - dx[col], dy[row + 1] - dy[row])
                if src.IsEmpty || dst.Width <= 0 || dst.Height <= 0 { col += 1; continue }
                let piece = img.Cropped(src)
                let pw = float32(src.Width)
                let ph = float32(src.Height)
                // A copy's size: a corner fills its corner; an edge's
                // copy keeps its side's thickness and the slice's shape.
                var tw = dst.Width
                var th = dst.Height
                if col == 1 { tw = pw * (row == 1 ? across : dst.Height / ph) }
                if row == 1 { th = ph * (col == 1 ? down : dst.Width / pw) }
                tilePiece(piece, dst, tw, th, col == 1 ? horizontal : .stretch, row == 1 ? vertical : .stretch)
                col += 1
            }
            row += 1
        }
    }

    func tilePiece(_ piece: Image, _ dst: Rect, _ tw: float32, _ th: float32, _ mh: SliceRepeat, _ mv: SliceRepeat) {
        if tw <= 0 || th <= 0 { return }
        let xs = slicePlaces(dst.X, dst.Width, tw, mh)
        let ys = slicePlaces(dst.Y, dst.Height, th, mv)
        // The same pixels, clipped to the side.
        var side = self
        let x0 = RoundToInt(dst.X)
        let y0 = RoundToInt(dst.Y)
        side.Clip = Clip.Intersect(IRect(x0, y0, RoundToInt(dst.Right) - x0, RoundToInt(dst.Bottom) - y0))
        for y in ys.starts {
            for x in xs.starts {
                let px = RoundToInt(x)
                let py = RoundToInt(y)
                side.DrawImage(piece, into: IRect(px, py, RoundToInt(x + xs.size) - px, RoundToInt(y + ys.size) - py))
            }
        }
    }
}

/// Where the copies of a piece go along a side from start: their
/// starts and their size.
func slicePlaces(_ start: float32, _ length: float32, _ tile: float32, _ mode: SliceRepeat) -> (starts: [float32], size: float32) {
    switch mode {
    case .stretch:
        return (starts: [start], size: length)
    case .tile:
        // One copy centred, and as many each side as reach the ends.
        let first = start + (length - tile) / 2
        let before = math.Ceil((first - start) / tile)
        var at = first - before * tile
        var out: [float32] = []
        while at < start + length {
            out.append(at)
            at += tile
        }
        return (starts: out, size: tile)
    case .round:
        let n = math.Max(1, math.Round(length / tile))
        let size = length / n
        var out: [float32] = []
        var i: float32 = 0
        while i < n {
            out.append(start + i * size)
            i += 1
        }
        return (starts: out, size: size)
    case .space:
        let n = math.Floor(length / tile)
        if n < 1 { return (starts: [], size: tile) }
        let gap = (length - n * tile) / (n + 1)
        var out: [float32] = []
        var i: float32 = 0
        while i < n {
            out.append(start + gap + i * (tile + gap))
            i += 1
        }
        return (starts: out, size: tile)
    }
}
