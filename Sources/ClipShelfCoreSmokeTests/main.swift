import ClipShelfCore
import CryptoKit
import Foundation

enum SmokeTestFailure: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw SmokeTestFailure.failed(message)
    }
}

func executeSQLite(databaseURL: URL, sql: String) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    process.arguments = [databaseURL.path, sql]
    try process.run()
    process.waitUntilExit()
    try expect(process.terminationStatus == 0, "sqlite3 command should succeed")
}

func testHashingIsStableAcrossPayloadOrder() throws {
    let first = ClipboardPayload(uti: "public.utf8-plain-text", data: Data("hello".utf8))
    let second = ClipboardPayload(uti: "public.url", data: Data("https://example.com".utf8))

    let hashA = Hashing.contentHash(payloads: [first, second])
    let hashB = Hashing.contentHash(payloads: [second, first])

    try expect(hashA == hashB, "content hashes should be stable across payload order")
}

func testPrivacySkipsDefaultConcealedTypes() throws {
    let matcher = PrivacyRuleMatcher(ignoredBundleIds: [], rules: PrivacyRuleMatcher.defaultRules)
    try expect(
        matcher.shouldSkip(
            sourceBundleId: nil,
            typeIdentifiers: ["org.nspasteboard.ConcealedType"],
            previewText: "secret"
        ),
        "concealed pasteboard types should be skipped"
    )
}

func testPrivacySkipsIgnoredBundleId() throws {
    let matcher = PrivacyRuleMatcher(ignoredBundleIds: ["com.example.Secret"], rules: [])
    try expect(
        matcher.shouldSkip(
            sourceBundleId: "com.example.Secret",
            typeIdentifiers: ["public.utf8-plain-text"],
            previewText: "private"
        ),
        "ignored bundle ids should be skipped"
    )
}

func testEncryptedStoreRoundTripsPayloadsAndDeduplicates() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipShelfTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let store = try ClipboardStore(baseURL: temp, keyProvider: StaticKeyStore(key: SymmetricKey(size: .bits256)))
    let payload = ClipboardPayload(uti: "public.utf8-plain-text", data: Data("hello world".utf8))
    let pending = PendingClipboardItem(
        item: ClipboardItem(
            sourceBundleId: "com.example.Source",
            sourceName: "Source",
            primaryType: ClipboardTypeFilter.text.rawValue,
            previewText: "hello world",
            contentHash: Hashing.contentHash(payloads: [payload])
        ),
        payloads: [payload]
    )

    guard let inserted = try store.addCapturedItem(pending) else {
        throw SmokeTestFailure.failed("first insert should create an item")
    }
    let duplicate = try store.addCapturedItem(pending)
    try expect(duplicate == nil, "duplicate insert should be skipped")

    let items = try store.items()
    try expect(items.count == 1, "store should contain one item")
    try expect(items.first?.id == inserted.id, "inserted item id should round trip")
    let roundTrippedPayloads = try store.payloads(for: inserted)
    try expect(roundTrippedPayloads == [payload], "payload should decrypt and round trip")
}

func testRetentionCleanupKeepsPinnedItems() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipShelfTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let store = try ClipboardStore(baseURL: temp, keyProvider: StaticKeyStore(key: SymmetricKey(size: .bits256)))

    let oldPayload = ClipboardPayload(uti: "public.utf8-plain-text", data: Data("old".utf8))
    var oldItem = ClipboardItem(
        createdAt: Date(timeIntervalSinceNow: -40 * 24 * 60 * 60),
        sourceBundleId: nil,
        sourceName: nil,
        primaryType: ClipboardTypeFilter.text.rawValue,
        previewText: "old",
        contentHash: Hashing.contentHash(payloads: [oldPayload])
    )
    oldItem.isPinned = true

    let newPayload = ClipboardPayload(uti: "public.utf8-plain-text", data: Data("new".utf8))
    let newItem = ClipboardItem(
        sourceBundleId: nil,
        sourceName: nil,
        primaryType: ClipboardTypeFilter.text.rawValue,
        previewText: "new",
        contentHash: Hashing.contentHash(payloads: [newPayload])
    )

    _ = try store.addCapturedItem(PendingClipboardItem(item: oldItem, payloads: [oldPayload]))
    _ = try store.addCapturedItem(PendingClipboardItem(item: newItem, payloads: [newPayload]))

    try store.cleanup(retentionPolicy: .days30)

    let previews = try store.items().map(\.previewText)
    try expect(previews.contains("old"), "pinned old item should survive retention cleanup")
    try expect(previews.contains("new"), "new item should survive retention cleanup")
}

func testRetentionCleanupSupportsHours() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipShelfTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let store = try ClipboardStore(baseURL: temp, keyProvider: StaticKeyStore(key: SymmetricKey(size: .bits256)))

    let oldPayload = ClipboardPayload(uti: "public.utf8-plain-text", data: Data("old hourly".utf8))
    let oldItem = ClipboardItem(
        createdAt: Date(timeIntervalSinceNow: -13 * 60 * 60),
        sourceBundleId: nil,
        sourceName: nil,
        primaryType: ClipboardTypeFilter.text.rawValue,
        previewText: "old hourly",
        contentHash: Hashing.contentHash(payloads: [oldPayload])
    )
    let newPayload = ClipboardPayload(uti: "public.utf8-plain-text", data: Data("new hourly".utf8))
    let newItem = ClipboardItem(
        createdAt: Date(timeIntervalSinceNow: -11 * 60 * 60),
        sourceBundleId: nil,
        sourceName: nil,
        primaryType: ClipboardTypeFilter.text.rawValue,
        previewText: "new hourly",
        contentHash: Hashing.contentHash(payloads: [newPayload])
    )

    _ = try store.addCapturedItem(PendingClipboardItem(item: oldItem, payloads: [oldPayload]))
    _ = try store.addCapturedItem(PendingClipboardItem(item: newItem, payloads: [newPayload]))

    try store.cleanup(retentionPolicy: .hours12)

    let previews = try store.items().map(\.previewText)
    try expect(!previews.contains("old hourly"), "12 hour cleanup should remove older unpinned items")
    try expect(previews.contains("new hourly"), "12 hour cleanup should keep newer items")
}

func testStorageUsageAndClearActions() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipShelfTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let store = try ClipboardStore(baseURL: temp, keyProvider: StaticKeyStore(key: SymmetricKey(size: .bits256)))
    let pinnedPayload = ClipboardPayload(uti: "public.utf8-plain-text", data: Data("pinned".utf8))
    var pinnedItem = ClipboardItem(
        sourceBundleId: nil,
        sourceName: nil,
        primaryType: ClipboardTypeFilter.text.rawValue,
        previewText: "pinned",
        contentHash: Hashing.contentHash(payloads: [pinnedPayload])
    )
    pinnedItem.isPinned = true

    let unpinnedPayload = ClipboardPayload(uti: "public.utf8-plain-text", data: Data("unpinned".utf8))
    let unpinnedItem = ClipboardItem(
        sourceBundleId: nil,
        sourceName: nil,
        primaryType: ClipboardTypeFilter.text.rawValue,
        previewText: "unpinned",
        contentHash: Hashing.contentHash(payloads: [unpinnedPayload])
    )

    _ = try store.addCapturedItem(PendingClipboardItem(item: pinnedItem, payloads: [pinnedPayload]))
    _ = try store.addCapturedItem(PendingClipboardItem(item: unpinnedItem, payloads: [unpinnedPayload]))

    let usage = try store.storageUsage()
    try expect(usage.itemCount == 2, "storage usage should count items")
    try expect(usage.blobCount == 2, "storage usage should count payloads")

    try store.deleteUnpinnedItems()
    var previews = try store.items().map(\.previewText)
    try expect(previews == ["pinned"], "deleteUnpinnedItems should preserve pinned items")

    try store.deleteAllItems()
    previews = try store.items().map(\.previewText)
    try expect(previews.isEmpty, "deleteAllItems should remove every history item")
}

func testTogglePinnedSyncsDefaultPinboard() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipShelfTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let store = try ClipboardStore(baseURL: temp, keyProvider: StaticKeyStore(key: SymmetricKey(size: .bits256)))
    let payload = ClipboardPayload(uti: "public.utf8-plain-text", data: Data("toggle pinned".utf8))
    let item = ClipboardItem(
        sourceBundleId: nil,
        sourceName: nil,
        primaryType: ClipboardTypeFilter.text.rawValue,
        previewText: "toggle pinned",
        contentHash: Hashing.contentHash(payloads: [payload])
    )

    guard let inserted = try store.addCapturedItem(PendingClipboardItem(item: item, payloads: [payload])) else {
        throw SmokeTestFailure.failed("insert should create an item")
    }

    let board = try store.pinboards().first
    guard let board else {
        throw SmokeTestFailure.failed("default pinboard should exist")
    }

    try store.togglePinned(itemId: inserted.id)
    var pinnedItems = try store.items(pinboardId: board.id)
    try expect(pinnedItems.map(\.id) == [inserted.id], "toggle pin should add item to default pinned board")
    try expect(pinnedItems.first?.isPinned == true, "pinned board item should be marked pinned")

    try store.togglePinned(itemId: inserted.id)
    pinnedItems = try store.items(pinboardId: board.id)
    try expect(pinnedItems.isEmpty, "toggle unpin should remove item from default pinned board")
    let recentItems = try store.items()
    try expect(recentItems.contains { $0.id == inserted.id }, "unpin should keep item in recent history")
}

func testPinboardRepairBackfillsPinnedItems() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipShelfTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let store = try ClipboardStore(baseURL: temp, keyProvider: StaticKeyStore(key: SymmetricKey(size: .bits256)))
    let payload = ClipboardPayload(uti: "public.utf8-plain-text", data: Data("legacy pinned".utf8))
    var item = ClipboardItem(
        sourceBundleId: nil,
        sourceName: nil,
        primaryType: ClipboardTypeFilter.text.rawValue,
        previewText: "legacy pinned",
        contentHash: Hashing.contentHash(payloads: [payload])
    )
    item.isPinned = true

    guard let inserted = try store.addCapturedItem(PendingClipboardItem(item: item, payloads: [payload])) else {
        throw SmokeTestFailure.failed("insert should create a legacy pinned item")
    }

    let board = try store.pinboards().first
    guard let board else {
        throw SmokeTestFailure.failed("default pinboard should exist")
    }

    let pinnedItems = try store.items(pinboardId: board.id)
    try expect(pinnedItems.map(\.id) == [inserted.id], "pinboard repair should backfill legacy pinned items")
}

func testPinboardRepairRemovesStaleUnpinnedMembership() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipShelfTests-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let store = try ClipboardStore(baseURL: temp, keyProvider: StaticKeyStore(key: SymmetricKey(size: .bits256)))
    let payload = ClipboardPayload(uti: "public.utf8-plain-text", data: Data("stale member".utf8))
    let item = ClipboardItem(
        sourceBundleId: nil,
        sourceName: nil,
        primaryType: ClipboardTypeFilter.text.rawValue,
        previewText: "stale member",
        contentHash: Hashing.contentHash(payloads: [payload])
    )

    guard let inserted = try store.addCapturedItem(PendingClipboardItem(item: item, payloads: [payload])) else {
        throw SmokeTestFailure.failed("insert should create an item")
    }
    guard let board = try store.pinboards().first else {
        throw SmokeTestFailure.failed("default pinboard should exist")
    }

    try executeSQLite(
        databaseURL: temp.appendingPathComponent("clipshelf.sqlite"),
        sql: """
        INSERT OR REPLACE INTO pinboard_items (pinboard_id, item_id, position)
        VALUES ('\(board.id.uuidString)', '\(inserted.id.uuidString)', 0);
        """
    )
    _ = try store.pinboards()

    let pinnedItems = try store.items(pinboardId: board.id)
    try expect(pinnedItems.isEmpty, "pinboard repair should remove stale unpinned memberships")
}

let tests: [(String, () throws -> Void)] = [
    ("hashing order stability", testHashingIsStableAcrossPayloadOrder),
    ("privacy concealed type skip", testPrivacySkipsDefaultConcealedTypes),
    ("privacy ignored bundle skip", testPrivacySkipsIgnoredBundleId),
    ("encrypted store round trip", testEncryptedStoreRoundTripsPayloadsAndDeduplicates),
    ("retention cleanup keeps pinned items", testRetentionCleanupKeepsPinnedItems),
    ("retention cleanup supports hours", testRetentionCleanupSupportsHours),
    ("storage usage and clear actions", testStorageUsageAndClearActions),
    ("toggle pinned syncs default pinboard", testTogglePinnedSyncsDefaultPinboard),
    ("pinboard repair backfills pinned items", testPinboardRepairBackfillsPinnedItems),
    ("pinboard repair removes stale unpinned membership", testPinboardRepairRemovesStaleUnpinnedMembership)
]

do {
    for (name, test) in tests {
        try test()
        print("PASS \(name)")
    }
    print("All ClipShelfCore smoke tests passed.")
} catch {
    fputs("FAIL \(error)\n", stderr)
    exit(1)
}
