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

let tests: [(String, () throws -> Void)] = [
    ("hashing order stability", testHashingIsStableAcrossPayloadOrder),
    ("privacy concealed type skip", testPrivacySkipsDefaultConcealedTypes),
    ("privacy ignored bundle skip", testPrivacySkipsIgnoredBundleId),
    ("encrypted store round trip", testEncryptedStoreRoundTripsPayloadsAndDeduplicates),
    ("retention cleanup keeps pinned items", testRetentionCleanupKeepsPinnedItems)
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
