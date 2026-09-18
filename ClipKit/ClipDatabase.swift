//
//  ClipDatabase.swift
//  ClipKit
//
//  v2.0：SQLite 持久化层（libsqlite3 直连，无第三方依赖）
//  - 元数据（类型/时间/哈希/置顶/标签）明文，便于排序筛选
//  - 正文 text / 图片 blob 使用 AES-256-CBC 字段级加密
//  - 数据库文件启用 iOS Data Protection
//

import Foundation
import SQLite3

/// SQLite 错误
public enum ClipDatabaseError: Error {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case bindFailed(String)
}

final class ClipDatabase {
    static let shared = ClipDatabase()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.clipboard.kit.database")
    private let key: Data

    // SQL
    private let schema = """
    CREATE TABLE IF NOT EXISTS clips (
        id           TEXT PRIMARY KEY,
        type         TEXT NOT NULL,
        text         BLOB,
        image        BLOB,
        timestamp    REAL NOT NULL,
        content_hash TEXT NOT NULL,
        is_sensitive INTEGER NOT NULL DEFAULT 0,
        is_pinned    INTEGER NOT NULL DEFAULT 0,
        tags         TEXT NOT NULL DEFAULT '[]',
        category     TEXT,
        source_app   TEXT,
        pinned_at    REAL
    );
    CREATE INDEX IF NOT EXISTS idx_clips_timestamp ON clips(timestamp DESC);
    CREATE INDEX IF NOT EXISTS idx_clips_hash ON clips(content_hash);
    CREATE INDEX IF NOT EXISTS idx_clips_pinned ON clips(is_pinned);
    CREATE TABLE IF NOT EXISTS meta (
        key   TEXT PRIMARY KEY,
        value TEXT
    );
    """

    private init() {
        self.key = KeychainHelper.masterKey()
        // 所有对 db 句柄的访问都串行化到 queue，建连也在 queue 上，避免与重开竞争
        queue.sync { openLocked() }
    }

    deinit { sqlite3_close(db) }

    // MARK: - 打开 / 建表
    //
    // 重要：openLocked()/closeLocked() 假定已运行在 self.queue 上，
    // 内部绝不能再调用会 queue.sync 的方法，否则同一条串行队列重入 = 死锁。

    private func databaseURL() -> URL? {
        // 统一走 RuntimeEnvironment：标准安装用 App Group 共享容器，
        // LiveContainer / 无 group 时自动落到其容器内 Documents。
        RuntimeEnvironment.shared.databaseURL
    }

    /// 直接执行（不分派队列），仅允许在持有 queue 时调用
    private func execRaw(_ sql: String) {
        guard db != nil else { return }
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK {
            _ = lastError()
        }
    }

    private func openLocked() {
        guard let url = databaseURL() else { return }
        // 保护属性：首次解锁后可访问，磁盘加密
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        guard sqlite3_open(url.path, &db) == SQLITE_OK else {
            db = nil
            return
        }
        // 用 DELETE 回滚日志而非 WAL：主 App 与键盘是两个独立进程，WAL 的
        // -wal/-shm 跨进程快照在自签重签环境下可能让长连接读不到另一进程的提交；
        // DELETE 模式每次提交都完整落进主 .sqlite，任一进程新读事务必见最新数据。
        // busy_timeout 让读在另一进程写时等待而非立刻 SQLITE_BUSY 返回空。
        execRaw("""
        PRAGMA journal_mode = DELETE;
        PRAGMA foreign_keys = ON;
        PRAGMA busy_timeout = 5000;
        PRAGMA synchronous = FULL;
        \(schema)
        """)
    }

    private func closeLocked() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    /// 关闭并重开连接：彻底丢弃任何进程内读快照，保证看到另一进程（键盘）已落盘的提交。
    /// 由主 App 回到前台 / 列表出现时调用，频率低、开销可忽略。
    func reopen() {
        queue.sync {
            closeLocked()
            openLocked()
        }
    }

    private func lastError() -> String {
        guard let db else { return "db is nil" }
        return String(cString: sqlite3_errmsg(db))
    }

    @discardableResult
    private func execute(_ sql: String) -> Bool {
        queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
                return false
            }
            defer { sqlite3_finalize(statement) }
            return sqlite3_step(statement) == SQLITE_DONE
        }
    }

    // MARK: - 元数据键值（跨进程心跳等，与历史共用同一共享文件，最可靠）

    func setMeta(_ value: String, for key: String) {
        queue.sync {
            var statement: OpaquePointer?
            let sql = "INSERT OR REPLACE INTO meta(key, value) VALUES(?, ?);"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(statement, 2, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_step(statement)
        }
    }

    func getMeta(_ key: String) -> String? {
        queue.sync {
            var statement: OpaquePointer?
            let sql = "SELECT value FROM meta WHERE key = ?;"
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
            if let c = sqlite3_column_text(statement, 0) { return String(cString: c) }
            return nil
        }
    }

    // MARK: - 加解密（字段级）

    private func encrypt(_ plaintext: String?) -> Data? {
        guard let plaintext, let data = plaintext.data(using: .utf8), !data.isEmpty else { return nil }
        let iv = CryptoHelper.randomBytes(count: 16)
        guard let cipher = CryptoHelper.aesEncrypt(data, key: key, iv: iv) else { return nil }
        return iv + cipher
    }

    private func encrypt(_ data: Data?) -> Data? {
        guard let data, !data.isEmpty else { return nil }
        let iv = CryptoHelper.randomBytes(count: 16)
        guard let cipher = CryptoHelper.aesEncrypt(data, key: key, iv: iv) else { return nil }
        return iv + cipher
    }

    private func decryptText(_ blob: Data?) -> String? {
        guard let plain = decrypt(blob) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    private func decrypt(_ blob: Data?) -> Data? {
        guard let blob, blob.count > 16 else { return nil }
        let iv = blob.prefix(16)
        let cipher = blob.dropFirst(16)
        return CryptoHelper.aesDecrypt(Data(cipher), key: key, iv: Data(iv))
    }

    // MARK: - CRUD

    /// 全量读取（按统一排序返回）
    func fetchAll() -> [ClipItem] {
        queue.sync {
            let sql = "SELECT * FROM clips ORDER BY is_pinned DESC, COALESCE(pinned_at, timestamp) DESC, timestamp DESC;"
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }
            var result: [ClipItem] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let item = decodeRow(statement) { result.append(item) }
            }
            return result
        }
    }

    /// 插入或替换（线程安全）
    func upsert(_ item: ClipItem) {
        queue.sync { performUpsert(item) }
    }

    /// 真正的插入实现（调用方必须已持有 queue，避免重入死锁）
    private func performUpsert(_ item: ClipItem) {
        let sql = """
        INSERT OR REPLACE INTO clips
        (id, type, text, image, timestamp, content_hash, is_sensitive, is_pinned, tags, category, source_app, pinned_at)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }

        bindText(statement, index: 1, value: item.id.uuidString)
        bindText(statement, index: 2, value: item.type.rawValue)
        bindBlob(statement, index: 3, value: encrypt(item.text))
        bindBlob(statement, index: 4, value: encrypt(item.imageData))
        bindDouble(statement, index: 5, value: item.timestamp.timeIntervalSince1970)
        bindText(statement, index: 6, value: item.contentHash)
        bindInt(statement, index: 7, value: item.isSensitive ? 1 : 0)
        bindInt(statement, index: 8, value: item.isPinned ? 1 : 0)
        let tagsData = (try? JSONEncoder().encode(item.tags)) ?? Data("[]".utf8)
        bindText(statement, index: 9, value: String(data: tagsData, encoding: .utf8) ?? "[]")
        bindText(statement, index: 10, value: item.category)
        bindText(statement, index: 11, value: item.sourceApp)
        if let pinnedAt = item.pinnedAt {
            bindDouble(statement, index: 12, value: pinnedAt.timeIntervalSince1970)
        } else {
            sqlite3_bind_null(statement, 12)
        }
        sqlite3_step(statement)
    }

    /// 批量插入（迁移用，单事务）
    func bulkInsert(_ items: [ClipItem]) {
        guard !items.isEmpty else { return }
        queue.sync {
            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
            for item in items { performUpsert(item) }
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        }
    }

    func delete(id: UUID) {
        queue.sync { performDelete(id: id) }
    }

    private func performDelete(id: UUID) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "DELETE FROM clips WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindText(statement, index: 1, value: id.uuidString)
        sqlite3_step(statement)
    }

    func delete(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        queue.sync {
            sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
            for id in ids { performDelete(id: id) }
            sqlite3_exec(db, "COMMIT;", nil, nil, nil)
        }
    }

    func clearAll() {
        execute("DELETE FROM clips;")
        execute("VACUUM;")
    }

    func purge(before cutoff: Date) {
        queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM clips WHERE timestamp < ? AND is_pinned = 0;", -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            bindDouble(statement, index: 1, value: cutoff.timeIntervalSince1970)
            sqlite3_step(statement)
        }
    }

    /// 更新置顶状态
    func setPinned(id: UUID, pinned: Bool, pinnedAt: Date?) {
        queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "UPDATE clips SET is_pinned = ?, pinned_at = ? WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            bindInt(statement, index: 1, value: pinned ? 1 : 0)
            if let pinnedAt { bindDouble(statement, index: 2, value: pinnedAt.timeIntervalSince1970) }
            else { sqlite3_bind_null(statement, 2) }
            bindText(statement, index: 3, value: id.uuidString)
            sqlite3_step(statement)
        }
    }

    /// 更新敏感状态
    func setSensitive(id: UUID, sensitive: Bool) {
        queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "UPDATE clips SET is_sensitive = ? WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            bindInt(statement, index: 1, value: sensitive ? 1 : 0)
            bindText(statement, index: 2, value: id.uuidString)
            sqlite3_step(statement)
        }
    }

    /// 更新标签 / 分类
    func updateTags(id: UUID, tags: [String], category: String?) {
        queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "UPDATE clips SET tags = ?, category = ? WHERE id = ?;", -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }
            let tagsData = (try? JSONEncoder().encode(tags)) ?? Data("[]".utf8)
            bindText(statement, index: 1, value: String(data: tagsData, encoding: .utf8) ?? "[]")
            bindText(statement, index: 2, value: category)
            bindText(statement, index: 3, value: id.uuidString)
            sqlite3_step(statement)
        }
    }

    /// 记录条数
    func count() -> Int {
        queue.sync {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM clips;", -1, &statement, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    // MARK: - 行解码

    private func decodeRow(_ statement: OpaquePointer?) -> ClipItem? {
        guard let statement,
              let idString = columnText(statement, column: 0),
              let id = UUID(uuidString: idString),
              let typeRaw = columnText(statement, column: 1),
              let type = ClipContentType(rawValue: typeRaw) else { return nil }

        let text = decryptText(columnBlob(statement, column: 2))
        let image = decrypt(columnBlob(statement, column: 3))
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        let hash = columnText(statement, column: 5) ?? ""
        let sensitive = sqlite3_column_int64(statement, 6) == 1
        let pinned = sqlite3_column_int64(statement, 7) == 1
        let tagsRaw = columnText(statement, column: 8) ?? "[]"
        let tags = (try? JSONDecoder().decode([String].self, from: Data(tagsRaw.utf8))) ?? []
        let category = columnText(statement, column: 9)
        let sourceApp = columnText(statement, column: 10)
        var pinnedAt: Date?
        if sqlite3_column_type(statement, 11) != SQLITE_NULL {
            pinnedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 11))
        }

        return ClipItem(
            id: id,
            type: type,
            text: text,
            imageData: image,
            timestamp: timestamp,
            contentHash: hash,
            isSensitive: sensitive,
            isPinned: pinned,
            tags: tags,
            category: category,
            sourceApp: sourceApp,
            pinnedAt: pinnedAt
        )
    }

    // MARK: - 绑定辅助

    private func bindText(_ statement: OpaquePointer?, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindBlob(_ statement: OpaquePointer?, index: Int32, value: Data?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        value.withUnsafeBytes { raw in
            _ = sqlite3_bind_blob(statement, index, raw.baseAddress, Int32(value.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
    }

    private func bindInt(_ statement: OpaquePointer?, index: Int32, value: Int64) {
        sqlite3_bind_int64(statement, index, value)
    }

    private func bindDouble(_ statement: OpaquePointer?, index: Int32, value: Double) {
        sqlite3_bind_double(statement, index, value)
    }

    private func columnText(_ statement: OpaquePointer?, column: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: cString)
    }

    private func columnBlob(_ statement: OpaquePointer?, column: Int32) -> Data? {
        let length = sqlite3_column_bytes(statement, column)
        guard length > 0, let pointer = sqlite3_column_blob(statement, column) else { return nil }
        return Data(bytes: pointer, count: Int(length))
    }
}
