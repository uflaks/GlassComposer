//
//  ComposerAttachmentPolicy.swift
//  GlassComposer
//

import CoreGraphics
import Foundation

/// How a picked photo is normalized before the composer holds it. The
/// defaults suit chat backends that cap request bodies at a few megabytes;
/// raise them for hosts that keep full-resolution images.
public struct ComposerAttachmentPolicy: Sendable, Equatable {
    /// Longest edge after downscale, in pixels. Images are never upscaled.
    public var maxPixelDimension: CGFloat

    /// JPEG byte budget. Quality and size are stepped down until it fits.
    public var maxJPEGByteCount: Int

    public init(maxPixelDimension: CGFloat = 1536, maxJPEGByteCount: Int = 750_000) {
        self.maxPixelDimension = maxPixelDimension
        self.maxJPEGByteCount = maxJPEGByteCount
    }

    public static let `default` = ComposerAttachmentPolicy()

    /// Downscales and JPEG-encodes image bytes under this policy. Returns `nil`
    /// only when the data cannot be decoded as an image.
    public func encode(_ data: Data) -> Data? {
        ComposerImageEncoder.encode(data, policy: self)
    }
}
