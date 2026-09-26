// Package image holds the pixel buffers that the still-image codecs
// (image/png, …) decode into and encode from. It does no I/O and knows
// nothing about windows or screens, so a server or a command-line tool
// can use it without touching ui.
package image

/// RGBA is an image of 8-bit red, green, blue and alpha samples, top row
/// first, four bytes per pixel with no padding between rows. Colors are
/// premultiplied by alpha: the layout ui/draw and ui/window use.
public struct RGBA {
    public var Width: int
    public var Height: int
    public var Pixels: [uint8]

    /// A transparent black image.
    public init(width: int, height: int) {
        self.Width = width
        self.Height = height
        self.Pixels = [uint8](repeating: 0, count: width * height * 4)
    }

    /// An image over existing pixels; pixels must hold width * height * 4 bytes.
    public init(width: int, height: int, pixels: [uint8]) {
        self.Width = width
        self.Height = height
        self.Pixels = pixels
    }

    /// Stride is the number of bytes from one row to the next.
    public var Stride: int { return Width * 4 }

    /// IsOpaque reports whether every pixel has alpha 255.
    public var IsOpaque: bool {
        var i = 3
        let n = Pixels.count
        while i < n {
            if Pixels[i] != 255 { return false }
            i += 4
        }
        return true
    }
}
