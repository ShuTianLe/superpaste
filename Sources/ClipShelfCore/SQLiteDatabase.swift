import Foundation
import SQLite3

final class SQLiteDatabase {
    enum Value {
        case null
        case int(Int64)
        case double(Double)
        case text(String)
        case blob(Data)
        case bool(Bool)
        case uuid(UUID)
        case date(Date)
    }

    typealias Row = [String: Value]

    private let url: URL
    private var db: OpaquePointer?
    private let lock = NSRecursiveLock()

    init(url: URL) throws {
        self.url = url
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw ClipShelfError.database("Unable to open \(url.path)")
        }
        try execute("PRAGMA foreign_keys = ON")
        try execute("PRAGMA journal_mode = WAL")
    }

    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }

    func execute(_ sql: String, _ values: [Value] = []) throws {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ClipShelfError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)

        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw ClipShelfError.database(lastError)
        }
    }

    func query(_ sql: String, _ values: [Value] = []) throws -> [Row] {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw ClipShelfError.database(lastError)
        }
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)

        var rows: [Row] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                break
            }
            guard result == SQLITE_ROW else {
                throw ClipShelfError.database(lastError)
            }

            var row: Row = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                row[name] = columnValue(statement, index: index)
            }
            rows.append(row)
        }
        return rows
    }

    private func bind(_ values: [Value], to statement: OpaquePointer?) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .int(let int):
                result = sqlite3_bind_int64(statement, index, int)
            case .double(let double):
                result = sqlite3_bind_double(statement, index, double)
            case .text(let string):
                result = sqlite3_bind_text(statement, index, string, -1, sqliteTransient)
            case .blob(let data):
                result = data.withUnsafeBytes {
                    sqlite3_bind_blob(statement, index, $0.baseAddress, Int32(data.count), sqliteTransient)
                }
            case .bool(let bool):
                result = sqlite3_bind_int(statement, index, bool ? 1 : 0)
            case .uuid(let uuid):
                result = sqlite3_bind_text(statement, index, uuid.uuidString, -1, sqliteTransient)
            case .date(let date):
                result = sqlite3_bind_double(statement, index, date.timeIntervalSince1970)
            }

            guard result == SQLITE_OK else {
                throw ClipShelfError.database(lastError)
            }
        }
    }

    private func columnValue(_ statement: OpaquePointer?, index: Int32) -> Value {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .int(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .double(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let cString = sqlite3_column_text(statement, index) else {
                return .null
            }
            return .text(String(cString: cString))
        case SQLITE_BLOB:
            let bytes = sqlite3_column_blob(statement, index)
            let count = Int(sqlite3_column_bytes(statement, index))
            guard let bytes else {
                return .blob(Data())
            }
            return .blob(Data(bytes: bytes, count: count))
        default:
            return .null
        }
    }

    private var lastError: String {
        guard let message = sqlite3_errmsg(db) else {
            return "Unknown SQLite error"
        }
        return String(cString: message)
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension SQLiteDatabase.Value {
    var stringValue: String? {
        switch self {
        case .text(let value):
            return value
        case .uuid(let uuid):
            return uuid.uuidString
        default:
            return nil
        }
    }

    var boolValue: Bool {
        switch self {
        case .bool(let value):
            return value
        case .int(let value):
            return value != 0
        default:
            return false
        }
    }

    var intValue: Int {
        switch self {
        case .int(let value):
            return Int(value)
        default:
            return 0
        }
    }

    var dateValue: Date {
        switch self {
        case .date(let date):
            return date
        case .double(let value):
            return Date(timeIntervalSince1970: value)
        case .int(let value):
            return Date(timeIntervalSince1970: TimeInterval(value))
        default:
            return Date(timeIntervalSince1970: 0)
        }
    }
}
