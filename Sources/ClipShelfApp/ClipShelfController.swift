import AppKit
import ClipShelfCore
import Combine
import Foundation

@MainActor
protocol OverlayPresenting: AnyObject {
    func show()
    func hide()
    func hideForPaste(completion: @escaping () -> Void)
}

struct PasteTargetContext {
    let app: NSRunningApplication?
    let bundleIdentifier: String?
    let wasFrontmostWhenOpened: Bool
    let capturedAt: Date

    var isFresh: Bool {
        Date().timeIntervalSince(capturedAt) < 60
    }
}

@MainActor
final class ClipShelfController: ObservableObject {
    let store: ClipboardStore
    let settingsStore: SettingsStore
    let watcher: ClipboardWatcher

    weak var overlayPresenter: OverlayPresenting?

    @Published var items: [ClipboardItem] = []
    @Published var pinboards: [Pinboard] = []
    @Published var selectedPinboardId: UUID?
    @Published var query = ""
    @Published var typeFilter: ClipboardTypeFilter = .all
    @Published var sourceFilter = ""
    @Published var selectedIndex = 0
    @Published var transientMessage: String?
    @Published var settings: AppSettings
    @Published var accessibilityTrusted = AccessibilityPermission.isTrusted
    @Published var localizationVersion = 0
    @Published var searchFocusRequest = 0
    @Published var overlayFocusResetRequest = 0

    private var pasteTargetContext: PasteTargetContext?

    var isPaused: Bool {
        get { watcher.isPaused }
        set { watcher.setPaused(newValue) }
    }

    init(store: ClipboardStore, settingsStore: SettingsStore, watcher: ClipboardWatcher) {
        self.store = store
        self.settingsStore = settingsStore
        self.watcher = watcher
        self.settings = settingsStore.load()
        reload()
    }

    func reload() {
        do {
            pinboards = try store.pinboards()
            items = try store.items(
                query: query,
                typeFilter: typeFilter,
                source: sourceFilter.isEmpty ? nil : sourceFilter,
                pinboardId: selectedPinboardId
            )
            selectedIndex = min(selectedIndex, max(items.count - 1, 0))
        } catch {
            showTransientMessage(error.localizedDescription)
        }
    }

    func showOverlay() {
        accessibilityTrusted = AccessibilityPermission.isTrusted
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            pasteTargetContext = PasteTargetContext(
                app: frontmost,
                bundleIdentifier: frontmost?.bundleIdentifier,
                wasFrontmostWhenOpened: frontmost?.isActive ?? false,
                capturedAt: Date()
            )
        }
        query = ""
        selectedIndex = 0
        searchFocusRequest = 0
        overlayFocusResetRequest += 1
        reload()
        overlayPresenter?.show()
    }

    func hideOverlay() {
        overlayPresenter?.hide()
    }

    func selectNext() {
        guard !items.isEmpty else { return }
        selectedIndex = min(selectedIndex + 1, items.count - 1)
    }

    func selectPrevious() {
        guard !items.isEmpty else { return }
        selectedIndex = max(selectedIndex - 1, 0)
    }

    func selectItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    func handleOverlayKeyEvent(_ event: NSEvent, isSearchFieldFocused: Bool) -> Bool {
        switch Int(event.keyCode) {
        case 36, 76:
            pasteSelected()
            return true
        case 123:
            selectPrevious()
            return true
        case 124:
            selectNext()
            return true
        case 51, 117:
            if !query.isEmpty {
                query.removeLast()
                if !isSearchFieldFocused {
                    searchFocusRequest += 1
                }
            } else if items.indices.contains(selectedIndex) {
                delete(items[selectedIndex])
            }
            return true
        case 53:
            if !query.isEmpty {
                query = ""
                searchFocusRequest = 0
                overlayFocusResetRequest += 1
                reload()
                return true
            }
            hideOverlay()
            return true
        default:
            break
        }

        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let character = event.charactersIgnoringModifiers?.first,
           let number = Int(String(character)),
           number >= 1,
           number <= 9 {
            let index = number - 1
            guard items.indices.contains(index) else {
                return true
            }
            selectedIndex = index
            paste(items[index])
            return true
        }

        guard !isSearchFieldFocused else {
            return false
        }

        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let characters = event.characters,
           characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !$0.properties.isWhitespace }) {
            query.append(contentsOf: characters)
            searchFocusRequest += 1
            return true
        }

        return false
    }

    func pasteSelected(asPlainText: Bool = false) {
        guard items.indices.contains(selectedIndex) else {
            return
        }
        paste(items[selectedIndex], asPlainText: asPlainText)
    }

    func paste(_ item: ClipboardItem, asPlainText: Bool = false) {
        do {
            let payloads = try store.payloads(for: item)
            let target = pasteTargetContext
            accessibilityTrusted = AccessibilityPermission.isTrusted
            if asPlainText {
                ClipboardWriter.writePlainText(item.previewText)
            } else {
                ClipboardWriter.write(payloads: payloads)
                watcher.markSelfWrite(payloads: payloads)
            }

            if settings.pasteMode == .direct && accessibilityTrusted {
                let performPaste = { [weak self] in
                    PasteExecutor.pasteIntoSavedTarget(target) { didPostPaste in
                        guard !didPostPaste else { return }
                        self?.showTransientMessage(L10n.text("toast.pasteFailed"))
                    }
                }
                if let overlayPresenter {
                    overlayPresenter.hideForPaste(completion: performPaste)
                } else {
                    hideOverlay()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(100))
                        performPaste()
                    }
                }
            } else if settings.pasteMode == .direct {
                let didOpenSettings = AccessibilityPermission.openSettingsFromPasteIfNeeded()
                let toastKey: String
                if !AccessibilityPermission.isRunningFromApplications {
                    toastKey = "toast.copiedManualWrongPath"
                } else if didOpenSettings {
                    toastKey = "toast.copiedManualFirstGuide"
                } else {
                    toastKey = "toast.copiedManualRestart"
                }
                showTransientMessage(
                    toastKey == "toast.copiedManualWrongPath"
                        ? L10n.format(toastKey, AccessibilityPermission.currentAppPath)
                        : L10n.text(toastKey)
                )
            } else {
                hideOverlay()
            }
        } catch {
            showTransientMessage(error.localizedDescription)
        }
    }

    func copyPlainText(_ item: ClipboardItem) {
        ClipboardWriter.writePlainText(item.previewText)
        showTransientMessage(L10n.text("toast.copiedPlain"))
    }

    func togglePin(_ item: ClipboardItem) {
        do {
            try store.togglePinned(itemId: item.id)
            reload()
        } catch {
            showTransientMessage(error.localizedDescription)
        }
    }

    func delete(_ item: ClipboardItem) {
        do {
            try store.delete(itemId: item.id)
            reload()
        } catch {
            showTransientMessage(error.localizedDescription)
        }
    }

    func saveEditedText(original: ClipboardItem, text: String) {
        let data = Data(text.utf8)
        let payload = ClipboardPayload(uti: NSPasteboard.PasteboardType.string.rawValue, data: data)
        let pending = PendingClipboardItem(
            item: ClipboardItem(
                sourceBundleId: Bundle.main.bundleIdentifier,
                sourceName: "ClipShelf",
                primaryType: ClipboardTypeFilter.text.rawValue,
                previewText: text,
                contentHash: Hashing.contentHash(payloads: [payload]),
                isPinned: original.isPinned
            ),
            payloads: [payload]
        )

        do {
            _ = try store.addCapturedItem(pending)
            reload()
        } catch {
            showTransientMessage(error.localizedDescription)
        }
    }

    func assignToFirstPinboard(_ item: ClipboardItem) {
        do {
            let board = try store.pinboards().first ?? store.addPinboard(Pinboard(name: L10n.text("overlay.pinboard"), color: "#53A2FF", sortOrder: 0))
            try store.assign(itemId: item.id, to: board.id)
            reload()
        } catch {
            showTransientMessage(error.localizedDescription)
        }
    }

    func addIgnoredApp(bundleId: String) {
        guard !settings.ignoredBundleIds.contains(bundleId) else {
            return
        }
        settings.ignoredBundleIds.append(bundleId)
        saveSettings()
    }

    func saveSettings() {
        AppLocalization.setLanguage(settings.language)
        settingsStore.save(settings)
        accessibilityTrusted = AccessibilityPermission.isTrusted
        localizationVersion += 1
        reload()
    }

    func showTransientMessage(_ message: String) {
        transientMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            if self?.transientMessage == message {
                self?.transientMessage = nil
            }
        }
    }
}
