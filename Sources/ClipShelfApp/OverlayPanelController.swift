import AppKit
import SwiftUI

@MainActor
final class OverlayPanelController: NSObject, OverlayPresenting, NSWindowDelegate {
    private let controller: ClipShelfController
    private lazy var panel: NSPanel = makePanel()

    init(controller: ClipShelfController) {
        self.controller = controller
        super.init()
    }

    func show() {
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.makeFirstResponder(panel.contentView)
    }

    func hide() {
        panel.orderOut(nil)
    }

    func hideForPaste(completion: @escaping () -> Void) {
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
        let hostingView = NSHostingView(rootView: OverlayView(controller: controller))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        return panel
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
        panel.setFrame(frame, display: true)
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }
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

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}
