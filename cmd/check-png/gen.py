#!/usr/bin/env python3
"""Writes PNG fixtures for check-png: every color type and bit depth, with
and without Adam7, plus the premultiplied RGBA each should decode to.
Uses only the standard library (zlib makes dynamic-Huffman streams, which
exercises that inflate path). Run: python3 gen.py testdata"""
import os, struct, sys, zlib

W, H = 13, 9

def chunk(t, d):
    return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)

PASSES = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]

def pack_row(samples, depth):
    if depth == 8:
        return bytes(samples)
    if depth == 16:
        return b"".join(struct.pack(">H", s) for s in samples)
    out, acc, n = bytearray(), 0, 0
    for s in samples:
        acc = (acc << depth) | s
        n += depth
        if n == 8:
            out.append(acc); acc, n = 0, 0
    if n:
        out.append(acc << (8 - n))
    return bytes(out)

def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    return a if pa <= pb and pa <= pc else (b if pb <= pc else c)

def filter_rows(rows, bpp):
    out, prev = bytearray(), bytes(len(rows[0])) if rows else b""
    for y, row in enumerate(rows):
        f = y % 5
        out.append(f)
        for i, x in enumerate(row):
            a = row[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
            v = [x, x - a, x - b, x - (a + b) // 2, x - paeth(a, b, c)][f]
            out.append(v & 0xff)
        prev = row
    return bytes(out)

def make(ct, depth, interlace):
    maxv = (1 << depth) - 1
    ch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    pix = {}   # (x,y) -> samples
    for y in range(H):
        for x in range(W):
            if ct == 3:
                pix[x, y] = [(x + y * 3) % (1 << depth)]
            else:
                pix[x, y] = [((x * 37 + y * 11 + k * 53) * (maxv // 7 + 1)) % (maxv + 1) for k in range(ch)]
    # palette: 2^depth entries, alpha on the first few
    palette = [((i * 47) % 256, (i * 91) % 256, (i * 13) % 256) for i in range(1 << depth)] if ct == 3 else []
    trns = b""
    if ct == 3:
        trns = bytes([0, 128, 255][: min(3, 1 << depth)])
    elif ct == 0:
        trns = struct.pack(">H", pix[1, 0][0])
    elif ct == 2:
        trns = b"".join(struct.pack(">H", s) for s in pix[2, 1])
    bpp = max(1, ch * depth // 8)
    if interlace:
        raw = b""
        for (x0, y0, dx, dy) in PASSES:
            xs = list(range(x0, W, dx)); ys = list(range(y0, H, dy))
            if not xs or not ys:
                continue
            rows = [pack_row([s for x in xs for s in pix[x, y]], depth) for y in ys]
            raw += filter_rows(rows, bpp)
    else:
        rows = [pack_row([s for x in range(W) for s in pix[x, y]], depth) for y in range(H)]
        raw = filter_rows(rows, bpp)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, depth, ct, 0, 0, interlace))
    if palette:
        png += chunk(b"PLTE", bytes(v for p in palette for v in p))
    if trns:
        png += chunk(b"tRNS", trns)
    z = zlib.compress(raw, 9)
    png += chunk(b"IDAT", z[: len(z) // 2]) + chunk(b"IDAT", z[len(z) // 2:])   # split IDAT
    png += chunk(b"tEXt", b"Comment\x00fixture") + chunk(b"IEND", b"")

    def to8(v):
        return v >> 8 if depth == 16 else v * 255 // maxv
    exp = bytearray()
    for y in range(H):
        for x in range(W):
            s = pix[x, y]
            if ct == 3:
                i = s[0]; r, g, b = palette[i]; a = trns[i] if i < len(trns) else 255
            elif ct == 0:
                r = g = b = to8(s[0]); a = 0 if trns and struct.pack(">H", s[0]) == trns else 255
            elif ct == 2:
                r, g, b = (to8(v) for v in s)
                a = 0 if b"".join(struct.pack(">H", v) for v in s) == trns else 255
            elif ct == 4:
                r = g = b = to8(s[0]); a = to8(s[1])
            else:
                r, g, b, a = (to8(v) for v in s)
            if a != 255:
                r, g, b = ((v * a + 127) // 255 for v in (r, g, b))
            exp += bytes([r, g, b, a])
    return png, bytes(exp)

def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    names = []
    for ct, depths in [(0, [1, 2, 4, 8, 16]), (2, [8, 16]), (3, [1, 2, 4, 8]), (4, [8, 16]), (6, [8, 16])]:
        for d in depths:
            for il in (0, 1):
                png, exp = make(ct, d, il)
                name = f"ct{ct}-d{d}-i{il}"
                open(os.path.join(out, name + ".png"), "wb").write(png)
                open(os.path.join(out, name + ".rgba"), "wb").write(exp)
                names.append(name)


main()
