//
//  VisionImagePreparer.swift
//  MaloryComposer
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downscales and JPEG-encodes photos before they enter a vision chat or
/// image-edit request.
///
/// Chat backends cap request bodies (NEAR AI rejects anything over 10 MiB with
/// `payload_too_large`). Vision attachments are base64-encoded into the
/// message, and E2EE then hex-encodes that plaintext (~2×), so an uncompressed
/// phone photo easily blows the budget. Built on ImageIO so it behaves the
/// same on iOS and macOS.
public nonisolated enum VisionImagePreparer {
    /// Longest edge after downscale — enough detail for VL models without a
    /// multi-megabyte E2EE wire field.
    public static let maxPixelDimension: CGFloat = 1536

    /// JPEG byte budget before base64 + E2EE hex expansion.
    /// Ciphertext hex ≈ 2 × (4/3 × jpegBytes); 750 KiB JPEG → ~2 MiB wire field.
    public static let maxJPEGByteCount = 750_000

    public static let prepareFailedMessage = "Couldn't prepare that photo for sending."

    /// Prepares picker/file bytes for upload. Returns `nil` only when the data
    /// cannot be decoded as an image.
    public static func prepare(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        var maxDimension = maxPixelDimension
        for _ in 0..<5 {
            guard let scaled = decode(source, maxDimension: maxDimension) else { return nil }
            if let jpeg = encodeJPEG(scaled, maxBytes: maxJPEGByteCount) {
                return jpeg
            }
            maxDimension *= 0.7
        }
        guard let fallback = decode(source, maxDimension: 1024) else { return nil }
        return jpegData(fallback, quality: 0.35)
    }

    /// Decodes the first frame at most `maxDimension` pixels on its longest
    /// edge, applying EXIF orientation. Never upscales.
    private static func decode(_ source: CGImageSource, maxDimension: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension.rounded(.down))
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func encodeJPEG(_ image: CGImage, maxBytes: Int) -> Data? {
        var quality: CGFloat = 0.85
        var best: Data?
        while quality >= 0.35 {
            guard let data = jpegData(image, quality: quality) else { break }
            best = data
            if data.count <= maxBytes {
                return data
            }
            quality -= 0.1
        }
        if let best, best.count <= maxBytes {
            return best
        }
        return nil
    }

    private static func jpegData(_ image: CGImage, quality: CGFloat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
