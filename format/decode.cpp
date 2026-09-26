// The platform's image decoders, for package image/format. They decode
// the formats the platform reads -- PNG, JPEG, GIF, WebP, HEIC, TIFF, BMP
// -- into premultiplied RGBA8, red first, top row first. macOS's are
// ImageIO and CoreGraphics (decode_darwin.mm); elsewhere there are none
// yet, and only what image/format decodes in Vertex is read.
module;
#include <stdint.h>
#if defined(__APPLE__)
#pragma vertex framework("CoreFoundation")
#pragma vertex framework("ImageIO")
#pragma vertex framework("CoreGraphics")
#endif
export module image.format;

// platformDecode decodes an image's bytes. It writes up to cap bytes of
// pixels and answers how many the image has, or 0 where the bytes are not
// an image the platform reads; width and height are set either way.
export int32_t platformDecode(const uint8_t* data, int32_t len, int32_t* width, int32_t* height,
                              uint8_t* pixels, int32_t cap) noexcept;

#if !defined(__APPLE__)
int32_t platformDecode(const uint8_t* data, int32_t len, int32_t* width, int32_t* height,
                       uint8_t* pixels, int32_t cap) noexcept {
    (void)data; (void)len; (void)pixels; (void)cap;
    if (width) *width = 0;
    if (height) *height = 0;
    return 0;
}
#endif
