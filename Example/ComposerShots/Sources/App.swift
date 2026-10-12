import GlassComposer
import PhotosUI
import SwiftUI

@main
struct ComposerShotsApp: App {
    var body: some Scene {
        WindowGroup { ShotScreen(shot: ProcessInfo.processInfo.environment["SHOT"] ?? "empty") }
    }
}

struct Message: Identifiable {
    let id = UUID()
    let mine: Bool
    let text: String
}

let script: [Message] = [
    Message(mine: true, text: "Can you summarise the last three commits on main?"),
    Message(mine: false, text: "Sure. The composer moved into its own package, AgentKit got a build fix after the AzureDevOpsKit move, and the Norwegian speech presets landed."),
    Message(mine: true, text: "Nice. Anything that still needs a tag?"),
    Message(mine: false, text: "GlassComposer 0.2.0 is tagged. The three apps already point at it."),
    Message(mine: true, text: "What does the composer need from the host app?"),
    Message(mine: false, text: "Two Info.plist keys: NSMicrophoneUsageDescription and NSSpeechRecognitionUsageDescription. Dictation runs on device through SpeechAnalyzer, and photos come in through PhotosPicker."),
    Message(mine: true, text: "And on the Mac?"),
    Message(mine: false, text: "Same API. A sandboxed Mac app also needs the Audio Input entitlement for dictation. The round controls use the same 44pt glass circles on both platforms."),
    Message(mine: true, text: "Does it grow with long drafts?"),
    Message(mine: false, text: "Yes, the field grows line by line up to a cap, and the send button turns into a stop button while a turn is running if you pass onStop."),
]

struct ShotScreen: View {
    let shot: String
    @State private var text = ""
    @State private var photo: PhotosPickerItem?
    @State private var webSearch = true
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List(script) { message in
                HStack {
                    if message.mine { Spacer(minLength: 48) }
                    Text(message.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(message.mine ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground), in: .rect(cornerRadius: 18))
                    if !message.mine { Spacer(minLength: 48) }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
            .listStyle(.plain)
            .defaultScrollAnchor(.bottom)
            .navigationTitle("Chat")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) { composer }
        }
        .onAppear {
            switch shot {
            case "typed", "accessory": text = "Draft a release note for 0.2.0 and keep it short."
            case "sending": text = ""
            default: break
            }
        }
    }

    @ViewBuilder private var composer: some View {
        switch shot {
        case "sending":
            ComposerView(
                text: $text, selectedPhoto: $photo, isFocused: $focused,
                isRecording: false, isSending: true, showsAttachments: true,
                placeholder: "Message",
                onSend: {}, onStop: {}, onToggleSpeech: {},
                menuExtras: { extras }
            )
        case "accessory":
            ComposerView(
                text: $text, selectedPhoto: $photo, isFocused: $focused,
                isRecording: false, showsAttachments: false,
                placeholder: "Prompt",
                onSend: {}, onToggleSpeech: {},
                accessory: {
                    ComposerAccessoryMenu(systemImage: "sparkles", accessibilityLabel: "Quick prompts") {
                        Button("Explain this file") {}
                        Button("Write tests") {}
                        Button("Review the diff") {}
                    }
                }
            )
        case "recording":
            ComposerView(
                text: $text, selectedPhoto: $photo, isFocused: $focused,
                isRecording: true, showsAttachments: true,
                placeholder: "Listening…",
                onSend: {}, onToggleSpeech: {},
                menuExtras: { extras }
            )
        case "error":
            ComposerView(
                text: $text, selectedPhoto: $photo, isFocused: $focused,
                isRecording: false, showsAttachments: true,
                errorMessage: "Speech recognition is not available for this language.",
                onSend: {}, onToggleSpeech: {},
                menuExtras: { extras }
            )
        default:
            ComposerView(
                text: $text, selectedPhoto: $photo, isFocused: $focused,
                isRecording: false, showsAttachments: true,
                leadingToggle: ComposerToggle(systemImage: "globe", isOn: webSearch, accessibilityLabel: "Web search") {
                    webSearch.toggle()
                },
                onSend: {}, onToggleSpeech: {},
                menuExtras: { extras }
            )
        }
    }

    @ViewBuilder private var extras: some View {
        ComposerPlusMenuButton(systemImage: "doc", title: "Attach file") {}
        ComposerPlusMenuButton(systemImage: "camera", title: "Take photo") {}
    }
}
