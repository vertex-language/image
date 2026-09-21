// cimage: the platform's image decoders, as a C ABI image/format
// calls. Decodes the formats the platform reads -- PNG, JPEG, GIF, WebP,
// HEIC, TIFF, BMP -- into premultiplied RGBA8, red first, top row first.
#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Decodes an image's bytes. Writes up to cap bytes of pixels and answers
// how many the image has, or 0 where the bytes are not an image the
// platform reads; width and height are set either way.
int32_t cimage_decode(const uint8_t* data, int32_t len, int32_t* width, int32_t* height,
                      uint8_t* pixels, int32_t cap);

#ifdef __cplusplus
}
#endif
