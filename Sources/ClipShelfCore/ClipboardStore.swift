import CryptoKit
import Foundation

public final class ClipboardStore {
    public let baseURL: URL
    private let database: SQLiteDatabase
    private let encryptedFiles: EncryptedFileStore

    public init(
        baseURL: URL = ClipboardStore.defaultBaseURL(),
        keyProvider: SymmetricKeyProviding = KeychainKeyStore()
    ) throws {
        self.baseURL = baseURL
        self.encryptedFiles = EncryptedFileStore(baseURL: baseURL, keyProvider: keyProvider)
        self.database = try SQLiteDatabase(url: baseURL.appendingPathComponent("clipshelf.sqlite"))
        try encryptedFiles.prepare()
        try migrate()
    }

    public static func defaultBaseURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("ClipShelf", isDirectory: true)
    }

    public func addCapturedItem(_ pending: PendingClipboardItem) throws -> ClipboardItem? {
        if try itemExists(contentHash: pending.item.contentHash) {
            return nil
        }

        try database.execute("BEGIN IMMEDIATE")
        do {
            try insertItem(pending.item)
            var blobs: [ClipboardBlob] = []

            for payload in pending.payloads {
                let encryptedPath = try encryptedFiles.write(payload.data)
                var thumbnailPath: String?
                var ocrText: String?
                if payload.isImagePayload {
                    if let thumbnail = LocalIntelligence.makePNGThumbnail(from: payload.data) {
                        thumbnailPath = try encryptedFiles.write(thumbnail, folder: "thumbs", extension: "png")
                    }
                    ocrText = LocalIntelligence.recognizeText(inImageData: payload.data)
                }

                let blob = ClipboardBlob(
                    itemId: pending.item.id,
                    uti: payload.uti,
                    size: payload.data.count,
                    sha256: Hashing.sha256Hex(payload.data),
                    encryptedPath: encryptedPath,
                    thumbnailPath: thumbnailPath,
                    ocrText: ocrText
                )
                try insertBlob(blob)
                blobs.append(blob)
            }

            try database.execute("COMMIT")
            var item = pending.item
            item.blobRefs = blobs
            return item
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    public func items(
        query: String = "",
        typeFilter: ClipboardTypeFilter = .all,
        source: String? = nil,
        pinboardId: UUID? = nil,
        limit: Int = 500
    ) throws -> [ClipboardItem] {
        let rows: [SQLiteDatabase.Row]
        if let pinboardId {
            rows = try database.query(
                """
                SELECT i.* FROM clipboard_items i
                JOIN pinboard_items p ON p.item_id = i.id
                WHERE p.pinboard_id = ?
                ORDER BY p.position ASC, i.created_at DESC
                LIMIT ?
                """,
                [.uuid(pinboardId), .int(Int64(limit))]
            )
        } else {
            rows = try database.query(
                """
                SELECT * FROM clipboard_items
                ORDER BY is_pinned DESC, created_at DESC
                LIMIT ?
                """,
                [.int(Int64(limit))]
            )
        }

        var result = try rows.map { try item(from: $0) }

        if typeFilter != .all {
            result = result.filter { $0.primaryType == typeFilter.rawValue }
        }
        if let source, !source.isEmpty {
            result = result.filter { ($0.sourceBundleId ?? "").contains(source) || ($0.sourceName ?? "").contains(source) }
        }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result = result.filter { LocalIntelligence.matches($0, query: query) }
        }
        return result
    }

    public func payloads(for item: ClipboardItem) throws -> [ClipboardPayload] {
        try blobs(for: item.id).map {
            ClipboardPayload(uti: $0.uti, data: try encryptedFiles.read(relativePath: $0.encryptedPath))
        }
    }

    public func thumbnailData(for blob: ClipboardBlob) throws -> Data? {
        guard let thumbnailPath = blob.thumbnailPath else {
            return nil
        }
        return try encryptedFiles.read(relativePath: thumbnailPath)
    }

    public func togglePinned(itemId: UUID) throws {
        try database.execute("BEGIN IMMEDIATE")
        do {
            let rows = try database.query("SELECT is_pinned FROM clipboard_items WHERE id = ?", [.uuid(itemId)])
            guard let current = rows.first?["is_pinned"]?.boolValue else {
                try database.execute("COMMIT")
                return
            }

            let pinned = !current
            let board = try defaultPinboard()
            try database.execute("UPDATE clipboard_items SET is_pinned = ? WHERE id = ?", [.bool(pinned), .uuid(itemId)])
            if pinned {
                try insertIntoDefaultPinned(itemId: itemId, pinboardId: board.id)
            } else {
                try removeFromDefaultPinned(itemId: itemId, pinboardId: board.id)
            }
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    public func delete(itemId: UUID) throws {
        let blobRows = try database.query("SELECT encrypted_path, thumbnail_path FROM clipboard_blobs WHERE item_id = ?", [.uuid(itemId)])
        for row in blobRows {
            encryptedFiles.delete(relativePath: row["encrypted_path"]?.stringValue)
            encryptedFiles.delete(relativePath: row["thumbnail_path"]?.stringValue)
        }
        try database.execute("DELETE FROM clipboard_items WHERE id = ?", [.uuid(itemId)])
    }

    public func pinboards() throws -> [Pinboard] {
        let board = try defaultPinboard()
        try repairDefaultPinnedMembership(pinboardId: board.id)
        let rows = try database.query("SELECT * FROM pinboards ORDER BY sort_order ASC, created_at ASC")
        return rows.compactMap(pinboard(from:))
    }

    @discardableResult
    public func addPinboard(_ pinboard: Pinboard) throws -> Pinboard {
        try database.execute(
            """
            INSERT OR IGNORE INTO pinboards (id, name, color, sort_order, created_at)
            VALUES (?, ?, ?, ?, ?)
            """,
            [
                .uuid(pinboard.id),
                .text(pinboard.name),
                .text(pinboard.color),
                .int(Int64(pinboard.sortOrder)),
                .date(pinboard.createdAt)
            ]
        )
        return pinboard
    }

    public func assign(itemId: UUID, to pinboardId: UUID) throws {
        let row = try database.query(
            "SELECT COALESCE(MAX(position), -1) + 1 AS next_position FROM pinboard_items WHERE pinboard_id = ?",
            [.uuid(pinboardId)]
        ).first
        let next = row?["next_position"]?.intValue ?? 0
        try database.execute(
            """
            INSERT OR REPLACE INTO pinboard_items (pinboard_id, item_id, position)
            VALUES (?, ?, ?)
            """,
            [.uuid(pinboardId), .uuid(itemId), .int(Int64(next))]
        )
        try database.execute("UPDATE clipboard_items SET is_pinned = 1 WHERE id = ?", [.uuid(itemId)])
    }

    public func remove(itemId: UUID, from pinboardId: UUID) throws {
        try database.execute(
            "DELETE FROM pinboard_items WHERE pinboard_id = ? AND item_id = ?",
            [.uuid(pinboardId), .uuid(itemId)]
        )
    }

    public func cleanup(retentionPolicy: RetentionPolicy, maxBytes: Int64? = nil) throws {
        if let interval = retentionPolicy.expirationInterval {
            let cutoff = Date().addingTimeInterval(-interval)
            let rows = try database.query(
                "SELECT id FROM clipboard_items WHERE created_at < ? AND is_pinned = 0",
                [.date(cutoff)]
            )
            for row in rows {
                guard let id = row["id"]?.stringValue.flatMap(UUID.init(uuidString:)) else {
                    continue
                }
                try delete(itemId: id)
            }
        }

        guard let maxBytes else {
            return
        }
        var total = try totalBlobBytes()
        guard total > maxBytes else {
            return
        }

        let rows = try database.query(
            "SELECT id FROM clipboard_items WHERE is_pinned = 0 ORDER BY created_at ASC"
        )
        for row in rows {
            guard total > maxBytes,
                  let id = row["id"]?.stringValue.flatMap(UUID.init(uuidString:))
            else {
                break
            }
            let size = try blobs(for: id).reduce(0) { $0 + Int64($1.size) }
            try delete(itemId: id)
            total -= size
        }
    }

    public func storageUsage() throws -> StorageUsage {
        let itemCount = try database.query("SELECT COUNT(*) AS count FROM clipboard_items").first?["count"]?.intValue ?? 0
        let blobCount = try database.query("SELECT COUNT(*) AS count FROM clipboard_blobs").first?["count"]?.intValue ?? 0
        let payloadBytes = try totalBlobBytes()
        let databaseBytes = fileSize(at: baseURL.appendingPathComponent("clipshelf.sqlite"))
            + fileSize(at: baseURL.appendingPathComponent("clipshelf.sqlite-wal"))
            + fileSize(at: baseURL.appendingPathComponent("clipshelf.sqlite-shm"))
        let attachmentBytes = directorySize(at: baseURL.appendingPathComponent("blobs", isDirectory: true))
            + directorySize(at: baseURL.appendingPathComponent("thumbs", isDirectory: true))

        return StorageUsage(
            itemCount: itemCount,
            blobCount: blobCount,
            payloadBytes: payloadBytes,
            databaseBytes: databaseBytes,
            attachmentBytes: attachmentBytes,
            totalBytes: databaseBytes + attachmentBytes,
            baseURL: baseURL
        )
    }

    public func deleteUnpinnedItems() throws {
        let rows = try database.query("SELECT id FROM clipboard_items WHERE is_pinned = 0")
        for row in rows {
            guard let id = row["id"]?.stringValue.flatMap(UUID.init(uuidString:)) else {
                continue
            }
            try delete(itemId: id)
        }
    }

    public func deleteAllItems() throws {
        let rows = try database.query("SELECT id FROM clipboard_items")
        for row in rows {
            guard let id = row["id"]?.stringValue.flatMap(UUID.init(uuidString:)) else {
                continue
            }
            try delete(itemId: id)
        }
        try database.execute("DELETE FROM pinboard_items")
    }

    public func diagnosticsSummary() throws -> String {
        let usage = try storageUsage()
        return """
        Superpaste diagnostics
        Items: \(usage.itemCount)
        Blobs: \(usage.blobCount)
        Payload bytes: \(usage.payloadBytes)
        Database bytes: \(usage.databaseBytes)
        Attachment bytes: \(usage.attachmentBytes)
        Total bytes: \(usage.totalBytes)
        Store: \(usage.baseURL.path)
        Network: disabled by design; no network frameworks or entitlements are used.
        """
    }

    private func migrate() throws {
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS clipboard_items (
              id TEXT PRIMARY KEY,
              created_at REAL NOT NULL,
              source_bundle_id TEXT,
              source_name TEXT,
              primary_type TEXT NOT NULL,
              preview_text TEXT NOT NULL,
              content_hash TEXT NOT NULL UNIQUE,
              is_pinned INTEGER NOT NULL DEFAULT 0,
              is_sensitive INTEGER NOT NULL DEFAULT 0
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS clipboard_blobs (
              id TEXT PRIMARY KEY,
              item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
              uti TEXT NOT NULL,
              size INTEGER NOT NULL,
              sha256 TEXT NOT NULL,
              encrypted_path TEXT NOT NULL,
              thumbnail_path TEXT,
              ocr_text TEXT
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS pinboards (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              color TEXT NOT NULL,
              sort_order INTEGER NOT NULL,
              created_at REAL NOT NULL
            )
            """
        )
        try database.execute(
            """
            CREATE TABLE IF NOT EXISTS pinboard_items (
              pinboard_id TEXT NOT NULL REFERENCES pinboards(id) ON DELETE CASCADE,
              item_id TEXT NOT NULL REFERENCES clipboard_items(id) ON DELETE CASCADE,
              position INTEGER NOT NULL,
              PRIMARY KEY (pinboard_id, item_id)
            )
            """
        )
        try database.execute("CREATE INDEX IF NOT EXISTS idx_clipboard_items_created_at ON clipboard_items(created_at DESC)")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_clipboard_items_hash ON clipboard_items(content_hash)")
        try database.execute("CREATE INDEX IF NOT EXISTS idx_clipboard_blobs_item ON clipboard_blobs(item_id)")
    }

    private func itemExists(contentHash: String) throws -> Bool {
        let rows = try database.query("SELECT id FROM clipboard_items WHERE content_hash = ? LIMIT 1", [.text(contentHash)])
        return !rows.isEmpty
    }

    private func defaultPinboard() throws -> Pinboard {
        if let row = try database.query("SELECT * FROM pinboards ORDER BY sort_order ASC, created_at ASC LIMIT 1").first,
           let pinboard = pinboard(from: row) {
            return pinboard
        }

        let inbox = Pinboard(
            name: AppLocalization.text("overlay.pinboard", value: "Pinned"),
            color: "#53A2FF",
            sortOrder: 0
        )
        return try addPinboard(inbox)
    }

    private func insertIntoDefaultPinned(itemId: UUID, pinboardId: UUID) throws {
        let row = try database.query(
            "SELECT COALESCE(MAX(position), -1) + 1 AS next_position FROM pinboard_items WHERE pinboard_id = ?",
            [.uuid(pinboardId)]
        ).first
        let next = row?["next_position"]?.intValue ?? 0
        try database.execute(
            """
            INSERT OR IGNORE INTO pinboard_items (pinboard_id, item_id, position)
            VALUES (?, ?, ?)
            """,
            [.uuid(pinboardId), .uuid(itemId), .int(Int64(next))]
        )
    }

    private func removeFromDefaultPinned(itemId: UUID, pinboardId: UUID) throws {
        try database.execute(
            "DELETE FROM pinboard_items WHERE pinboard_id = ? AND item_id = ?",
            [.uuid(pinboardId), .uuid(itemId)]
        )
    }

    private func repairDefaultPinnedMembership(pinboardId: UUID) throws {
        try database.execute(
            """
            DELETE FROM pinboard_items
            WHERE pinboard_id = ?
              AND item_id IN (SELECT id FROM clipboard_items WHERE is_pinned = 0)
            """,
            [.uuid(pinboardId)]
        )

        let rows = try database.query(
            """
            SELECT id FROM clipboard_items
            WHERE is_pinned = 1
              AND id NOT IN (SELECT item_id FROM pinboard_items WHERE pinboard_id = ?)
            ORDER BY created_at DESC
            """,
            [.uuid(pinboardId)]
        )
        for row in rows {
            guard let itemId = row["id"]?.stringValue.flatMap(UUID.init(uuidString:)) else {
                continue
            }
            try insertIntoDefaultPinned(itemId: itemId, pinboardId: pinboardId)
        }
    }

    private func insertItem(_ item: ClipboardItem) throws {
        try database.execute(
            """
            INSERT INTO clipboard_items
            (id, created_at, source_bundle_id, source_name, primary_type, preview_text, content_hash, is_pinned, is_sensitive)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .uuid(item.id),
                .date(item.createdAt),
                item.sourceBundleId.map(SQLiteDatabase.Value.text) ?? .null,
                item.sourceName.map(SQLiteDatabase.Value.text) ?? .null,
                .text(item.primaryType),
                .text(item.previewText),
                .text(item.contentHash),
                .bool(item.isPinned),
                .bool(item.isSensitive)
            ]
        )
    }

    private func insertBlob(_ blob: ClipboardBlob) throws {
        try database.execute(
            """
            INSERT INTO clipboard_blobs
            (id, item_id, uti, size, sha256, encrypted_path, thumbnail_path, ocr_text)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .uuid(blob.id),
                .uuid(blob.itemId),
                .text(blob.uti),
                .int(Int64(blob.size)),
                .text(blob.sha256),
                .text(blob.encryptedPath),
                blob.thumbnailPath.map(SQLiteDatabase.Value.text) ?? .null,
                blob.ocrText.map(SQLiteDatabase.Value.text) ?? .null
            ]
        )
    }

    private func item(from row: SQLiteDatabase.Row) throws -> ClipboardItem {
        guard let id = row["id"]?.stringValue.flatMap(UUID.init(uuidString:)) else {
            throw ClipShelfError.database("Missing clipboard item id")
        }
        return ClipboardItem(
            id: id,
            createdAt: row["created_at"]?.dateValue ?? Date(),
            sourceBundleId: row["source_bundle_id"]?.stringValue,
            sourceName: row["source_name"]?.stringValue,
            primaryType: row["primary_type"]?.stringValue ?? ClipboardTypeFilter.text.rawValue,
            previewText: row["preview_text"]?.stringValue ?? "",
            contentHash: row["content_hash"]?.stringValue ?? "",
            isPinned: row["is_pinned"]?.boolValue ?? false,
            isSensitive: row["is_sensitive"]?.boolValue ?? false,
            blobRefs: try blobs(for: id)
        )
    }

    private func pinboard(from row: SQLiteDatabase.Row) -> Pinboard? {
        guard let id = row["id"]?.stringValue.flatMap(UUID.init(uuidString:)),
              let name = row["name"]?.stringValue,
              let color = row["color"]?.stringValue
        else {
            return nil
        }
        return Pinboard(
            id: id,
            name: name,
            color: color,
            sortOrder: row["sort_order"]?.intValue ?? 0,
            createdAt: row["created_at"]?.dateValue ?? Date()
        )
    }

    private func blobs(for itemId: UUID) throws -> [ClipboardBlob] {
        let rows = try database.query(
            "SELECT * FROM clipboard_blobs WHERE item_id = ? ORDER BY rowid ASC",
            [.uuid(itemId)]
        )
        return rows.compactMap { row in
            guard let id = row["id"]?.stringValue.flatMap(UUID.init(uuidString:)) else {
                return nil
            }
            return ClipboardBlob(
                id: id,
                itemId: itemId,
                uti: row["uti"]?.stringValue ?? "",
                size: row["size"]?.intValue ?? 0,
                sha256: row["sha256"]?.stringValue ?? "",
                encryptedPath: row["encrypted_path"]?.stringValue ?? "",
                thumbnailPath: row["thumbnail_path"]?.stringValue,
                ocrText: row["ocr_text"]?.stringValue
            )
        }
    }

    private func totalBlobBytes() throws -> Int64 {
        let row = try database.query("SELECT COALESCE(SUM(size), 0) AS total FROM clipboard_blobs").first
        return Int64(row?["total"]?.intValue ?? 0)
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else {
            return 0
        }
        return size.int64Value
    }

    private func directorySize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard resourceValues?.isRegularFile == true else {
                continue
            }
            total += Int64(resourceValues?.fileSize ?? 0)
        }
        return total
    }
}
