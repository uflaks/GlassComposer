#if canImport(UIKit)
import SwiftUI
import Testing
import UIKit
@testable import MaloryComposer

/// Hosts the composer the way Malory does (`safeAreaInset` over a List) in a
/// real window and hit-tests it with UIKit, so a regression where taps fall
/// through to the rows beneath fails here instead of in the consuming app.
@MainActor
@Suite("Composer hit testing")
struct ComposerHitTestingTests {
    @Test("Touches anywhere in the composer's bounds stay out of the list beneath")
    func composerAbsorbsTouches() async throws {
        guard #available(iOS 26.0, *) else { return }
        let host = try await ComposerHost.make()
        let frame = try #require(host.composerFrame)

        // Corners of the padding, the gap between the + button and the field,
        // the gap between the field and the accessory, the accessory itself,
        // and the gap between the accessory and the send button.
        let probes: [(String, CGPoint)] = [
            ("top-left padding", CGPoint(x: frame.minX + 4, y: frame.minY + 3)),
            ("bottom-right padding", CGPoint(x: frame.maxX - 4, y: frame.maxY - 3)),
            ("gap after +", CGPoint(x: frame.minX + 16 + 44 + 4, y: frame.midY)),
            ("gap before accessory", CGPoint(x: frame.maxX - 16 - 44 - 8 - 44 - 4, y: frame.midY)),
            ("accessory", CGPoint(x: frame.maxX - 16 - 44 - 8 - 22, y: frame.midY)),
            ("gap before send", CGPoint(x: frame.maxX - 16 - 44 - 4, y: frame.midY))
        ]
        for (name, point) in probes {
            let hit = host.window.hitTest(point, with: nil)
            #expect(hit != nil, "\(name): nothing hit")
            #expect(!host.isInsideList(hit), "\(name) at \(point) reached the list")
        }
    }
}

@available(iOS 26.0, *)
@MainActor
private struct ComposerHost {
    let window: UIWindow
    let controller: UIHostingController<AnyView>

    let frames: FrameBox

    static func make() async throws -> ComposerHost {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let frames = FrameBox()
        let controller = UIHostingController(rootView: AnyView(Harness(frames: frames)))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        // Let SwiftUI run its layout and safe-area passes.
        for _ in 0..<3 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(50))
        }
        window.layoutIfNeeded()
        return ComposerHost(window: window, controller: controller, frames: frames)
    }

    /// The composer's frame in window coordinates, as reported by the harness.
    var composerFrame: CGRect? { frames.composer }

    func isInsideList(_ view: UIView?) -> Bool {
        sequence(first: view, next: { $0?.superview }).contains { $0 is UICollectionView }
    }
}

@MainActor
private final class FrameBox {
    var composer: CGRect?
}

@available(iOS 26.0, *)
private struct Harness: View {
    let frames: FrameBox
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        List(0..<40, id: \.self) { row in
            Text("Row \(row)")
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ComposerView(
                text: $text,
                selectedPhoto: .constant(nil),
                isFocused: $isFocused,
                isRecording: false,
                onSend: {},
                onToggleSpeech: {},
                accessory: {
                    ComposerAccessoryMenu(systemImage: "bolt", accessibilityLabel: "Quick prompts") {
                        Button("Commit") {}
                    }
                }
            )
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frames.composer = $0 }
        }
    }
}
#endif
