// cimage for macOS: ImageIO and CoreGraphics.
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#include "cimage.h"

int32_t cimage_decode(const uint8_t* data, int32_t len, int32_t* width, int32_t* height,
                      uint8_t* pixels, int32_t cap) {
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
