# image/draw

A software rasterizer over premultiplied RGBA pixels: fills, anti-aliased rounded corners, borders, gradients, 8-bit masks, images resampled up or down; `Color`, `Point`, `Size`, `Rect`.

```vertex
import "image/draw"
```

## Types

- **`Mask`** (struct): An 8-bit coverage mask: a glyph, or any shape to paint in one color.
- **`Image`** (class): Pixels of an image: premultiplied RGBA, red first, top row first.
- **`Canvas`** (struct): Somewhere to draw: premultiplied RGBA8 pixels, red first, top row first, which is what a window surface presents.
- **`Color`** (struct): A color: red, green, blue and alpha, each 0 to 255, not premultiplied.
- **`Rect`** (struct): A rectangle in CSS pixels: what layout measures in.
- **`IRect`** (struct): A rectangle in device pixels: what a canvas is measured in.
- **`Edges`** (struct): Four lengths, one per side, in the order CSS writes them.
- **`Radii`** (struct): The radius of each corner, clockwise from the top left.
- **`Point`** (struct): A position in CSS pixels, from the top-left corner.
- **`Size`** (struct): A size in CSS pixels.
- and 7 more

## Functions

- `func WithCanvas(_ pixels: inout [uint8], width: int32, height: int32, _ body: (Canvas) -> Void)`: Runs body with a canvas over pixels, which must hold width * height premultiplied RGBA pixels.
- `func RoundToInt(_ v: float32) -> int32`: The nearest whole number, halves rounding to even.

Part of the [`image`](https://github.com/vertex-language/image) repository.
