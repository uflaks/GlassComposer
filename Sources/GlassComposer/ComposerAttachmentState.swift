//
//  ComposerAttachmentState.swift
//  GlassComposer
//

import Observation
import PhotosUI
import SwiftUI

/// Photo-picker load state for a composer: bind `selectedPhoto` to
/// `ComposerView`, call `loadSelectedPhoto()` when it changes, and read
/// `imageData` when sending.
@Observable
@MainActor
public final class ComposerAttachmentState {
    public var selectedPhoto: PhotosPickerItem?
    public private(set) var attachment: ComposerAttachmentSummary?
    public var errorMessage: String?

    public init() {}

    /// The prepared JPEG bytes of the attached photo, if any.
    public var imageData: Data? { attachment?.imageData }

    public func loadSelectedPhoto() async {
        guard let selectedPhoto else {
            attachment = nil
            return
        }
        do {
            attachment = try await selectedPhoto.loadTransferable(
                type: ComposerAttachmentSummary.self
            )
            errorMessage = attachment == nil ? VisionImagePreparer.prepareFailedMessage : nil
        } catch {
            attachment = nil
            errorMessage = VisionImagePreparer.prepareFailedMessage
        }
    }

    public func clear() {
        selectedPhoto = nil
        attachment = nil
        errorMessage = nil
    }
}

/// The "paperclip filename" caption shown above the composer while a photo
/// is attached.
public struct ComposerAttachedFileLabel: View {
    let filename: String

    public init(filename: String) {
        self.filename = filename
    }

    public var body: some View {
        Label(filename, systemImage: "paperclip")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 4)
    }
}
