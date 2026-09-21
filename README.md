# image

[![package: stdlib](https://img.shields.io/badge/package-stdlib-f4f4f5?style=flat-square&labelColor=e4e4e7&color=18181b)](https://github.com/vertex-language)

Still images for the Vertex standard library: pixel buffers and codecs for
picture formats. Nothing here depends on windows or screens, so a server, a
command-line tool or a remote-desktop client can read and write images
without importing `ui`.

---

## Packages

| Package | What it is | Native code |
| :--- | :--- | :--- |
| **`image`** | `RGBA`: premultiplied 8-bit pixels, top row first, the layout `ui/draw` and `ui/window` use. | none |
| **`image/png`** | PNG decode (every color type and bit depth, palettes, `tRNS`, Adam7) and encode (RGB or RGBA, per-row filters, zlib), in pure Vertex. | none |
| **`image/format`** | `Decode` by sniffing the bytes: PNG in pure Vertex, JPEG/GIF/WebP/HEIC/TIFF/BMP through the platform until pure decoders land; `data:` URLs. | `cimage` (ImageIO) |

## Example

```swift
import "image"
import "image/png"
import "fs"

var img = image.RGBA(width: 64, height: 64)
// … fill img.Pixels …
try fs.WriteFile(fs.Path("out.png"), png.Encode(img))

let back = try png.Decode(try fs.ReadFile(fs.Path("out.png")))
```

## Tests

```bash
vsc build && (cd tests/png && python3 gen.py testdata && ../../.build/vsc/debug/check-png testdata)
```

`gen.py` writes a PNG for every color type × bit depth × interlace, with the
pixels each should decode to.

## Next

- `image/jpeg` (baseline + progressive), `image/gif`, `image/webp` in pure Vertex, so `image/format` stops needing the platform.
- Dynamic-Huffman blocks in the PNG encoder (fixed codes today), and lifting zlib into its own `compress/*` package once something else needs it.
