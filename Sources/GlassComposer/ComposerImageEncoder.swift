//
//  ComposerImageEncoder.swift
//  GlassComposer
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downscales and JPEG-encodes picked photos under a `ComposerAttachmentPolicy`.
/// Built on ImageIO so it behaves the same on iOS and macOS.
nonisolated enum ComposerImageEncoder {
    /// Returns `nil` only when the data cannot be decoded as an image.
    static func encode(_ data: Data, policy: ComposerAttachmentPolicy) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            return nil
        }

        var maxDimension = policy.maxPixelDimension
        for _ in 0..<5 {
            guard let scaled = decode(source, maxDimension: maxDimension) else { return nil }
            if let jpeg = encodeJPEG(scaled, maxBytes: policy.maxJPEGByteCount) {
                return jpeg
            }
            maxDimension *= 0.7
        }
        // Last resort: the smallest size the policy allows at low quality.
        // The byte budget is best effort from here; a tiny budget with a
        // large dimension can still come out over.
        guard let fallback = decode(source, maxDimension: min(1024, policy.maxPixelDimension)) else { return nil }
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
