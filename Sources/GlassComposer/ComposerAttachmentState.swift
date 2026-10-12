//
//  ComposerAttachmentState.swift
//  GlassComposer
//

import Observation
import PhotosUI
import SwiftUI

/// Photo-picker load state for a composer: bind `selectedPhoto` to
/// `ComposerView`, call `loadSelectedPhoto()` when it changes, and read
/// `imageData` when sending. Photos are normalized under `policy` as they
/// load.
@Observable
@MainActor
public final class ComposerAttachmentState {
    public var selectedPhoto: PhotosPickerItem?
    public private(set) var attachment: ComposerAttachmentSummary?
    public var errorMessage: String?
    public let policy: ComposerAttachmentPolicy

    /// Shown in `errorMessage` when a picked photo cannot be loaded or encoded.
    public static let loadFailedMessage = "Couldn't prepare that photo for sending."

    public init(policy: ComposerAttachmentPolicy = .default) {
        self.policy = policy
    }

    /// The prepared JPEG bytes of the attached photo, if any.
    public var imageData: Data? { attachment?.imageData }

    public func loadSelectedPhoto() async {
        guard let selectedPhoto else {
            attachment = nil
            return
        }
        do {
            let picked = try await selectedPhoto.loadTransferable(type: PickedImage.self)
            let policy = self.policy
            let encoded = await Task.detached { picked.flatMap { policy.encode($0.data) } }.value
            if let picked, let encoded {
                attachment = ComposerAttachmentSummary(filename: picked.filename + ".jpg", imageData: encoded)
                errorMessage = nil
            } else {
                attachment = nil
                errorMessage = Self.loadFailedMessage
            }
        } catch {
            attachment = nil
            errorMessage = Self.loadFailedMessage
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
