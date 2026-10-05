import Foundation
import SQLite3

public enum SQLiteError: Error, CustomStringConvertible {
    case open(String), prepare(String), step(String)
    public var description: String {
        switch self { case .open(let m), .prepare(let m), .step(let m): return m }
    }
}

public enum SQLValue {
    case int(Int64), double(Double), text(String), blob(Data), null
    public static func opt(_ s: String?) -> SQLValue { s.map { .text($0) } ?? .null }
    public static func opt(_ d: Date?) -> SQLValue { d.map { .double($0.timeIntervalSince1970) } ?? .null }
    public static func opt(_ i: Int?) -> SQLValue { i.map { .int(Int64($0)) } ?? .null }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Minimal SQLite wrapper. Not thread-safe; callers serialise access (see ClipboardDatabase).
public final class SQLiteDatabase {
    private var db: OpaquePointer?

    public init(path: String) throws {
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            throw SQLiteError.open(String(cString: sqlite3_errmsg(db)))
        }
        if path != ":memory:" {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }
    deinit { sqlite3_close(db) }

    public func execute(_ sql: String, _ params: [SQLValue] = []) throws {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        let rc = sqlite3_step(stmt)
        if rc != SQLITE_DONE && rc != SQLITE_ROW { throw SQLiteError.step(message) }
    }

    public func query<T>(_ sql: String, _ params: [SQLValue] = [], map: (Row) -> T) throws -> [T] {
        let stmt = try prepare(sql, params)
        defer { sqlite3_finalize(stmt) }
        var out: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW { out.append(map(Row(stmt: stmt!))) }
            else if rc == SQLITE_DONE { break }
            else { throw SQLiteError.step(message) }
        }
        return out
    }

    public var changes: Int { Int(sqlite3_changes(db)) }

    public func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN")
        do { try body(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }

    private var message: String { String(cString: sqlite3_errmsg(db)) }

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw SQLiteError.prepare(message) }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case .blob(let v): _ = v.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(v.count), SQLITE_TRANSIENT) }
            case .null: sqlite3_bind_null(stmt, idx)
            }
        }
        return stmt
    }

    public struct Row {
        let stmt: OpaquePointer
        public func int(_ c: Int32) -> Int { Int(sqlite3_column_int64(stmt, c)) }
        public func double(_ c: Int32) -> Double { sqlite3_column_double(stmt, c) }
        public func text(_ c: Int32) -> String? {
            guard let p = sqlite3_column_text(stmt, c) else { return nil }
            return String(cString: p)
        }
        public func date(_ c: Int32) -> Date? {
            sqlite3_column_type(stmt, c) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: double(c))
        }
        public func blob(_ c: Int32) -> Data? {
            guard let p = sqlite3_column_blob(stmt, c) else { return nil }
            return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, c)))
        }
        public func optInt(_ c: Int32) -> Int? {
            sqlite3_column_type(stmt, c) == SQLITE_NULL ? nil : int(c)
        }
    }
}
