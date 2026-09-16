import AppKit
import ClipShelfCore
import CryptoKit
import XCTest
import SwiftUI
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
        XCTAssertTrue(presenter.presentedPanel.isKeyWindow)
        XCTAssertTrue(presenter.presentedPanel.canBecomeKey)
        XCTAssertFalse(presenter.presentedPanel.canBecomeMain)
        XCTAssertFalse(presenter.presentedPanel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(presenter.presentedPanel.firstResponder === presenter.presentedKeyboardResponder)

        presenter.presentedPanel.sendEvent(keyEvent(keyCode: 124))
        XCTAssertEqual(controller.selectedIndex, 1)
    }

    func testPanelIgnoresTransientResignKeyDuringPresentationButDismissesAfterward() throws {
        let controller = try makeController(items: ["one", "two"])
        let presenter = OverlayPanelController(controller: controller)
        let resignNotification = Notification(name: NSWindow.didResignKeyNotification, object: presenter.presentedPanel)

        presenter.show()
        presenter.windowDidResignKey(resignNotification)
        XCTAssertTrue(presenter.presentedPanel.isVisible)

        let settleDeadline = Date(timeIntervalSinceNow: 2)
        while !presenter.isPresentationStable && Date() < settleDeadline {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        XCTAssertTrue(presenter.isPresentationStable)
        XCTAssertTrue(presenter.presentedPanel.isVisible)

        presenter.windowDidResignKey(resignNotification)
        XCTAssertFalse(presenter.presentedPanel.isVisible)
    }

    func testHoverTrackingIsRestoredWithoutChangingSelection() throws {
        let controller = try makeController(items: ["one", "two"])
        controller.selectItem(at: 0)

        let view = CardClickView(frame: NSRect(x: 0, y: 0, width: 214, height: 196))
        var hoverEvents: [Bool] = []
        view.onHoverChanged = { hoverEvents.append($0) }
        view.updateTrackingAreas()

        XCTAssertEqual(view.trackingAreas.count, 1)
        XCTAssertTrue(view.trackingAreas[0].options.contains(.mouseEnteredAndExited))
        XCTAssertTrue(view.trackingAreas[0].options.contains(.activeInKeyWindow))

        view.onHoverChanged?(true)
        view.onHoverChanged?(false)
        XCTAssertEqual(hoverEvents, [true, false])
        XCTAssertEqual(controller.selectedIndex, 0)

        let item = controller.items[0]
        let plainCard = ClipCard(index: 0, item: item, isSelected: true, isHovered: false, thumbnailState: .unavailable)
        let hoveredCard = ClipCard(index: 0, item: item, isSelected: true, isHovered: true, thumbnailState: .unavailable)
        XCTAssertNotEqual(plainCard, hoveredCard)
    }

    func testSelectionScrollOnlyMovesWhenCardLeavesVisibleBounds() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 220))
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1_400, height: 196))
        let view = HorizontalWheelScrollView()
        let itemID = UUID()

        let visibleRequest = OverlaySelectionScrollRequest(
            itemID: itemID,
            index: 0,
            direction: .forward,
            animated: false,
            sequence: 1
        )
        view.revealSelectionForTesting(visibleRequest, in: scrollView)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)

        let offscreenRequest = OverlaySelectionScrollRequest(
            itemID: itemID,
            index: 3,
            direction: .forward,
            animated: false,
            sequence: 2
        )
        view.revealSelectionForTesting(offscreenRequest, in: scrollView)
        let offsetAfterForward = scrollView.contentView.bounds.origin.x
        XCTAssertGreaterThan(offsetAfterForward, 0)

        let visibleBounds = scrollView.contentView.bounds
        let targetFrame = OverlayTimelineLayout.cardFrame(for: 3, visibleBounds: visibleBounds)
        XCTAssertGreaterThanOrEqual(targetFrame.minX, visibleBounds.minX + 15.5)
        XCTAssertLessThanOrEqual(targetFrame.maxX, visibleBounds.maxX - 15.5)

        let backwardRequest = OverlaySelectionScrollRequest(
            itemID: itemID,
            index: 0,
            direction: .backward,
            animated: false,
            sequence: 3
        )
        view.revealSelectionForTesting(backwardRequest, in: scrollView)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, 0, accuracy: 0.5)
    }

    func testThumbnailCompletionRefreshesRenderedCardDuringHover() throws {
        let controller = try makeController(items: [])
        let item = imageItem()
        var completions: [(NSImage?) -> Void] = []
        let cache = OverlayThumbnailCache { _, _, completion in completions.append(completion) }
        let host = NSHostingView(rootView: ThumbnailTestView(cache: cache, item: item))
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 220)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        cache.load(item: item, store: controller.store, presentation: 1)
        cache.load(item: item, store: controller.store, presentation: 1)
        XCTAssertEqual(completions.count, 1)
        pumpUI()
        let before = try renderedPixels(host)
        for hovering in [false, true, false, true] {
            host.rootView = ThumbnailTestView(cache: cache, item: item, hovering: hovering)
            pumpUI()
            XCTAssertEqual(cache.state(for: item), .loading)
        }
        let image = NSImage(size: NSSize(width: 100, height: 80), flipped: false) { rect in
            NSColor.systemRed.setFill()
            rect.fill()
            return true
        }
        completions[0](image)
        pumpUI()
        let after = try renderedPixels(host)
        XCTAssertNotEqual(before, after, "Published completion must update an equatable card without another input event")
        XCTAssertEqual(cache.state(for: item), .loaded(image))
        for hovering in [false, true, false] {
            host.rootView = ThumbnailTestView(cache: cache, item: item, hovering: hovering)
            pumpUI()
            XCTAssertEqual(cache.state(for: item), .loaded(image))
            XCTAssertGreaterThan(try redPixelCount(host), 1000, "Hover must retain the rendered image")
        }
        cache.load(item: item, store: controller.store, presentation: 2)
        XCTAssertEqual(completions.count, 1, "Reopening must retain successful thumbnails")
        let a = ClipCard(index: 0, item: item, isSelected: false, isHovered: true, thumbnailState: .loading)
        let b = ClipCard(index: 0, item: item, isSelected: false, isHovered: true, thumbnailState: .loaded(image))
        XCTAssertNotEqual(a, b)
    }

    func testThumbnailFailureRetriesOnReopenAndRejectsStaleResults() throws {
        let controller = try makeController(items: [])
        let item = imageItem()
        var completions: [(NSImage?) -> Void] = []
        let cache = OverlayThumbnailCache { _, _, completion in completions.append(completion) }
        cache.load(item: item, store: controller.store, presentation: 1)
        completions[0](nil)
        pumpUI()
        XCTAssertEqual(cache.state(for: item), .unavailable)
        cache.load(item: item, store: controller.store, presentation: 1)
        XCTAssertEqual(completions.count, 1)
        cache.load(item: item, store: controller.store, presentation: 2)
        XCTAssertEqual(completions.count, 2)
        cache.retain(items: [])
        cache.load(item: item, store: controller.store, presentation: 2)
        completions[1](NSImage(size: NSSize(width: 10, height: 10)))
        pumpUI()
        XCTAssertEqual(cache.state(for: item), .loading, "Old filtered-out request must not overwrite the new request")
        let image = NSImage(size: NSSize(width: 20, height: 20))
        completions[2](image)
        pumpUI()
        XCTAssertEqual(cache.state(for: item), .loaded(image))
    }

    func testTwentyThumbnailsRemainLoadedAcrossRepeatedAppearances() throws {
        let controller = try makeController(items: [])
        let items = (0..<22).map { _ in imageItem() }
        var completions: [(NSImage?) -> Void] = []
        let cache = OverlayThumbnailCache { _, _, completion in completions.append(completion) }
        for item in items { cache.load(item: item, store: controller.store, presentation: 1) }
        let image = NSImage(size: NSSize(width: 20, height: 20))
        for complete in completions.reversed() { complete(image) }
        pumpUI()
        cache.retain(items: items)
        for item in items.reversed() {
            cache.load(item: item, store: controller.store, presentation: 1)
            XCTAssertEqual(cache.state(for: item), .loaded(image))
        }
        XCTAssertEqual(completions.count, 22)
    }

    private func redPixelCount(_ view: NSView) throws -> Int {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: renderedPixels(view)))
        var count = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.redComponent > 0.7 && color.greenComponent < 0.5 && color.blueComponent < 0.5 { count += 1 }
            }
        }
        return count
    }

    private func imageItem() -> ClipboardItem {
        var item = ClipboardItem(sourceBundleId: "test", sourceName: "Fixture", primaryType: "image", previewText: "Image", contentHash: UUID().uuidString)
        item.blobRefs = [ClipboardBlob(itemId: item.id, uti: "public.png", size: 1,
                                      sha256: "fixture", encryptedPath: "fixture", thumbnailPath: "fixture.png")]
        return item
    }

    private func pumpUI() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    }

    private func renderedPixels(_ view: NSView) throws -> Data {
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
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

@MainActor
private struct ThumbnailTestView: View {
    @ObservedObject var cache: OverlayThumbnailCache
    let item: ClipboardItem
    var hovering = true
    var body: some View {
        ClipCard(index: 0, item: item, isSelected: false, isHovered: hovering,
                 thumbnailState: cache.state(for: item))
            .equatable()
            .transaction { $0.animation = nil }
    }
}
