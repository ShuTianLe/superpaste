import AppKit
import SwiftUI

@MainActor
final class OverlayPanelController: NSObject, OverlayPresenting, NSWindowDelegate {
    private let controller: ClipShelfController
    private lazy var panel: NSPanel = makePanel()
    private weak var keyboardResponder: NSView?
    private enum PresentationState: Equatable {
        case hidden
        case presenting(Int)
        case visible
    }
    private var presentationState: PresentationState = .hidden
    private var presentationGeneration = 0

    init(controller: ClipShelfController) {
        self.controller = controller
        super.init()
    }

    func show() {
        presentationGeneration += 1
        let generation = presentationGeneration
        presentationState = .presenting(generation)
        positionPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        focusPanel()

        DispatchQueue.main.async { @MainActor [weak self] in
            guard let self,
                  self.presentationGeneration == generation,
                  self.panel.isVisible
            else {
                return
            }
            if !self.panel.isKeyWindow {
                self.panel.makeKey()
            }
            self.focusPanel()
            self.presentationState = .visible
        }
    }

    func hide() {
        guard presentationState != .hidden else {
            return
        }
        presentationGeneration += 1
        presentationState = .hidden
        if panel.isVisible {
            panel.orderOut(nil)
        }
    }

    func hideForPaste(completion: @escaping () -> Void) {
        hide()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            completion()
        }
    }

    private func makePanel() -> NSPanel {
        let height: CGFloat = 392
        let panel = KeyboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: height),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.keyHandler = { [weak panel, weak controller] event in
            controller?.handleOverlayKeyEvent(
                event,
                isSearchFieldFocused: panel?.firstResponder is NSTextView
            ) ?? false
        }
        panel.delegate = self
        let hostingView = KeyboardHostingView(rootView: OverlayView(controller: controller))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        keyboardResponder = hostingView
        panel.initialFirstResponder = hostingView
        panel.contentView = hostingView
        return panel
    }

    private func focusPanel() {
        guard let keyboardResponder,
              panel.firstResponder !== keyboardResponder
        else {
            return
        }
        panel.makeFirstResponder(keyboardResponder)
    }

    private func positionPanel() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }
        let visible = screen.visibleFrame
        let height: CGFloat = 392
        let frame = NSRect(
            x: visible.minX,
            y: visible.minY + 8,
            width: visible.width,
            height: height
        )
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        switch presentationState {
        case .hidden, .presenting:
            // A nonactivating panel can briefly report resign-key while AppKit
            // completes the key-window handoff. It must not dismiss itself
            // during that presentation window.
            return
        case .visible:
            hide()
        }
    }

    #if DEBUG
    var presentedPanel: NSPanel { panel }
    var presentedKeyboardResponder: NSView? { keyboardResponder }
    var isPresentationStable: Bool { presentationState == .visible }
    #endif
}

final class KeyboardPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, keyHandler?(event) == true {
            return
        }
        super.sendEvent(event)
    }

}

private final class KeyboardHostingView<Content: View>: NSHostingView<Content> {
    override var acceptsFirstResponder: Bool { true }
    override var needsPanelToBecomeKey: Bool { true }
}
