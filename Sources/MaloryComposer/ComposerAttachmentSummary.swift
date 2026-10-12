//
//  ComposerAttachmentSummary.swift
//  MaloryComposer
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// A picked photo, already downscaled and JPEG-encoded by
/// `VisionImagePreparer` during transfer so the composer only ever holds
/// upload-ready bytes.
public struct ComposerAttachmentSummary: Transferable, Sendable {
    public let filename: String
    public let imageData: Data

    public init(filename: String, imageData: Data) {
        self.filename = filename
        self.imageData = imageData
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            guard let prepared = VisionImagePreparer.prepare(data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return ComposerAttachmentSummary(filename: "photo.jpg", imageData: prepared)
        }
        ProxyRepresentation(importing: { (url: URL) in
            let data = try Data(contentsOf: url)
            guard let prepared = VisionImagePreparer.prepare(data) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return ComposerAttachmentSummary(
                filename: url.deletingPathExtension().lastPathComponent + ".jpg",
                imageData: prepared
            )
        })
    }
}
