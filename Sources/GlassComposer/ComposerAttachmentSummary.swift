//
//  ComposerAttachmentSummary.swift
//  GlassComposer
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A picked photo, already downscaled and JPEG-encoded under the owning
/// `ComposerAttachmentState`'s policy, so the composer only ever holds
/// upload-ready bytes.
public struct ComposerAttachmentSummary: Sendable, Equatable {
    public let filename: String
    public let imageData: Data

    public init(filename: String, imageData: Data) {
        self.filename = filename
        self.imageData = imageData
    }
}

/// What the Photos picker hands over before encoding: the original bytes and
/// a filename to derive the JPEG name from.
struct PickedImage: Transferable, Sendable {
    let filename: String
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PickedImage(filename: "photo", data: data)
        }
        ProxyRepresentation(importing: { (url: URL) in
            PickedImage(filename: url.deletingPathExtension().lastPathComponent, data: try Data(contentsOf: url))
        })
    }
}
