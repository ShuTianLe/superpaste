import AppKit
import ClipShelfCore
import CryptoKit
import XCTest
@testable import ClipShelfApp

@MainActor
final class ClipShelfAppTests: XCTestCase {
    private var temporaryDirectories: [URL] = []
    private var defaultsSuites: [String] = []

    override func tearDown() {
        for url in temporaryDirectories {
            try? FileManager.default.removeItem(at: url)
        }
        for suite in defaultsSuites {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        temporaryDirectories.removeAll()
        defaultsSuites.removeAll()
        super.tearDown()
    }

    func testArrowNavigationCarriesDirectionAndRepeatState() throws {
        let controller = try makeController(items: ["one", "two", "three"])

        XCTAssertTrue(controller.handleOverlayKeyEvent(keyEvent(keyCode: 124), isSearchFieldFocused: false))
        XCTAssertEqual(controller.selectedIndex, 1)
        XCTAssertEqual(controller.selectionScrollRequest?.direction, .forward)
        XCTAssertEqual(controller.selectionScrollRequest?.animated, true)

        XCTAssertTrue(controller.handleOverlayKeyEvent(keyEvent(keyCode: 124, isRepeat: true), isSearchFieldFocused: false))
        XCTAssertEqual(controller.selectedIndex, 2)
        XCTAssertEqual(controller.selectionScrollRequest?.direction, .forward)
        XCTAssertEqual(controller.selectionScrollRequest?.animated, false)

        XCTAssertTrue(controller.handleOverlayKeyEvent(keyEvent(keyCode: 124, isRepeat: true), isSearchFieldFocused: false))
        XCTAssertEqual(controller.selectedIndex, 2, "selection must stop at the final item")

        XCTAssertTrue(controller.handleOverlayKeyEvent(keyEvent(keyCode: 123), isSearchFieldFocused: false))
        XCTAssertEqual(controller.selectedIndex, 1)
        XCTAssertEqual(controller.selectionScrollRequest?.direction, .backward)
    }

    func testArrowKeysWorkWhileSearchFieldIsFocused() throws {
        let controller = try makeController(items: ["one", "two"])

        XCTAssertTrue(controller.handleOverlayKeyEvent(keyEvent(keyCode: 124), isSearchFieldFocused: true))
        XCTAssertEqual(controller.selectedIndex, 1)
    }

    func testRapidNavigationAcrossTwentyItemsDoesNotQueueAnimatedScrolls() throws {
        let previews = (1...20).map { "item \($0)" }
        let controller = try makeController(items: previews)

        for _ in 0..<19 {
            XCTAssertTrue(controller.handleOverlayKeyEvent(keyEvent(keyCode: 124, isRepeat: true), isSearchFieldFocused: false))
        }

        XCTAssertEqual(controller.selectedIndex, 19)
        XCTAssertEqual(controller.selectionScrollRequest?.itemID, controller.items[19].id)
        XCTAssertEqual(controller.selectionScrollRequest?.animated, false)
    }

    func testTypingBackspaceAndEscapeUpdateSearchOncePerAction() throws {
        let controller = try makeController(items: ["apple", "banana"])

        XCTAssertTrue(controller.handleOverlayKeyEvent(keyEvent(keyCode: 11, characters: "b"), isSearchFieldFocused: false))
        XCTAssertEqual(controller.query, "b")
        XCTAssertEqual(controller.items.map(\.previewText), ["banana"])
        XCTAssertGreaterThan(controller.searchFocusRequest, 0)

        XCTAssertTrue(controller.handleOverlayKeyEvent(keyEvent(keyCode: 51, characters: "\u{8}"), isSearchFieldFocused: true))
        XCTAssertEqual(controller.query, "")
        XCTAssertEqual(controller.items.count, 2)

        controller.updateQuery("app")
        XCTAssertTrue(controller.handleOverlayKeyEvent(keyEvent(keyCode: 53, characters: "\u{1b}"), isSearchFieldFocused: true))
        XCTAssertEqual(controller.query, "")
        XCTAssertEqual(controller.items.count, 2)
        XCTAssertEqual(controller.searchFocusRequest, 0)
    }

    func testDeleteRemovesSelectedItemWhenSearchIsEmpty() throws {
        let controller = try makeController(items: ["one", "two"])

        controller.selectItem(at: 1)
        XCTAssertTrue(controller.handleOverlayKeyEvent(keyEvent(keyCode: 51, characters: "\u{8}"), isSearchFieldFocused: false))
        XCTAssertEqual(controller.items.map(\.previewText), ["one"])
    }

    func testEmptyListConsumesPasteShortcutsAndEscapeHidesPanel() throws {
        let controller = try makeController(items: [])
        let presenter = RecordingOverlayPresenter()
        controller.overlayPresenter = presenter

        XCTAssertTrue(controller.handleOverlayKeyEvent(keyEvent(keyCode: 36, characters: "\r"), isSearchFieldFocused: false))
        XCTAssertTrue(controller.handleOverlayKeyEvent(keyEvent(keyCode: 18, characters: "1"), isSearchFieldFocused: false))
        XCTAssertTrue(controller.handleOverlayKeyEvent(keyEvent(keyCode: 53, characters: "\u{1b}"), isSearchFieldFocused: false))
        XCTAssertEqual(presenter.hideCallCount, 1)
    }

    func testKeyboardPanelDispatchesHandledEventOnlyOnce() {
        let panel = KeyboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        var callCount = 0
        panel.keyHandler = { _ in
            callCount += 1
            return true
        }

        panel.sendEvent(keyEvent(keyCode: 124))

        XCTAssertEqual(callCount, 1)
    }

    func testPanelIsConfiguredForImmediateKeyboardInputOnShow() throws {
        let controller = try makeController(items: ["one", "two"])
        let presenter = OverlayPanelController(controller: controller)
        controller.overlayPresenter = presenter

        presenter.show()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        defer { presenter.hide() }

        XCTAssertTrue(presenter.presentedPanel.isVisible)
        XCTAssertTrue(presenter.presentedPanel.canBecomeKey)
        XCTAssertFalse(presenter.presentedPanel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(presenter.presentedPanel.firstResponder === presenter.presentedKeyboardResponder)

        presenter.presentedPanel.sendEvent(keyEvent(keyCode: 124))
        XCTAssertEqual(controller.selectedIndex, 1)
    }

    private func makeController(items previews: [String]) throws -> ClipShelfController {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipShelfAppTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)

        let suite = "ClipShelfAppTests.\(UUID().uuidString)"
        defaultsSuites.append(suite)
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw TestError.unableToCreateDefaults
        }
        let settingsStore = SettingsStore(defaults: defaults)
        let store = try ClipboardStore(
            baseURL: directory,
            keyProvider: StaticKeyStore(key: SymmetricKey(size: .bits256))
        )

        for preview in previews.reversed() {
            let payload = ClipboardPayload(uti: "public.utf8-plain-text", data: Data(preview.utf8))
            _ = try store.addCapturedItem(
                PendingClipboardItem(
                    item: ClipboardItem(
                        sourceBundleId: "io.clipshelf.tests",
                        sourceName: "Tests",
                        primaryType: ClipboardTypeFilter.text.rawValue,
                        previewText: preview,
                        contentHash: Hashing.contentHash(payloads: [payload])
                    ),
                    payloads: [payload]
                )
            )
        }

        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ClipShelfAppTests.\(UUID().uuidString)"))
        let watcher = ClipboardWatcher(pasteboard: pasteboard, store: store, settingsStore: settingsStore)
        return ClipShelfController(store: store, settingsStore: settingsStore, watcher: watcher)
    }

    private func keyEvent(
        keyCode: UInt16,
        characters: String = "",
        isRepeat: Bool = false
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isRepeat,
            keyCode: keyCode
        )!
    }
}

private enum TestError: Error {
    case unableToCreateDefaults
}

@MainActor
private final class RecordingOverlayPresenter: OverlayPresenting {
    private(set) var hideCallCount = 0

    func show() {}

    func hide() {
        hideCallCount += 1
    }

    func hideForPaste(completion: @escaping () -> Void) {
        completion()
    }
}
