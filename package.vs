// The 'image' package: still images. Pixel buffers and pure-Vertex codecs
// for picture formats, with no dependency on windows or screens.
import PackageDescription

let package = Package(
    name: "image",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "image", targets: ["image"]),
        .library(name: "image/png", targets: ["png"]),
        .library(name: "image/format", targets: ["format"]),
        .executable(name: "check-png", targets: ["check_png"]),
    ],
    targets: [
        // Pixel buffers: RGBA.
        .target(
            name: "image",
            path: "image"
        ),
        // PNG decode and encode, with the zlib/DEFLATE it needs.
        .target(
            name: "png",
            dependencies: ["image"],
            path: "png"
        ),
        // The platform's image decoders, as a C ABI.
        .target(
            name: "cimage",
            path: "format/cimage",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("CoreFoundation"),
                .linkedFramework("ImageIO"),
                .linkedFramework("CoreGraphics"),
            ]
        ),
        // Decode by sniffing: PNG in Vertex, other formats via cimage.
        .target(
            name: "format",
            dependencies: ["image", "png", "cimage"],
            path: "format",
            exclude: ["cimage"]
        ),
        // PNG checked against generated fixtures and round trips.
        .executableTarget(
            name: "check_png",
            dependencies: ["image", "png"],
            path: "tests/png",
            exclude: ["gen.py", "testdata"]
        ),
    ]
)
