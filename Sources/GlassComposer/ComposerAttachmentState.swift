//
//  ComposerAttachmentState.swift
//  GlassComposer
//

import Observation
import PhotosUI
import SwiftUI

/// Photo-picker load state for a composer: bind `selectedPhoto` to
/// `ComposerView` and read `imageData` when sending. A new selection loads
/// and encodes by itself under `policy`; `isLoading` is true meanwhile, so
/// disable send on it if the attachment matters.
@Observable
@MainActor
public final class ComposerAttachmentState {
    public var selectedPhoto: PhotosPickerItem? {
        didSet {
            guard selectedPhoto != oldValue else { return }
            Task { await loadSelectedPhoto() }
        }
    }
    public private(set) var attachment: ComposerAttachmentSummary?
    /// A pick is being transferred from Photos or encoded.
    public private(set) var isLoading = false
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

    /// Loads and encodes `selectedPhoto`. Runs automatically when the
    /// selection changes; calling it again for a pick that is already loading
    /// does nothing. A newer selection wins over a slower, older load.
    public func loadSelectedPhoto() async {
        guard let item = selectedPhoto else {
            attachment = nil
            failure = nil
            isLoading = false
            loadingItem = nil
            return
        }
        guard loadingItem != item else { return }
        loadingItem = item
        attachment = nil
        failure = nil
        isLoading = true
        defer {
            if selectedPhoto == item {
                isLoading = false
                loadingItem = nil
            }
        }
        do {
            let picked = try await item.loadTransferable(type: PickedImage.self)
            guard selectedPhoto == item else { return }
            let policy = self.policy
            let encoded = await Task.detached { picked.flatMap { policy.encode($0.data) } }.value
            guard selectedPhoto == item else { return }
            if let picked, let encoded {
                attachment = ComposerAttachmentSummary(filename: picked.filename + ".jpg", imageData: encoded)
            } else {
                failure = picked == nil ? .unavailable : .notAnImage
            }
        } catch {
            guard selectedPhoto == item else { return }
            failure = .unavailable
        }
    }

    private var loadingItem: PhotosPickerItem?

    public func clear() {
        selectedPhoto = nil
        attachment = nil
        failure = nil
        isLoading = false
        loadingItem = nil
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
