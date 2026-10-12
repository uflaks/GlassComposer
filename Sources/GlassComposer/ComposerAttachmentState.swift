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
    /// Why the last pick could not become an attachment, or nil. Set it to
    /// nil to dismiss.
    public var failure: ComposerAttachmentFailure?
    public let policy: ComposerAttachmentPolicy

    /// `failure` as user-facing text.
    public var errorMessage: String? { failure?.errorDescription }

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
                failure = nil
            } else {
                attachment = nil
                failure = picked == nil ? .unavailable : .notAnImage
            }
        } catch {
            attachment = nil
            failure = .unavailable
        }
    }

    public func clear() {
        selectedPhoto = nil
        attachment = nil
        failure = nil
    }
}

/// Why a picked photo did not become an attachment.
public enum ComposerAttachmentFailure: Error, LocalizedError, Equatable, Sendable {
    /// Photos could not hand the item over (iCloud download failed, item
    /// removed, or the transfer threw).
    case unavailable
    /// The bytes arrived but ImageIO could not decode them as an image.
    case notAnImage

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return localized("Couldn't load that photo.")
        case .notAnImage:
            return localized("That file isn't an image the composer can send.")
        }
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
