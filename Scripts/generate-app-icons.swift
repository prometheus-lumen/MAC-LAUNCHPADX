#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: generate-app-icons.swift <source.png> <AppIcon.appiconset>\n", stderr)
    exit(64)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)

guard
    let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
    let sourceImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fputs("Unable to read \(sourceURL.path)\n", stderr)
    exit(65)
}

guard sourceImage.width == sourceImage.height else {
    fputs("The source icon must be square.\n", stderr)
    exit(65)
}

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
    | CGImageAlphaInfo.premultipliedLast.rawValue
var sourcePixels = [UInt8](repeating: 0, count: sourceImage.width * sourceImage.height * 4)

guard let sourceContext = CGContext(
    data: &sourcePixels,
    width: sourceImage.width,
    height: sourceImage.height,
    bitsPerComponent: 8,
    bytesPerRow: sourceImage.width * 4,
    space: colorSpace,
    bitmapInfo: bitmapInfo
) else {
    fputs("Unable to create the source bitmap.\n", stderr)
    exit(70)
}

sourceContext.draw(
    sourceImage,
    in: CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height)
)

// The supplied artwork is flattened over black. Reconstruct transparency by
// treating its RGB values as premultiplied color and deriving alpha from the
// brightest channel. This keeps the original artwork and soft edge shadows.
for offset in stride(from: 0, to: sourcePixels.count, by: 4) {
    sourcePixels[offset + 3] = max(
        sourcePixels[offset],
        sourcePixels[offset + 1],
        sourcePixels[offset + 2]
    )
}

guard let transparentImage = sourceContext.makeImage() else {
    fputs("Unable to create the transparent icon.\n", stderr)
    exit(70)
}

let outputs: [(String, Int)] = [
    ("AppIcon-16.png", 16),
    ("AppIcon-16@2x.png", 32),
    ("AppIcon-32.png", 32),
    ("AppIcon-32@2x.png", 64),
    ("AppIcon-128.png", 128),
    ("AppIcon-128@2x.png", 256),
    ("AppIcon-256.png", 256),
    ("AppIcon-256@2x.png", 512),
    ("AppIcon-512.png", 512),
    ("AppIcon-512@2x.png", 1024),
]

try FileManager.default.createDirectory(
    at: outputDirectory,
    withIntermediateDirectories: true
)

for (filename, size) in outputs {
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        fputs("Unable to create \(filename).\n", stderr)
        exit(70)
    }

    context.interpolationQuality = .high
    context.draw(
        transparentImage,
        in: CGRect(x: 0, y: 0, width: size, height: size)
    )

    guard
        let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(
            outputDirectory.appendingPathComponent(filename) as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        fputs("Unable to prepare \(filename).\n", stderr)
        exit(70)
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        fputs("Unable to write \(filename).\n", stderr)
        exit(74)
    }
}

print("Generated \(outputs.count) icon renditions in \(outputDirectory.path)")
