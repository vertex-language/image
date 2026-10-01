# image/format

Decodes an image whose format isn't known ahead of time: it sniffs the bytes and hands them to the right decoder.

```vertex
import "image/format"
```

## Types

- **`Kind`** (enum): Kind is an image file format, as recognised from its first bytes.

## Functions

- `func Sniff(_ b: [uint8]) -> Kind`: Sniff names the format of an image's bytes.
- `func Decode(_ bytes: [uint8]) -> image.RGBA?`: Decode decodes an image's bytes into premultiplied RGBA. Nil where the bytes are not an image anything here reads.
- `func DecodeDataURL(_ url: string) -> image.RGBA?`: DecodeDataURL decodes a `data:` URL's image, base64 or plain.

Part of the [`image`](https://github.com/vertex-language/image) repository.
