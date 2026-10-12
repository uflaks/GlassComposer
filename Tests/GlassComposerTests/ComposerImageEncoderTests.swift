import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import GlassComposer

@Suite("Attachment image encoding")
struct ComposerImageEncoderTests {
    private let policy = ComposerAttachmentPolicy.default

    @Test("A large noisy photo is downscaled and fits the JPEG byte budget")
    func downscalesLargePhoto() throws {
        let png = try #require(Self.noisyPNG(width: 4032, height: 3024))

        let prepared = try #require(policy.encode(png))

        #expect(prepared.count <= policy.maxJPEGByteCount)
        let (width, height) = try #require(Self.pixelSize(of: prepared))
        #expect(max(width, height) <= Int(policy.maxPixelDimension))
        #expect(Self.utType(of: prepared) == .jpeg)
    }

    @Test("A small image is re-encoded as JPEG without upscaling")
    func keepsSmallImageSize() throws {
        let png = try #require(Self.noisyPNG(width: 320, height: 200))

        let prepared = try #require(policy.encode(png))

        let (width, height) = try #require(Self.pixelSize(of: prepared))
        #expect(width == 320)
        #expect(height == 200)
    }

    @Test("A custom policy caps the longest edge")
    func honoursCustomPolicy() throws {
        let png = try #require(Self.noisyPNG(width: 1200, height: 900))
        let small = ComposerAttachmentPolicy(maxPixelDimension: 300, maxJPEGByteCount: 750_000)

        let prepared = try #require(small.encode(png))

        let (width, height) = try #require(Self.pixelSize(of: prepared))
        #expect(width == 300)
        #expect(height == 225)
    }

    @Test("EXIF orientation is applied and dropped")
    func appliesOrientation() throws {
        let png = try #require(Self.noisyPNG(width: 800, height: 400))
        let rotated = try #require(Self.jpeg(from: png, orientation: 6))

        let prepared = try #require(policy.encode(rotated))

        let (width, height) = try #require(Self.pixelSize(of: prepared))
        #expect(width == 400)
        #expect(height == 800)
        #expect(Self.orientation(of: prepared) == nil)
    }

    @Test("The last-resort fallback never exceeds the policy's dimension")
    func fallbackHonoursDimension() throws {
        let png = try #require(Self.noisyPNG(width: 2000, height: 2000))
        // A budget no JPEG of noise can meet forces the fallback path.
        let strict = ComposerAttachmentPolicy(maxPixelDimension: 200, maxJPEGByteCount: 1)

        let prepared = try #require(strict.encode(png))

        let (width, height) = try #require(Self.pixelSize(of: prepared))
        #expect(max(width, height) <= 200)
    }

    @Test("Non-image bytes are rejected")
    func rejectsGarbage() {
        #expect(policy.encode(Data("not an image".utf8)) == nil)
        #expect(policy.encode(Data()) == nil)
    }

    // MARK: - Fixtures

    /// Random-pixel PNG so JPEG compression cannot shrink it trivially.
    private static func noisyPNG(width: Int, height: Int) -> Data? {
        var generator = SystemRandomNumberGenerator()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            pixels[index] = UInt8.random(in: 0...255, using: &generator)
            pixels[index + 1] = UInt8.random(in: 0...255, using: &generator)
            pixels[index + 2] = UInt8.random(in: 0...255, using: &generator)
            pixels[index + 3] = 255
        }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
        guard let context = pixels.withUnsafeMutableBytes({ buffer -> CGContext? in
            CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo.rawValue
            )
        }), let image = context.makeImage() else {
            return nil
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.png.identifier as CFString, 1, nil
        ) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Re-encodes PNG bytes as a JPEG carrying an EXIF orientation tag.
    private static func jpeg(from data: Data, orientation: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func orientation(of data: Data) -> Int? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        return properties[kCGImagePropertyOrientation] as? Int
    }

    private static func pixelSize(of data: Data) -> (Int, Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return (width, height)
    }

    private static func utType(of data: Data) -> UTType? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String? else {
            return nil
        }
        return UTType(identifier)
    }
}
