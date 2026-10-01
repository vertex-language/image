# image/png

Reads and writes PNG images (RFC 2083, PNG 1.2): every color type and bit depth, palettes with transparency, and Adam7 interlacing on the way in; 8-bit RGB or RGBA with per-row filters and zlib compression on the way out.

```vertex
import "image/png"
```

## Types

- **`PngError`** (enum): PngError is why bytes could not be decoded.
- **`Config`** (struct): Config is what the header says about an image.

## Functions

- `func Encode(_ img: image.RGBA) -> [uint8]`: Encode writes an image as a PNG. Opaque images are stored as RGB, others as RGBA with the color un-premultiplied.
- `func DecodeConfig(_ data: [uint8]) throws -> Config`: DecodeConfig reads only the header.
- `func Decode(_ data: [uint8]) throws -> image.RGBA`: Decode reads a PNG into premultiplied RGBA. 16-bit samples keep their high byte; gamma and color profiles are not applied.

Part of the [`image`](https://github.com/vertex-language/image) repository.
