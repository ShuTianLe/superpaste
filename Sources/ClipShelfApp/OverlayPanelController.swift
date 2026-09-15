import AppKit
import SwiftUI

@MainActor
final class OverlayPanelController: NSObject, OverlayPresenting, NSWindowDelegate {
    private let controller: ClipShelfController
    private lazy var panel: NSPanel = makePanel()
    private weak var keyboardResponder: NSView?
    private var previouslyActiveApplication: NSRunningApplication?

    init(controller: ClipShelfController) {
        self.controller = controller
        super.init()
    }

    func show() {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        if frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previouslyActiveApplication = frontmostApplication
        }
        positionPanel()
        panel.orderFrontRegardless()
        NSApp.activate()
        panel.makeKey()
        focusPanel()

        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, panel.isVisible else { return }
            if !panel.isKeyWindow {
                panel.makeKey()
            }
            focusPanel()
        }
    }

    func hide() {
        panel.orderOut(nil)
        restorePreviousApplication()
    }

    func hideForPaste(completion: @escaping () -> Void) {
        previouslyActiveApplication = nil
        panel.orderOut(nil)
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

    private func restorePreviousApplication() {
        let application = previouslyActiveApplication
        previouslyActiveApplication = nil
        application?.activate()
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
        hide()
    }

    #if DEBUG
    var presentedPanel: NSPanel { panel }
    var presentedKeyboardResponder: NSView? { keyboardResponder }
    #endif
}

final class KeyboardPanel: NSPanel {
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

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
