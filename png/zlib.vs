// zlib streams (RFC 1950) around DEFLATE (RFC 1951): the inflater takes
// every block type; the deflater does LZ77 over a 32 KiB window with hash
// chains and codes it with the fixed Huffman tables, which is small code
// and compresses screen-like images well.
package png

// --- inflate ---

struct bitReader {
    var data: [uint8]
    var pos: int = 0
    var bits: uint32 = 0
    var count: int = 0

    init(_ data: [uint8], at: int) {
        self.data = data
        self.pos = at
    }

    mutating func need(_ n: int) throws {
        while count < n {
            if pos >= data.count { throw PngError.badData("deflate stream ends early") }
            bits |= uint32(data[pos]) << uint32(count)
            pos += 1
            count += 8
        }
    }

    mutating func take(_ n: int) throws -> int {
        if n == 0 { return 0 }
        try need(n)
        let v = int(bits & ((uint32(1) << uint32(n)) - 1))
        bits = bits >> uint32(n)
        count -= n
        return v
    }

    mutating func alignToByte() {
        bits = 0
        count = 0
    }
}

// huffman is a canonical code as counts per length and symbols in code
// order, plus a table that resolves codes of up to fastBits bits at once.
struct huffman {
    var counts: [int]
    var symbols: [int]
    // fast[code reversed] = symbol << 4 | length, or -1 when longer.
    var fast: [int]

    init(_ lengths: [int]) throws {
        counts = [int](repeating: 0, count: 16)
        for l in lengths { counts[l] += 1 }
        counts[0] = 0
        var offs = [int](repeating: 0, count: 16)
        var i = 1
        while i < 15 { offs[i + 1] = offs[i] + counts[i]; i += 1 }
        symbols = [int](repeating: 0, count: lengths.count)
        var s = 0
        while s < lengths.count {
            if lengths[s] != 0 {
                symbols[offs[lengths[s]]] = s
                offs[lengths[s]] += 1
            }
            s += 1
        }
        // Fill the fast table by walking the canonical codes.
        fast = [int](repeating: -1, count: 1 << fastBits)
        var code = 0
        var index = 0
        var len = 1
        while len <= fastBits {
            var n = 0
            while n < counts[len] {
                let sym = symbols[index]
                let rev = reverseBits(code, len)
                var fill = rev
                while fill < (1 << fastBits) {
                    fast[fill] = (sym << 4) | len
                    fill += 1 << len
                }
                code += 1
                index += 1
                n += 1
            }
            code = code << 1
            len += 1
        }
    }

    func decode(_ br: inout bitReader) throws -> int {
        // Top up without failing: the last symbols of a stream can be
        // shorter than fastBits.
        while br.count < fastBits && br.pos < br.data.count {
            br.bits |= uint32(br.data[br.pos]) << uint32(br.count)
            br.pos += 1
            br.count += 8
        }
        let e = fast[int(br.bits & uint32((1 << fastBits) - 1))]
        if e >= 0 && (e & 15) <= br.count {
            let l = e & 15
            br.bits = br.bits >> uint32(l)
            br.count -= l
            return e >> 4
        }
        // Slow path: one bit at a time (puff's decode).
        var code = 0
        var first = 0
        var index = 0
        var len = 1
        while len <= 15 {
            code |= try br.take(1)
            let count = counts[len]
            if code - count < first { return symbols[index + (code - first)] }
            index += count
            first += count
            first = first << 1
            code = code << 1
            len += 1
        }
        throw PngError.badData("bad Huffman code")
    }
}

let fastBits = 9

func reverseBits(_ v: int, _ n: int) -> int {
    var r = 0
    var x = v
    var i = 0
    while i < n {
        r = (r << 1) | (x & 1)
        x = x >> 1
        i += 1
    }
    return r
}

func lengthBase() -> [int] {
    return [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31,
            35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258]
}
func lengthExtra() -> [int] {
    return [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2,
            3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
}
func distBase() -> [int] {
    return [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
            257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
            8193, 12289, 16385, 24577]
}
func distExtra() -> [int] {
    return [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6,
            7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]
}

func fixedLiteralLengths() -> [int] {
    var l = [int](repeating: 8, count: 288)
    var i = 144
    while i < 256 { l[i] = 9; i += 1 }
    while i < 280 { l[i] = 7; i += 1 }
    return l
}

/// inflateZlib decodes a zlib stream. sizeHint, when known, is the
/// expected output size.
func inflateZlib(_ data: [uint8], sizeHint: int) throws -> [uint8] {
    if data.count < 6 { throw PngError.badData("zlib stream too short") }
    let cmf = int(data[0])
    let flg = int(data[1])
    if cmf & 0x0F != 8 || (cmf * 256 + flg) % 31 != 0 {
        throw PngError.badData("not a zlib deflate stream")
    }
    if flg & 0x20 != 0 { throw PngError.unsupported("zlib preset dictionary") }
    var out: [uint8] = []
    if sizeHint > 0 { out = [uint8](repeating: 0, count: sizeHint) }
    var n = 0
    var br = bitReader(data, at: 2)
    let lb = lengthBase()
    let le = lengthExtra()
    let db = distBase()
    let de = distExtra()
    let fixedLit = try huffman(fixedLiteralLengths())
    let fixedDist = try huffman([int](repeating: 5, count: 30))

    var final = false
    while !final {
        final = try br.take(1) == 1
        let type = try br.take(2)
        if type == 0 {
            br.alignToByte()
            if br.pos + 4 > data.count { throw PngError.badData("stored block header truncated") }
            let len = int(data[br.pos]) | (int(data[br.pos + 1]) << 8)
            let nlen = int(data[br.pos + 2]) | (int(data[br.pos + 3]) << 8)
            if len != (~nlen & 0xFFFF) { throw PngError.badData("stored block length check") }
            br.pos += 4
            if br.pos + len > data.count { throw PngError.badData("stored block truncated") }
            var i = 0
            while i < len {
                if n >= out.count { out.append(data[br.pos + i]) } else { out[n] = data[br.pos + i] }
                n += 1
                i += 1
            }
            br.pos += len
            continue
        }
        if type == 3 { throw PngError.badData("reserved deflate block type") }
        var lit = fixedLit
        var dist = fixedDist
        if type == 2 {
            let hlit = try br.take(5) + 257
            let hdist = try br.take(5) + 1
            let hclen = try br.take(4) + 4
            let order: [int] = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
            var clens = [int](repeating: 0, count: 19)
            var i = 0
            while i < hclen { clens[order[i]] = try br.take(3); i += 1 }
            let ch = try huffman(clens)
            var lengths = [int](repeating: 0, count: hlit + hdist)
            i = 0
            while i < hlit + hdist {
                let sym = try ch.decode(&br)
                if sym < 16 {
                    lengths[i] = sym
                    i += 1
                } else {
                    var rep = 0
                    var val = 0
                    if sym == 16 {
                        if i == 0 { throw PngError.badData("repeat with no previous length") }
                        val = lengths[i - 1]
                        rep = 3 + (try br.take(2))
                    } else if sym == 17 {
                        rep = 3 + (try br.take(3))
                    } else {
                        rep = 11 + (try br.take(7))
                    }
                    if i + rep > hlit + hdist { throw PngError.badData("code lengths overflow") }
                    while rep > 0 { lengths[i] = val; i += 1; rep -= 1 }
                }
            }
            var ll: [int] = []
            var dl: [int] = []
            i = 0
            while i < hlit { ll.append(lengths[i]); i += 1 }
            while i < hlit + hdist { dl.append(lengths[i]); i += 1 }
            lit = try huffman(ll)
            dist = try huffman(dl)
        }
        while true {
            let sym = try lit.decode(&br)
            if sym < 256 {
                if n >= out.count { out.append(uint8(sym)) } else { out[n] = uint8(sym) }
                n += 1
                continue
            }
            if sym == 256 { break }
            let li = sym - 257
            if li >= 29 { throw PngError.badData("bad length symbol") }
            let length = lb[li] + (try br.take(le[li]))
            let ds = try dist.decode(&br)
            if ds >= 30 { throw PngError.badData("bad distance symbol") }
            let d = db[ds] + (try br.take(de[ds]))
            if d > n { throw PngError.badData("distance before start of output") }
            var k = 0
            while k < length {
                let b = out[n - d]
                if n >= out.count { out.append(b) } else { out[n] = b }
                n += 1
                k += 1
            }
        }
    }
    if n < out.count {
        var trimmed = [uint8](repeating: 0, count: n)
        var i = 0
        while i < n { trimmed[i] = out[i]; i += 1 }
        return trimmed
    }
    return out
}

// --- deflate ---

struct bitWriter {
    var out: [uint8] = []
    var bits: uint32 = 0
    var count: int = 0

    init() {}

    mutating func put(_ v: int, _ n: int) {
        bits |= uint32(v) << uint32(count)
        count += n
        while count >= 8 {
            out.append(uint8(truncatingIfNeeded: bits))
            bits = bits >> 8
            count -= 8
        }
    }

    mutating func flush() {
        if count > 0 {
            out.append(uint8(truncatingIfNeeded: bits))
            bits = 0
            count = 0
        }
    }
}

// fixedCodes returns the reversed fixed-Huffman literal/length codes and
// their lengths, ready to write LSB first.
func fixedCodes() -> ([int], [int]) {
    var codes = [int](repeating: 0, count: 288)
    var lens = [int](repeating: 0, count: 288)
    var i = 0
    while i < 288 {
        var code = 0
        var len = 0
        if i < 144 { code = 0x30 + i; len = 8 }
        else if i < 256 { code = 0x190 + (i - 144); len = 9 }
        else if i < 280 { code = i - 256; len = 7 }
        else { code = 0xC0 + (i - 280); len = 8 }
        codes[i] = reverseBits(code, len)
        lens[i] = len
        i += 1
    }
    return (codes, lens)
}

/// deflateZlib compresses data into a zlib stream.
func deflateZlib(_ data: [uint8]) -> [uint8] {
    var w = bitWriter()
    w.out.append(0x78)
    w.out.append(0x9C)
    let (codes, lens) = fixedCodes()
    let lb = lengthBase()
    let le = lengthExtra()
    let db = distBase()
    let de = distExtra()
    // Symbol lookups for lengths 3...258 and distances 1...32768.
    var lengthSym = [int](repeating: 0, count: 259)
    var s = 0
    while s < 29 {
        var l = lb[s]
        let top = s == 28 ? 258 : lb[s] + (1 << le[s]) - 1
        while l <= top && l <= 258 { lengthSym[l] = s; l += 1 }
        s += 1
    }
    lengthSym[258] = 28

    let hashSize = 1 << 15
    let window = 32768
    let maxChain = 48
    var head = [int](repeating: -1, count: hashSize)
    var prev = [int](repeating: -1, count: window)

    // One fixed-Huffman block for the whole stream.
    w.put(1, 1)   // BFINAL
    w.put(1, 2)   // BTYPE = fixed
    let n = data.count
    var i = 0
    while i < n {
        var bestLen = 0
        var bestDist = 0
        if i + 2 < n {
            let h = ((int(data[i]) << 10) ^ (int(data[i + 1]) << 5) ^ int(data[i + 2])) & (hashSize - 1)
            var cand = head[h]
            var chain = 0
            let maxLen = n - i < 258 ? n - i : 258
            while cand >= 0 && i - cand <= window && chain < maxChain {
                if data[cand + bestLen] == data[i + bestLen] || bestLen == 0 {
                    var l = 0
                    while l < maxLen && data[cand + l] == data[i + l] { l += 1 }
                    if l > bestLen {
                        bestLen = l
                        bestDist = i - cand
                        if l == maxLen { break }
                    }
                }
                let next = prev[cand & (window - 1)]
                if next >= cand { break }
                cand = next
                chain += 1
            }
            prev[i & (window - 1)] = head[h]
            head[h] = i
        }
        if bestLen >= 3 {
            let ls = lengthSym[bestLen]
            w.put(codes[257 + ls], lens[257 + ls])
            if le[ls] > 0 { w.put(bestLen - lb[ls], le[ls]) }
            var ds = 0
            while ds < 29 && db[ds + 1] <= bestDist { ds += 1 }
            w.put(reverseBits(ds, 5), 5)
            if de[ds] > 0 { w.put(bestDist - db[ds], de[ds]) }
            // Hash the positions the match covers so later data can find them.
            var k = 1
            while k < bestLen {
                let p = i + k
                if p + 2 < n {
                    let h = ((int(data[p]) << 10) ^ (int(data[p + 1]) << 5) ^ int(data[p + 2])) & (hashSize - 1)
                    prev[p & (window - 1)] = head[h]
                    head[h] = p
                }
                k += 1
            }
            i += bestLen
        } else {
            let b = int(data[i])
            w.put(codes[b], lens[b])
            i += 1
        }
    }
    w.put(codes[256], lens[256])
    w.flush()
    let a = adler32(data)
    w.out.append(uint8(truncatingIfNeeded: a >> 24))
    w.out.append(uint8(truncatingIfNeeded: a >> 16))
    w.out.append(uint8(truncatingIfNeeded: a >> 8))
    w.out.append(uint8(truncatingIfNeeded: a))
    return w.out
}

func adler32(_ data: [uint8]) -> uint32 {
    var a: uint32 = 1
    var b: uint32 = 0
    var i = 0
    let n = data.count
    while i < n {
        // 5552 bytes is the most that can be summed before reducing.
        var end = i + 5552
        if end > n { end = n }
        while i < end {
            a += uint32(data[i])
            b += a
            i += 1
        }
        a = a % 65521
        b = b % 65521
    }
    return (b << 16) | a
}
