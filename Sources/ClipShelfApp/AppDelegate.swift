import AppKit
import ClipShelfCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ClipboardWatcherDelegate {
    private var statusItem: NSStatusItem!
    private var controller: ClipShelfController!
    private var overlayController: OverlayPanelController!
    private var hotKeyManager: HotKeyManager!
    private var settingsWindowController: NSWindowController?
    private var onboardingWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let settingsStore = SettingsStore()
            let store = try ClipboardStore()
            let watcher = ClipboardWatcher(store: store, settingsStore: settingsStore)
            controller = ClipShelfController(store: store, settingsStore: settingsStore, watcher: watcher)
            watcher.delegate = self
            watcher.start()

            overlayController = OverlayPanelController(controller: controller)
            controller.overlayPresenter = overlayController

            hotKeyManager = HotKeyManager { [weak self] in
                self?.controller.showOverlay()
            }
            try hotKeyManager.register(settingsStore.load().hotkey)

            setupStatusItem()
            showOnboardingIfNeeded()
        } catch {
            NSAlert(error: error).runModal()
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeyManager?.unregister()
    }

    func clipboardWatcher(_ watcher: ClipboardWatcher, didCapture item: ClipboardItem) {
        controller.reload()
    }

    func clipboardWatcher(_ watcher: ClipboardWatcher, didFail error: Error) {
        controller.showTransientMessage(error.localizedDescription)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = makeMenuBarImage()
        statusItem.button?.imagePosition = .imageOnly

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: L10n.text("menu.show"), action: #selector(showOverlay), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L10n.text("menu.pause"), action: #selector(togglePause), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.text("menu.settings"), action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: L10n.text("menu.diagnostics"), action: #selector(exportDiagnostics), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.text("menu.quit"), action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func makeMenuBarImage() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        NSColor.black.setStroke()

        let back = NSBezierPath(roundedRect: NSRect(x: 4.2, y: 4.2, width: 8.6, height: 10.2), xRadius: 2.0, yRadius: 2.0)
        back.lineWidth = 1.8
        back.stroke()

        let front = NSBezierPath(roundedRect: NSRect(x: 6.2, y: 2.9, width: 8.0, height: 10.0), xRadius: 1.9, yRadius: 1.9)
        front.fill()

        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 7.7, y: 8.8, width: 5.0, height: 1.1), xRadius: 0.55, yRadius: 0.55).fill()
        NSBezierPath(roundedRect: NSRect(x: 7.7, y: 6.4, width: 4.0, height: 1.1), xRadius: 0.55, yRadius: 0.55).fill()
        NSColor.black.setFill()
        NSBezierPath(roundedRect: NSRect(x: 7.7, y: 13.1, width: 4.9, height: 2.1), xRadius: 1.05, yRadius: 1.05).fill()

        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "ClipShelf"
        return image
    }

    @objc private func showOverlay() {
        controller.showOverlay()
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        controller.isPaused.toggle()
        sender.title = controller.isPaused ? L10n.text("menu.resume") : L10n.text("menu.pause")
    }

    @objc private func showSettings() {
        if settingsWindowController == nil {
            let view = SettingsView(controller: controller, onHotKeyChanged: { [weak self] settings in
                do {
                    try self?.hotKeyManager.register(settings.hotkey)
                } catch {
                    self?.controller.showTransientMessage(error.localizedDescription)
                }
            }, onLocalizationChanged: { [weak self] in
                self?.refreshLocalizedChrome()
            })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = L10n.text("settings.title")
            window.contentView = NSHostingView(rootView: view)
            window.center()
            settingsWindowController = NSWindowController(window: window)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
    }

    private func refreshLocalizedChrome() {
        settingsWindowController?.window?.title = L10n.text("settings.title")
        onboardingWindowController?.window?.title = L10n.text("onboarding.title")

        guard let menu = statusItem.menu else {
            return
        }
        menu.items[safe: 0]?.title = L10n.text("menu.show")
        menu.items[safe: 1]?.title = controller.isPaused ? L10n.text("menu.resume") : L10n.text("menu.pause")
        menu.items[safe: 3]?.title = L10n.text("menu.settings")
        menu.items[safe: 4]?.title = L10n.text("menu.diagnostics")
        menu.items[safe: 6]?.title = L10n.text("menu.quit")
    }

    @objc private func exportDiagnostics() {
        do {
            let summary = try controller.store.diagnosticsSummary()
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "ClipShelf Diagnostics.txt"
            panel.allowedContentTypes = [.plainText]
            panel.begin { response in
                guard response == .OK, let url = panel.url else {
                    return
                }
                try? summary.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            controller.showTransientMessage(error.localizedDescription)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func showOnboardingIfNeeded() {
        let key = "ClipShelf.HasShownOnboarding.v1"
        guard !UserDefaults.standard.bool(forKey: key) else {
            return
        }

        let view = OnboardingView(
            requestAccessibility: {
                AccessibilityPermission.requestAndOpenSettings()
            },
            finish: { [weak self] in
                UserDefaults.standard.set(true, forKey: key)
                self?.onboardingWindowController?.close()
                self?.onboardingWindowController = nil
            }
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("onboarding.title")
        window.contentView = NSHostingView(rootView: view)
        window.center()
        onboardingWindowController = NSWindowController(window: window)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindowController?.showWindow(nil)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
