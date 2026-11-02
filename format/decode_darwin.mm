// platformDecode on macOS: ImageIO and CoreGraphics. See decode.cpp.
module;
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
module image.format;

int32_t platformDecode(const uint8_t* data, int32_t len, int32_t* width, int32_t* height,
                       uint8_t* pixels, int32_t cap) noexcept {
    if (width) *width = 0;
    if (height) *height = 0;
    if (data == NULL || len <= 0)
        return 0;
    @autoreleasepool {
        CFDataRef cfdata = CFDataCreateWithBytesNoCopy(NULL, data, (CFIndex)len, kCFAllocatorNull);
        if (cfdata == NULL)
            return 0;
        CGImageSourceRef source = CGImageSourceCreateWithData(cfdata, NULL);
        CFRelease(cfdata);
        if (source == NULL)
            return 0;
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CFRelease(source);
        if (image == NULL)
            return 0;
        size_t w = CGImageGetWidth(image);
        size_t h = CGImageGetHeight(image);
        if (w == 0 || h == 0 || w > 16384 || h > 16384) {
            CGImageRelease(image);
            return 0;
        }
        if (width) *width = (int32_t)w;
        if (height) *height = (int32_t)h;
        int32_t need = (int32_t)(w * h * 4);
        if (pixels == NULL || cap < need) {
            CGImageRelease(image);
            return need;
        }
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef ctx = CGBitmapContextCreate(pixels, w, h, 8, w * 4, space,
                                                 kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(space);
        if (ctx == NULL) {
            CGImageRelease(image);
            return 0;
        }
        CGContextSetBlendMode(ctx, kCGBlendModeCopy);
        CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), image);
        CGContextRelease(ctx);
        CGImageRelease(image);
        return need;
    }
}

int32_t platformFrameCount(const uint8_t* data, int32_t len) noexcept {
    if (data == NULL || len <= 0) return 0;
    @autoreleasepool {
        CFDataRef cfdata = CFDataCreateWithBytesNoCopy(NULL, data, (CFIndex)len, kCFAllocatorNull);
        if (cfdata == NULL) return 0;
        CGImageSourceRef source = CGImageSourceCreateWithData(cfdata, NULL);
        CFRelease(cfdata);
        if (source == NULL) return 0;
        int32_t n = (int32_t)CGImageSourceGetCount(source);
        CFRelease(source);
        return n;
    }
}

// How long a frame shows, from whichever format's properties it has.
static double frameDelay(CGImageSourceRef source, size_t index) {
    double out = 0;
    CFDictionaryRef props = CGImageSourceCopyPropertiesAtIndex(source, index, NULL);
    if (props == NULL) return 0;
    const CFStringRef groups[] = {kCGImagePropertyGIFDictionary, kCGImagePropertyPNGDictionary, kCGImagePropertyWebPDictionary};
    const CFStringRef unclamped[] = {kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyWebPUnclampedDelayTime};
    const CFStringRef clamped[] = {kCGImagePropertyGIFDelayTime, kCGImagePropertyAPNGDelayTime, kCGImagePropertyWebPDelayTime};
    for (int i = 0; i < 3 && out <= 0; i++) {
        CFDictionaryRef group = (CFDictionaryRef)CFDictionaryGetValue(props, groups[i]);
        if (group == NULL) continue;
        CFNumberRef n = (CFNumberRef)CFDictionaryGetValue(group, unclamped[i]);
        if (n != NULL) CFNumberGetValue(n, kCFNumberDoubleType, &out);
        if (out <= 0) {
            n = (CFNumberRef)CFDictionaryGetValue(group, clamped[i]);
            if (n != NULL) CFNumberGetValue(n, kCFNumberDoubleType, &out);
        }
    }
    CFRelease(props);
    return out;
}

int32_t platformDecodeFrame(const uint8_t* data, int32_t len, int32_t index, int32_t* width, int32_t* height,
                            uint8_t* pixels, int32_t cap, double* delay) noexcept {
    if (width) *width = 0;
    if (height) *height = 0;
    if (delay) *delay = 0;
    if (data == NULL || len <= 0 || index < 0) return 0;
    @autoreleasepool {
        CFDataRef cfdata = CFDataCreateWithBytesNoCopy(NULL, data, (CFIndex)len, kCFAllocatorNull);
        if (cfdata == NULL) return 0;
        CGImageSourceRef source = CGImageSourceCreateWithData(cfdata, NULL);
        CFRelease(cfdata);
        if (source == NULL) return 0;
        if (delay) *delay = frameDelay(source, (size_t)index);
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, (size_t)index, NULL);
        CFRelease(source);
        if (image == NULL) return 0;
        size_t w = CGImageGetWidth(image);
        size_t h = CGImageGetHeight(image);
        if (w == 0 || h == 0 || w > 16384 || h > 16384) {
            CGImageRelease(image);
            return 0;
        }
        if (width) *width = (int32_t)w;
        if (height) *height = (int32_t)h;
        int32_t need = (int32_t)(w * h * 4);
        if (pixels == NULL || cap < need) {
            CGImageRelease(image);
            return need;
        }
        CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
        CGContextRef ctx = CGBitmapContextCreate(pixels, w, h, 8, w * 4, space, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
        CGColorSpaceRelease(space);
        if (ctx == NULL) {
            CGImageRelease(image);
            return 0;
        }
        CGContextSetBlendMode(ctx, kCGBlendModeCopy);
        CGContextDrawImage(ctx, CGRectMake(0, 0, (CGFloat)w, (CGFloat)h), image);
        CGContextRelease(ctx);
        CGImageRelease(image);
        return need;
    }
}
