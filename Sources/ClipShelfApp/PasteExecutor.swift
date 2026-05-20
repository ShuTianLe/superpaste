import AppKit

enum PasteExecutor {
    static func pasteIntoSavedTarget(_ target: PasteTargetContext?, completion: @escaping (Bool) -> Void) {
        guard AXIsProcessTrusted() else {
            completion(false)
            return
        }

        if shouldRestoreTarget(target) {
            restoreTarget(target)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
            performCommandV()
            completion(true)
        }
    }

    static func performCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private static func shouldRestoreTarget(_ target: PasteTargetContext?) -> Bool {
        guard let target, target.isFresh, target.wasFrontmostWhenOpened else {
            return false
        }
        let currentBundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if currentBundleId == Bundle.main.bundleIdentifier {
            return true
        }
        guard let currentBundleId, let targetBundleId = target.bundleIdentifier else {
            return false
        }
        return currentBundleId != targetBundleId
    }

    private static func restoreTarget(_ target: PasteTargetContext?) {
        guard let target else { return }
        if let app = target.app, !app.isTerminated {
            app.activate()
        } else if let bundleIdentifier = target.bundleIdentifier,
                  let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            app.activate()
        }
    }
}

enum AccessibilityPermission {
    private static var lastSettingsOpenDate: Date?
    private static var didGuideDuringPaste = false

    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static var currentAppPath: String {
        Bundle.main.bundleURL.path
    }

    static var expectedApplicationsPath: String {
        "/Applications/ClipShelf.app"
    }

    static var isRunningFromApplications: Bool {
        let current = URL(fileURLWithPath: currentAppPath).standardizedFileURL.path
        let expected = URL(fileURLWithPath: expectedApplicationsPath).standardizedFileURL.path
        return current == expected
    }

    static var pathDiagnosticMessage: String {
        if isRunningFromApplications {
            return L10n.text("settings.accessibilityPathOk")
        }
        return L10n.format("settings.accessibilityPathWarning", currentAppPath, expectedApplicationsPath)
    }

    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func requestAndOpenSettings() {
        request()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            openSettings(force: true)
        }
    }

    static func openSettingsFromPasteIfNeeded() -> Bool {
        guard !didGuideDuringPaste else {
            return false
        }
        didGuideDuringPaste = true
        openSettings(force: true)
        return true
    }

    static func openSettings(force: Bool = false) {
        if !force,
           let lastSettingsOpenDate,
           Date().timeIntervalSince(lastSettingsOpenDate) < 8 {
            return
        }
        lastSettingsOpenDate = Date()

        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:"
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else {
                continue
            }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
