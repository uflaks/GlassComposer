//
//  ComposerToggle.swift
//  GlassComposer
//

import SwiftUI

/// An on/off control shown at the leading edge of the text field, such as a
/// web-search or "think longer" switch. The composer draws `systemImage`
/// tinted with the accent color while `isOn` and calls `action` on tap; the
/// host owns the state.
public struct ComposerToggle {
    public var systemImage: String
    public var isOn: Bool
    /// What the control is, for VoiceOver ("Web search"). The on/off state is
    /// reported separately.
    public var accessibilityLabel: String
    public var action: () -> Void

    public init(systemImage: String, isOn: Bool, accessibilityLabel: String, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.isOn = isOn
        self.accessibilityLabel = accessibilityLabel
        self.action = action
    }
}
