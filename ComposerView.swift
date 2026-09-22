//
//  ComposerView.swift
//  MaloryComposer
//

import PhotosUI
import SwiftUI

/// The Liquid Glass chat composer shared by Malory and AgentDeck: a growing
/// text field with dictation, an optional web-search toggle, an optional
/// `+` menu (Photos plus caller-supplied `ComposerPlusMenuButton` rows), and a
/// send button that turns into a stop button while a turn is running when the
/// caller provides `onStop`.
@available(iOS 26.0, macOS 26.0, *)
public struct ComposerView<MenuExtras: View>: View {
    @Binding var text: String
    @Binding var selectedPhoto: PhotosPickerItem?
    @FocusState.Binding var isFocused: Bool
    var isRecording: Bool
    var isSending: Bool
    var showsAttachments: Bool
    var showsWebSearch: Bool
    var webSearchEnabled: Bool
    var placeholder: String
    var errorMessage: String?
    var onSend: () -> Void
    var onStop: (() -> Void)?
    var onToggleSpeech: () -> Void
    var onToggleWebSearch: (() -> Void)?
    @ViewBuilder var menuExtras: () -> MenuExtras

    @State private var isPlusMenuExpanded = false
    @State private var sendPulse = 0

    private let controlHeight: CGFloat = 44
    private let menuCornerRadius: CGFloat = 24
    private let menuAnimation = Animation.easeOut(duration: 0.16)

    /// - Parameters:
    ///   - text: The draft. Speech input writes into it as well.
    ///   - selectedPhoto: Bound to the Photos picker row; pass `.constant(nil)`
    ///     when `showsAttachments` is false.
    ///   - isFocused: Focus state of the text field.
    ///   - isRecording: Whether dictation is active (drives the mic icon).
    ///   - isSending: Disables send while a turn is in flight. With `onStop`
    ///     set, the send button becomes a stop button instead.
    ///   - showsAttachments: Whether the `+` menu offers Photos.
    ///   - showsWebSearch: Whether the web-search globe is shown.
    ///   - webSearchEnabled: Current web-search state for the globe.
    ///   - placeholder: Text field placeholder.
    ///   - errorMessage: Shown above the field in red when non-nil.
    ///   - onSend: Called when the user sends; the caller reads `text`.
    ///   - onStop: Called from the stop button while `isSending`.
    ///   - onToggleSpeech: Start/stop dictation.
    ///   - onToggleWebSearch: Toggle web search; required for the globe to appear.
    ///   - menuExtras: Extra rows for the `+` menu, typically `ComposerPlusMenuButton`s.
    public init(
        text: Binding<String>,
        selectedPhoto: Binding<PhotosPickerItem?>,
        isFocused: FocusState<Bool>.Binding,
        isRecording: Bool,
        isSending: Bool = false,
        showsAttachments: Bool = true,
        showsWebSearch: Bool = false,
        webSearchEnabled: Bool = false,
        placeholder: String = "Message",
        errorMessage: String? = nil,
        onSend: @escaping () -> Void,
        onStop: (() -> Void)? = nil,
        onToggleSpeech: @escaping () -> Void,
        onToggleWebSearch: (() -> Void)? = nil,
        @ViewBuilder menuExtras: @escaping () -> MenuExtras
    ) {
        self._text = text
        self._selectedPhoto = selectedPhoto
        self._isFocused = isFocused
        self.isRecording = isRecording
        self.isSending = isSending
        self.showsAttachments = showsAttachments
        self.showsWebSearch = showsWebSearch
        self.webSearchEnabled = webSearchEnabled
        self.placeholder = placeholder
        self.errorMessage = errorMessage
        self.onSend = onSend
        self.onStop = onStop
        self.onToggleSpeech = onToggleSpeech
        self.onToggleWebSearch = onToggleWebSearch
        self.menuExtras = menuExtras
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private var showsStopButton: Bool {
        isSending && onStop != nil
    }

    private var showsPlusControl: Bool {
        showsAttachments || MenuExtras.self != EmptyView.self
    }

    public var body: some View {
        VStack(spacing: 8) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .bottom, spacing: 8) {
                if showsPlusControl {
                    plusControl
                }
                GlassEffectContainer(spacing: 8) {
                    HStack(alignment: .bottom, spacing: 8) {
                        messageField
                        if showsStopButton {
                            stopButton
                        } else {
                            sendButton
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // Hosts mount the composer over their scrolling content (`safeAreaInset`
        // in Malory), so make the whole padded bounds hit-testable. Otherwise
        // touches in the padding and the gaps between controls fall through to
        // the rows scrolled beneath the glass.
        .contentShape(Rectangle())
        .background {
            if isPlusMenuExpanded {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismissPlusMenu)
                    .padding(-2000)
                    .accessibilityHidden(true)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: sendPulse)
        .sensoryFeedback(.selection, trigger: isPlusMenuExpanded)
        .sensoryFeedback(.selection, trigger: isRecording)
        .sensoryFeedback(.selection, trigger: webSearchEnabled)
        .sensoryFeedback(.error, trigger: errorMessage) { _, newValue in
            newValue != nil
        }
        .onChange(of: isFocused) { _, focused in
            if focused {
                dismissPlusMenu()
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            if item != nil {
                dismissPlusMenu()
            }
        }
    }

    private var plusControl: some View {
        plusButton
            // Mount behind the button so the + hit target is never covered by the panel.
            .background(alignment: .bottomLeading) {
                plusMenuPanel
                    .opacity(isPlusMenuExpanded ? 1 : 0)
                    .scaleEffect(isPlusMenuExpanded ? 1 : 0.94, anchor: .bottomLeading)
                    .offset(y: -(controlHeight + 10))
                    .allowsHitTesting(isPlusMenuExpanded)
                    .accessibilityHidden(!isPlusMenuExpanded)
            }
            .zIndex(1)
    }

    private var plusButton: some View {
        Button {
            withAnimation(menuAnimation) {
                isPlusMenuExpanded.toggle()
            }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.semibold))
                .rotationEffect(.degrees(isPlusMenuExpanded ? 45 : 0))
                .frame(width: controlHeight, height: controlHeight)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular, in: .circle)
        .frame(width: controlHeight, height: controlHeight)
        .contentShape(Circle())
        .accessibilityLabel(isPlusMenuExpanded ? "Close menu" : "Open menu")
    }

    private var plusMenuPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsAttachments {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    ComposerPlusMenuRowLabel(systemImage: "photo", title: "Photos")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photos")
            }

            menuExtras()
        }
        .frame(minWidth: 220, alignment: .leading)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: .rect(cornerRadius: menuCornerRadius, style: .continuous))
        .environment(\.dismissComposerPlusMenu, dismissPlusMenu)
    }

    private var messageField: some View {
        HStack(alignment: .center, spacing: 8) {
            if showsWebSearch, let onToggleWebSearch {
                Button(action: onToggleWebSearch) {
                    Image(systemName: "globe")
                        .font(.body.weight(.medium))
                        .foregroundStyle(webSearchEnabled ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(webSearchEnabled ? "Disable web search" : "Enable web search")
                .accessibilityAddTraits(webSearchEnabled ? .isSelected : [])
            }

            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .lineLimit(1...6)

            Button(action: onToggleSpeech) {
                Image(systemName: isRecording ? "mic.fill" : "mic")
                    .font(.body.weight(.medium))
                    .foregroundStyle(isRecording ? .red : .primary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? "Stop speech input" : "Start speech input")
        }
        .padding(.leading, showsWebSearch ? 12 : 16)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(minHeight: controlHeight)
        .glassEffect(.regular, in: .rect(cornerRadius: controlHeight / 2, style: .continuous))
        .onSubmit(send)
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.glass)
        .frame(width: controlHeight, height: controlHeight)
        .disabled(!canSend)
        .keyboardShortcut(.return, modifiers: .command)
        .accessibilityLabel("Send")
    }

    private var stopButton: some View {
        Button {
            onStop?()
        } label: {
            Image(systemName: "stop.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.glass)
        .frame(width: controlHeight, height: controlHeight)
        .accessibilityLabel("Stop")
    }

    private func send() {
        guard canSend else { return }
        dismissPlusMenu()
        sendPulse += 1
        onSend()
    }

    private func dismissPlusMenu() {
        guard isPlusMenuExpanded else { return }
        withAnimation(menuAnimation) {
            isPlusMenuExpanded = false
        }
    }
}

@available(iOS 26.0, macOS 26.0, *)
extension ComposerView where MenuExtras == EmptyView {
    /// A composer without extra `+` menu rows. The `+` button still appears
    /// when `showsAttachments` is true.
    public init(
        text: Binding<String>,
        selectedPhoto: Binding<PhotosPickerItem?>,
        isFocused: FocusState<Bool>.Binding,
        isRecording: Bool,
        isSending: Bool = false,
        showsAttachments: Bool = true,
        showsWebSearch: Bool = false,
        webSearchEnabled: Bool = false,
        placeholder: String = "Message",
        errorMessage: String? = nil,
        onSend: @escaping () -> Void,
        onStop: (() -> Void)? = nil,
        onToggleSpeech: @escaping () -> Void,
        onToggleWebSearch: (() -> Void)? = nil
    ) {
        self.init(
            text: text,
            selectedPhoto: selectedPhoto,
            isFocused: isFocused,
            isRecording: isRecording,
            isSending: isSending,
            showsAttachments: showsAttachments,
            showsWebSearch: showsWebSearch,
            webSearchEnabled: webSearchEnabled,
            placeholder: placeholder,
            errorMessage: errorMessage,
            onSend: onSend,
            onStop: onStop,
            onToggleSpeech: onToggleSpeech,
            onToggleWebSearch: onToggleWebSearch,
            menuExtras: { EmptyView() }
        )
    }
}

@available(iOS 26.0, macOS 26.0, *)
#Preview {
    @Previewable @FocusState var isFocused: Bool

    ComposerView(
        text: .constant(
            """
            Liquid glass composer with enough lines
            to check vertical padding stays comfortable
            when the field grows past a single row.
            """
        ),
        selectedPhoto: .constant(nil),
        isFocused: $isFocused,
        isRecording: false,
        showsWebSearch: true,
        webSearchEnabled: true,
        errorMessage: nil,
        onSend: {},
        onToggleSpeech: {},
        onToggleWebSearch: {},
        menuExtras: {
            ComposerPlusMenuButton(systemImage: "gearshape", title: "Settings") {}
            ComposerPlusMenuButton(systemImage: "trash", title: "Clear", role: .destructive) {}
        }
    )
    .frame(maxHeight: .infinity, alignment: .bottom)
}
