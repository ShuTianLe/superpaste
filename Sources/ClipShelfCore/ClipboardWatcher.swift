import AppKit
import Foundation

@MainActor
public protocol ClipboardWatcherDelegate: AnyObject {
    func clipboardWatcher(_ watcher: ClipboardWatcher, didCapture item: ClipboardItem)
    func clipboardWatcher(_ watcher: ClipboardWatcher, didFail error: Error)
}

@MainActor
public final class ClipboardWatcher {
    public weak var delegate: ClipboardWatcherDelegate?
    public private(set) var isPaused = false

    private let pasteboard: NSPasteboard
    private let store: ClipboardStore
    private let settingsStore: SettingsStore
    private let normalizer: ClipboardNormalizer
    private var timer: Timer?
    private var lastChangeCount: Int
    private var selfWriteHashes = Set<String>()

    public init(
        pasteboard: NSPasteboard = .general,
        store: ClipboardStore,
        settingsStore: SettingsStore = SettingsStore(),
        normalizer: ClipboardNormalizer = ClipboardNormalizer()
    ) {
        self.pasteboard = pasteboard
        self.store = store
        self.settingsStore = settingsStore
        self.normalizer = normalizer
        self.lastChangeCount = pasteboard.changeCount
    }

    public func start(interval: TimeInterval = 0.65) {
        stop()
        lastChangeCount = pasteboard.changeCount
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func setPaused(_ paused: Bool) {
        isPaused = paused
    }

    public func markSelfWrite(payloads: [ClipboardPayload]) {
        selfWriteHashes.insert(Hashing.contentHash(payloads: payloads))
    }

    public func tick() {
        guard pasteboard.changeCount != lastChangeCount else {
            return
        }
        lastChangeCount = pasteboard.changeCount
        guard !isPaused else {
            return
        }

        let settings = settingsStore.load()
        let source = NSWorkspace.shared.frontmostApplication
        let matcher = PrivacyRuleMatcher(settings: settings)

        guard let pending = normalizer.capture(
            from: pasteboard,
            sourceBundleId: source?.bundleIdentifier,
            sourceName: source?.localizedName,
            settings: settings,
            privacyMatcher: matcher
        ) else {
            return
        }

        if selfWriteHashes.remove(pending.item.contentHash) != nil {
            return
        }

        do {
            if let item = try store.addCapturedItem(pending) {
                delegate?.clipboardWatcher(self, didCapture: item)
            }
            try store.cleanup(retentionPolicy: settings.retentionPolicy)
        } catch {
            delegate?.clipboardWatcher(self, didFail: error)
        }
    }
}
