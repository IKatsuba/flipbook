import AppKit
import Combine
import SwiftUI

extension Composition {
    /// Opens a window that plays the composition at its frame rate, with a scrubber, and returns
    /// when the window is closed. Space plays and pauses; the arrow keys step a frame.
    ///
    /// This is for looking at a scene while writing it. It is ordinary on-screen SwiftUI driven by a
    /// timer, not the renderer: the pixels of `video` and `still` are the ones that count.
    public func preview(title: String = "Flipbook", startAt index: Int = 0, playing: Bool = true) {
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)

        let view = PreviewView(composition: self, index: min(max(index, 0), frames - 1), playing: playing)
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false
        )
        window.title = "\(title) · \(pixelWidth)×\(pixelHeight) · \(fps) fps"
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)

        let closed = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { NSApplication.shared.stop(nil) }
            // stop() takes effect after the next event; send one.
            let wake = NSEvent.otherEvent(
                with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                subtype: 0, data1: 0, data2: 0
            )
            if let wake { MainActor.assumeIsolated { NSApplication.shared.postEvent(wake, atStart: true) } }
        }
        application.run()
        NotificationCenter.default.removeObserver(closed)
    }
}

struct PreviewView<Content: View>: View {
    let composition: Composition<Content>
    @State var index: Int
    @State var playing: Bool
    @FocusState private var focused: Bool

    /// The composition scaled down to fit a laptop screen, never up.
    var fit: CGFloat {
        min(1, 1100 / CGFloat(composition.width), 680 / CGFloat(composition.height))
    }

    var body: some View {
        let frame = composition.frame(at: index)
        VStack(spacing: 0) {
            composition.content(frame)
                .frame(width: CGFloat(composition.width), height: CGFloat(composition.height))
                .clipped()
                .transaction { $0.disablesAnimations = true; $0.animation = nil }
                .scaleEffect(fit)
                .frame(width: CGFloat(composition.width) * fit, height: CGFloat(composition.height) * fit)
                .background(Color.black)

            HStack(spacing: 12) {
                Button(action: { playing.toggle() }) {
                    Image(systemName: playing ? "pause.fill" : "play.fill").frame(width: 16)
                }
                Slider(
                    value: Binding(get: { Double(index) }, set: { index = Int($0.rounded()); playing = false }),
                    in: 0...Double(max(composition.frames - 1, 1))
                )
                Text(String(format: "%d / %d · %.2f s", index, composition.frames - 1, frame.time))
                    .font(.system(size: 12, design: .monospaced))
                    .frame(width: 170, alignment: .trailing)
            }
            .padding(12)
        }
        .frame(minWidth: 420)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.space) { playing.toggle(); return .handled }
        .onKeyPress(.leftArrow) { step(-1); return .handled }
        .onKeyPress(.rightArrow) { step(1); return .handled }
        .onReceive(Timer.publish(every: 1 / Double(composition.fps), on: .main, in: .common).autoconnect()) { _ in
            if playing { index = (index + 1) % composition.frames }
        }
    }

    func step(_ by: Int) {
        playing = false
        index = min(max(index + by, 0), composition.frames - 1)
    }
}
