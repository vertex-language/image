package draw

import "math"

/// A rectangle in CSS pixels: what layout measures in.
public struct Rect: Equatable {
    public var X: float32
    public var Y: float32
    public var Width: float32
    public var Height: float32

    public init(_ x: float32, _ y: float32, _ width: float32, _ height: float32) {
        X = x
        Y = y
        Width = width
        Height = height
    }

    public static let zero = Rect(0, 0, 0, 0)

    public var Right: float32 { return X + Width }
    public var Bottom: float32 { return Y + Height }
    public var IsEmpty: bool { return Width <= 0 || Height <= 0 }

    public func Contains(_ px: float32, _ py: float32) -> bool {
        return px >= X && py >= Y && px < X + Width && py < Y + Height
    }

    public func Offset(_ dx: float32, _ dy: float32) -> Rect {
        return Rect(X + dx, Y + dy, Width, Height)
    }

    /// The rectangle both cover; empty where they do not meet.
    public func Intersect(_ o: Rect) -> Rect {
        let x0 = X > o.X ? X : o.X
        let y0 = Y > o.Y ? Y : o.Y
        let x1 = Right < o.Right ? Right : o.Right
        let y1 = Bottom < o.Bottom ? Bottom : o.Bottom
        if x1 <= x0 || y1 <= y0 { return Rect(x0, y0, 0, 0) }
        return Rect(x0, y0, x1 - x0, y1 - y0)
    }

    /// The smallest rectangle covering both.
    public func Union(_ o: Rect) -> Rect {
        if IsEmpty { return o }
        if o.IsEmpty { return self }
        let x0 = X < o.X ? X : o.X
        let y0 = Y < o.Y ? Y : o.Y
        let x1 = Right > o.Right ? Right : o.Right
        let y1 = Bottom > o.Bottom ? Bottom : o.Bottom
        return Rect(x0, y0, x1 - x0, y1 - y0)
    }

    /// Scaled by a factor, with its edges snapped to whole device pixels
    /// the way a browser snaps a box: the edges round, so that two boxes
    /// that abut in CSS pixels abut on the screen.
    public func Snapped(scale: float32) -> IRect {
        let x0 = RoundToInt(X * scale)
        let y0 = RoundToInt(Y * scale)
        let x1 = RoundToInt((X + Width) * scale)
        let y1 = RoundToInt((Y + Height) * scale)
        return IRect(x0, y0, x1 - x0, y1 - y0)
    }
}

/// A rectangle in device pixels: what a canvas is measured in.
public struct IRect: Equatable {
    public var X: int32
    public var Y: int32
    public var Width: int32
    public var Height: int32

    public init(_ x: int32, _ y: int32, _ width: int32, _ height: int32) {
        X = x
        Y = y
        Width = width
        Height = height
    }

    public static let zero = IRect(0, 0, 0, 0)

    public var Right: int32 { return X + Width }
    public var Bottom: int32 { return Y + Height }
    public var IsEmpty: bool { return Width <= 0 || Height <= 0 }

    public func Contains(_ px: int32, _ py: int32) -> bool {
        return px >= X && py >= Y && px < X + Width && py < Y + Height
    }

    public func Intersect(_ o: IRect) -> IRect {
        let x0 = X > o.X ? X : o.X
        let y0 = Y > o.Y ? Y : o.Y
        let x1 = Right < o.Right ? Right : o.Right
        let y1 = Bottom < o.Bottom ? Bottom : o.Bottom
        if x1 <= x0 || y1 <= y0 { return IRect(x0, y0, 0, 0) }
        return IRect(x0, y0, x1 - x0, y1 - y0)
    }

    public func Union(_ o: IRect) -> IRect {
        if IsEmpty { return o }
        if o.IsEmpty { return self }
        let x0 = X < o.X ? X : o.X
        let y0 = Y < o.Y ? Y : o.Y
        let x1 = Right > o.Right ? Right : o.Right
        let y1 = Bottom > o.Bottom ? Bottom : o.Bottom
        return IRect(x0, y0, x1 - x0, y1 - y0)
    }
}

/// Four lengths, one per side, in the order CSS writes them.
public struct Edges: Equatable {
    public var Top: float32
    public var Right: float32
    public var Bottom: float32
    public var Left: float32

    public init(_ top: float32, _ right: float32, _ bottom: float32, _ left: float32) {
        Top = top
        Right = right
        Bottom = bottom
        Left = left
    }

    public init(all: float32) {
        Top = all
        Right = all
        Bottom = all
        Left = all
    }

    public static let zero = Edges(0, 0, 0, 0)

    public var Horizontal: float32 { return Left + Right }
    public var Vertical: float32 { return Top + Bottom }
}

/// The radius of each corner, clockwise from the top left.
public struct Radii: Equatable {
    public var TopLeft: float32
    public var TopRight: float32
    public var BottomRight: float32
    public var BottomLeft: float32

    public init(_ tl: float32, _ tr: float32, _ br: float32, _ bl: float32) {
        TopLeft = tl
        TopRight = tr
        BottomRight = br
        BottomLeft = bl
    }

    public init(all: float32) {
        TopLeft = all
        TopRight = all
        BottomRight = all
        BottomLeft = all
    }

    public static let zero = Radii(0, 0, 0, 0)

    public var IsZero: bool {
        return TopLeft <= 0 && TopRight <= 0 && BottomRight <= 0 && BottomLeft <= 0
    }

    public func Scaled(_ s: float32) -> Radii {
        return Radii(TopLeft * s, TopRight * s, BottomRight * s, BottomLeft * s)
    }

    /// Each radius shrunk by the border on its two sides, which is the
    /// curve of the padding edge inside a rounded border.
    public func Inset(_ e: Edges) -> Radii {
        return Radii(
            math.Max(TopLeft - math.Max(e.Top, e.Left), 0),
            math.Max(TopRight - math.Max(e.Top, e.Right), 0),
            math.Max(BottomRight - math.Max(e.Bottom, e.Right), 0),
            math.Max(BottomLeft - math.Max(e.Bottom, e.Left), 0))
    }

    /// Radii that fit the rectangle: where the sum of two along a side
    /// exceeds it, all are scaled down together, as CSS does.
    public func Fitted(_ w: float32, _ h: float32) -> Radii {
        var f: float32 = 1
        let top = TopLeft + TopRight
        let bottom = BottomLeft + BottomRight
        let left = TopLeft + BottomLeft
        let right = TopRight + BottomRight
        if top > w && top > 0 { let s = w / top; if s < f { f = s } }
        if bottom > w && bottom > 0 { let s = w / bottom; if s < f { f = s } }
        if left > h && left > 0 { let s = h / left; if s < f { f = s } }
        if right > h && right > 0 { let s = h / right; if s < f { f = s } }
        if f >= 1 { return self }
        return Scaled(f)
    }
}

/// The nearest whole number, halves rounding to even.
public func RoundToInt(_ v: float32) -> int32 {
    return math.RoundToInt(v)
}

/// A position in CSS pixels, from the top-left corner.
public struct Point: Equatable {
    public var X: float32
    public var Y: float32

    public init(_ x: float32, _ y: float32) {
        X = x
        Y = y
    }

    public static let zero = Point(0, 0)
}

/// A size in CSS pixels.
public struct Size: Equatable {
    public var Width: float32
    public var Height: float32

    public init(_ width: float32, _ height: float32) {
        Width = width
        Height = height
    }
}
