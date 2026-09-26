# image

[![package: vs-package](https://img.shields.io/badge/package-vs--package-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)
[![formats: png](https://img.shields.io/badge/formats-png-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language/image)

Image formats and pixel buffers: pixel models, color representations, and format codecs for reading and writing images without window or screen dependencies.

---

## Packages

| Package | What it is | Native code |
| :--- | :--- | :--- |
| **`image`** | `RGBA`: premultiplied 8-bit pixels, top row first. | none |
| **`image/png`** | PNG decode (every color type and bit depth, palettes, `tRNS`, Adam7) and encode (RGB or RGBA, per-row filters, zlib). | none |
| **`image/draw`** | A software rasterizer over premultiplied RGBA pixels: fills, anti-aliased rounded corners, borders, gradients, 8-bit masks, images resampled up or down; `Color`, `Point`, `Size`, `Rect`. | none |
| **`image/format`** | `Decode` by sniffing the bytes: PNG, and platform image format decoding; `data:` URLs. | its C++ module `image.format`: ImageIO on macOS (`format/decode_darwin.mm`) |

---

## Quick Start

Run the PNG conformance test suite in `cmd/` directly:

```bash
vsc run check-png -- cmd/check-png/testdata
```

### Encoding and Decoding PNG

```swift
package main

import (
    "fs"
    "image"
    "image/png"
)

func main() -> int32 {
    var img = image.RGBA(width: 64, height: 64)
    // fill img.Pixels...
    try! fs.WriteFile(fs.Path("out.png"), png.Encode(img))

    let back = try! png.Decode(try! fs.ReadFile(fs.Path("out.png")))
    print("Decoded image: \(back.Width)x\(back.Height)")
    return 0
}
```

---

## Tests

Run the PNG conformance test suite and the rasterizer's checks:

```bash
vsc run check-png -- cmd/check-png/testdata
vsc run check-draw
```

---

## License

[MIT](LICENSE)
