//
//  ComposerPlusMenu.swift
//  MaloryComposer
//

import SwiftUI

enum ComposerPlusMenuDismissKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

extension EnvironmentValues {
    /// Closes the composer's `+` menu. `ComposerView` injects it into the
    /// menu panel; custom rows call it before performing their action.
    public var dismissComposerPlusMenu: @MainActor () -> Void {
        get { self[ComposerPlusMenuDismissKey.self] }
        set { self[ComposerPlusMenuDismissKey.self] = newValue }
    }
}

/// Icon-in-a-circle plus title, the row layout every `+` menu entry uses.
public struct ComposerPlusMenuRowLabel: View {
    let systemImage: String
    let title: String
    var isDestructive: Bool

    public init(systemImage: String, title: String, isDestructive: Bool = false) {
        self.systemImage = systemImage
        self.title = title
        self.isDestructive = isDestructive
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background {
                    Circle()
                        .fill(Color(.tertiarySystemFill))
                }

            Text(title)
                .font(.body.weight(.medium))
                .foregroundStyle(isDestructive ? Color.red : Color.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// A `+` menu row that closes the menu and then runs `action`.
/// Place inside `ComposerView`'s `menuExtras`.
public struct ComposerPlusMenuButton: View {
    let systemImage: String
    let title: String
    var role: ButtonRole?
    let action: () -> Void

    @Environment(\.dismissComposerPlusMenu) private var dismissComposerPlusMenu

    public init(systemImage: String, title: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.title = title
        self.role = role
        self.action = action
    }

    public var body: some View {
        Button(role: role) {
            dismissComposerPlusMenu()
            action()
        } label: {
            ComposerPlusMenuRowLabel(
                systemImage: systemImage,
                title: title,
                isDestructive: role == .destructive
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    VStack(spacing: 0) {
        ComposerPlusMenuButton(systemImage: "photo", title: "Photos") {}
        ComposerPlusMenuButton(systemImage: "gearshape", title: "Settings") {}
        ComposerPlusMenuButton(systemImage: "trash", title: "Clear", role: .destructive) {}
    }
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .padding()
}
