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

enum OverlayScrollDirection: Equatable {
    case initial
    case backward
    case forward
}

struct OverlaySelectionScrollRequest: Equatable {
    let itemID: UUID
    let index: Int
    let direction: OverlayScrollDirection
    let animated: Bool
    let sequence: Int
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
    @Published private(set) var selectionScrollRequest: OverlaySelectionScrollRequest?

    private var pasteTargetContext: PasteTargetContext?
    private var selectionScrollSequence = 0

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

    func reload(resetSelection: Bool = false, scrollToSelection: Bool = false) {
        do {
            pinboards = try store.pinboards()
            items = try store.items(
                query: query,
                typeFilter: typeFilter,
                source: sourceFilter.isEmpty ? nil : sourceFilter,
                pinboardId: selectedPinboardId
            )
            if resetSelection {
                selectedIndex = 0
            } else {
                selectedIndex = min(selectedIndex, max(items.count - 1, 0))
            }
            if scrollToSelection {
                requestSelectionScroll(direction: .initial, animated: false)
            }
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
        reload(resetSelection: true, scrollToSelection: true)
        overlayPresenter?.show()
    }

    func hideOverlay() {
        overlayPresenter?.hide()
    }

    func selectNext(isRepeat: Bool = false) {
        guard !items.isEmpty else { return }
        let nextIndex = min(selectedIndex + 1, items.count - 1)
        guard nextIndex != selectedIndex else { return }
        selectedIndex = nextIndex
        requestSelectionScroll(direction: .forward, animated: !isRepeat)
    }

    func selectPrevious(isRepeat: Bool = false) {
        guard !items.isEmpty else { return }
        let previousIndex = max(selectedIndex - 1, 0)
        guard previousIndex != selectedIndex else { return }
        selectedIndex = previousIndex
        requestSelectionScroll(direction: .backward, animated: !isRepeat)
    }

    func selectItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        selectedIndex = index
    }

    func updateQuery(_ newQuery: String, focusSearch: Bool = false) {
        guard query != newQuery else { return }
        query = newQuery
        reload(resetSelection: true, scrollToSelection: true)
        if focusSearch {
            searchFocusRequest += 1
        }
    }

    func updateTypeFilter(_ newFilter: ClipboardTypeFilter) {
        guard typeFilter != newFilter else { return }
        typeFilter = newFilter
        reload(resetSelection: true, scrollToSelection: true)
    }

    func requestSelectionScroll(direction: OverlayScrollDirection, animated: Bool) {
        guard items.indices.contains(selectedIndex) else { return }
        selectionScrollSequence += 1
        selectionScrollRequest = OverlaySelectionScrollRequest(
            itemID: items[selectedIndex].id,
            index: selectedIndex,
            direction: direction,
            animated: animated,
            sequence: selectionScrollSequence
        )
    }

    func handleOverlayKeyEvent(_ event: NSEvent, isSearchFieldFocused: Bool) -> Bool {
        switch Int(event.keyCode) {
        case 36, 76:
            pasteSelected()
            return true
        case 123:
            selectPrevious(isRepeat: event.isARepeat)
            return true
        case 124:
            selectNext(isRepeat: event.isARepeat)
            return true
        case 51, 117:
            if !query.isEmpty {
                updateQuery(String(query.dropLast()), focusSearch: !isSearchFieldFocused)
            } else if items.indices.contains(selectedIndex) {
                delete(items[selectedIndex])
            }
            return true
        case 53:
            if !query.isEmpty {
                updateQuery("")
                searchFocusRequest = 0
                overlayFocusResetRequest += 1
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
            requestSelectionScroll(direction: .initial, animated: false)
            paste(items[index])
            return true
        }

        guard !isSearchFieldFocused else {
            return false
        }

        if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           let characters = event.characters,
           characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) && !$0.properties.isWhitespace }) {
            updateQuery(query + characters, focusSearch: true)
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
                sourceName: "Superpaste",
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

    func saveSettings(refreshLocalization: Bool = false, reloadItems: Bool = false) {
        AppLocalization.setLanguage(settings.language)
        settingsStore.save(settings)
        accessibilityTrusted = AccessibilityPermission.isTrusted
        if refreshLocalization {
            localizationVersion += 1
        }
        if reloadItems {
            reload()
        }
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
