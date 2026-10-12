//
//  ComposerAccessoryMenu.swift
//  MaloryComposer
//

import SwiftUI

/// A `Menu` styled like the composer's send button: a round Liquid Glass
/// control with one SF Symbol, for `ComposerView`'s `accessory` slot between
/// the text field and the send button. Put plain `Button`s (and `Divider`s)
/// in `content`; the host decides what picking one does, typically dropping a
/// prepared prompt into the draft.
@available(iOS 26.0, macOS 26.0, *)
public struct ComposerAccessoryMenu<Content: View>: View {
    let systemImage: String
    let accessibilityLabel: String
    @ViewBuilder let content: () -> Content

    /// - Parameters:
    ///   - systemImage: The SF Symbol shown on the button.
    ///   - accessibilityLabel: What the button is, for VoiceOver.
    ///   - content: The menu's rows.
    public init(
        systemImage: String,
        accessibilityLabel: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.content = content
    }

    public var body: some View {
        // Styled like the `+` button rather than with `.buttonStyle(.glass)`:
        // on macOS a `Menu` in the button style takes the standard control
        // size and shows a chevron, so it renders as a small rounded pill
        // next to the 44pt round send button. A plain-style label with its
        // own circular glass effect fills the frame the same way on both
        // platforms.
        Menu {
            content()
        } label: {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: ComposerMetrics.controlHeight, height: ComposerMetrics.controlHeight)
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .circle)
        .frame(width: ComposerMetrics.controlHeight, height: ComposerMetrics.controlHeight)
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
    }
}

@available(iOS 26.0, macOS 26.0, *)
#Preview {
    HStack(spacing: 8) {
        ComposerAccessoryMenu(systemImage: "bolt", accessibilityLabel: "Quick prompts") {
            Button("Commit", systemImage: "checkmark.circle") {}
            Button("Run tests", systemImage: "checkmark.seal") {}
            Divider()
            Button("Edit Quick Prompts…", systemImage: "pencil") {}
        }
        ComposerAccessoryMenu(systemImage: "slider.horizontal.3", accessibilityLabel: "Options") {
            Button("One") {}
            Button("Two") {}
        }
    }
    .padding()
}
