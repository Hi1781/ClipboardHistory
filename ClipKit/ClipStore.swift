//
//  ClipStore.swift
//  ClipKit
//
//  历史记录门面（v2.0）
//  - SQLite 为持久化真相源（ClipDatabase）
//  - 内存缓存承载搜索 / 筛选 / 排序，保证列表与键盘流畅
//  - 兼容 v1.0 加密 JSON（history.enc）一次性迁移
//

import Foundation
import UIKit

/// 列表筛选条件
public struct ClipFilter: Equatable {
    public var keyword: String = ""
    public var type: ClipContentType?
    public var tag: String?
    public var includeSensitive: Bool = true
    public var pinnedOnly: Bool = false

    public init(keyword: String = "", type: ClipContentType? = nil, tag: String? = nil,
                includeSensitive: Bool = true, pinnedOnly: Bool = false) {
        self.keyword = keyword
        self.type = type
        self.tag = tag
        self.includeSensitive = includeSensitive
        self.pinnedOnly = pinnedOnly
    }

    public static let none = ClipFilter()
}

public final class ClipStore {
    public static let shared = ClipStore()

    private let database = ClipDatabase.shared
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.clipboard.kit.store", attributes: .concurrent)

    private var cachedItems: [ClipItem] = []
    private var cacheLoaded = false

    /// 数据变更通知（主线程发送）
    public static let didChangeNotification = Notification.Name("com.clipboard.kit.storeDidChange")

    private init() {
        migrateLegacyStoreIfNeeded()
    }

    // MARK: - 读取

    /// 全部记录（统一排序）
    public func fetchAll() -> [ClipItem] {
        queue.sync {
            if cacheLoaded { return cachedItems }
            cachedItems = database.fetchAll()
            cacheLoaded = true
            return cachedItems
        }
    }

    /// 按条件筛选
    public func fetch(filter: ClipFilter = .none) -> [ClipItem] {
        let all = fetchAll()
        let keywords = filter.keyword
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map(String.init)
            .filter { !$0.isEmpty }

        return all.filter { item in
            if !filter.includeSensitive && item.isSensitive { return false }
            if filter.pinnedOnly && !item.isPinned { return false }
            if let type = filter.type, item.type != type { return false }
            if let tag = filter.tag, !item.tags.contains(tag) { return false }
            if !keywords.isEmpty && !item.matches(keywords) { return false }
            return true
        }
    }

    /// 搜索（便捷方法）
    public func search(_ keyword: String, type: ClipContentType? = nil) -> [ClipItem] {
        fetch(filter: ClipFilter(keyword: keyword, type: type))
    }

    /// 最新一条非敏感记录
    public func fetchLatest() -> ClipItem? {
        fetchAll().first(where: { !$0.isSensitive })
    }

    /// 置顶记录
    public func fetchPinned() -> [ClipItem] {
        fetchAll().filter { $0.isPinned }
    }

    /// 全部标签（去重，按使用频次排序）
    public func allTags() -> [String] {
        var counts: [String: Int] = [:]
        for item in fetchAll() {
            for tag in item.tags { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { $0.value > $1.value }.map(\.key)
    }

    public func exists(contentHash: String) -> Bool {
        fetchAll().contains { $0.contentHash == contentHash }
    }

    public func item(id: UUID) -> ClipItem? {
        fetchAll().first { $0.id == id }
    }

    public func totalCount() -> Int { fetchAll().count }

    // MARK: - 写入

    /// 追加一条（自动去重，返回是否新增）
    @discardableResult
    public func add(_ item: ClipItem) -> Bool {
        let dedup = AppGroupConfig.sharedDefaults?.bool(forKey: AppGroupConfig.DefaultsKey.deduplicateEnabled) ?? true
        if dedup, exists(contentHash: item.contentHash) {
            return false
        }
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            self.database.upsert(item)
            self.cachedItems.insert(item, at: 0)
            self.cachedItems = self.cachedItems.sortedForDisplay()
            self.trimIfNeeded()
            self.postChange()
        }
        return true
    }

    /// 用编辑后的文本「原地替换」某条记录（保留 id 与标签/置顶等元数据）
    public func replaceText(id: UUID, edited: String) {
        guard let current = item(id: id), current.text != nil else { return }
        let replaced = current.replacingText(edited)
        mutate { db, items in
            db.upsert(replaced)
            if let idx = items.firstIndex(where: { $0.id == id }) { items[idx] = replaced }
            items = items.sortedForDisplay()
        }
    }

    public func delete(id: UUID) {
        mutate { db, items in
            db.delete(id: id)
            items.removeAll { $0.id == id }
        }
    }

    /// v1.2 批量删除
    public func delete(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        mutate { db, items in
            db.delete(ids: ids)
            let idSet = Set(ids)
            items.removeAll { idSet.contains($0.id) }
        }
    }

    public func clearAll() {
        mutate { db, items in
            db.clearAll()
            items.removeAll()
        }
    }

    /// 切换敏感
    public func toggleSensitive(id: UUID) {
        guard let current = item(id: id) else { return }
        let newValue = !current.isSensitive
        mutate { db, items in
            db.setSensitive(id: id, sensitive: newValue)
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].isSensitive = newValue
            }
        }
    }

    // MARK: - v1.2 置顶 / 标签

    @discardableResult
    public func togglePinned(id: UUID) -> Bool {
        guard let current = item(id: id) else { return false }
        let newValue = !current.isPinned
        let pinnedAt = newValue ? Date() : nil
        mutate { db, items in
            db.setPinned(id: id, pinned: newValue, pinnedAt: pinnedAt)
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].isPinned = newValue
                items[idx].pinnedAt = pinnedAt
                items.sort { lhs, rhs in
                    if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
                    return lhs.timestamp > rhs.timestamp
                }
            }
        }
        return newValue
    }

    public func setTags(id: UUID, tags: [String], category: String? = nil) {
        let cleaned = tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        mutate { db, items in
            db.updateTags(id: id, tags: cleaned, category: category)
            if let idx = items.firstIndex(where: { $0.id == id }) {
                items[idx].tags = cleaned
                if let category { items[idx].category = category }
            }
        }
    }

    public func addTag(id: UUID, tag: String) {
        guard let current = item(id: id), !current.tags.contains(tag) else { return }
        setTags(id: id, tags: current.tags + [tag])
    }

    // MARK: - 自动清理

    public func purgeOldRecords(days: Int) {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-TimeInterval(days * 86_400))
        mutate { db, items in
            db.purge(before: cutoff)
            items.removeAll { $0.timestamp < cutoff && !$0.isPinned }
        }
    }

    private func trimIfNeeded() {
        let maxCount = AppGroupConfig.sharedDefaults?.integer(forKey: AppGroupConfig.DefaultsKey.maxRecordCount) ?? 1000
        let limit = maxCount > 0 ? maxCount : 1000
        guard cachedItems.count > limit else { return }
        // 先删未置顶的最旧记录
        let pinned = cachedItems.filter { $0.isPinned }
        let normal = cachedItems.filter { !$0.isPinned }
        if normal.count > limit {
            let toRemove = Array(normal.suffix(normal.count - limit))
            database.delete(ids: toRemove.map(\.id))
            cachedItems = pinned + Array(normal.prefix(limit))
            cachedItems = cachedItems.sortedForDisplay()
        }
    }

    // MARK: - 跨进程刷新

    /// 强制从磁盘重新加载（键盘 / Widget 跨进程后调用）
    public func reload() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            self.cachedItems = self.database.fetchAll()
            self.cacheLoaded = true
        }
    }

    /// 同步重载（键盘 viewWillAppear 需要立即拿到数据）
    public func reloadSync() {
        queue.sync(flags: .barrier) { [weak self] in
            guard let self else { return }
            self.cachedItems = self.database.fetchAll()
            self.cacheLoaded = true
        }
    }

    // MARK: - 私有：统一写入口

    private func mutate(_ block: @escaping (ClipDatabase, inout [ClipItem]) -> Void) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self else { return }
            block(self.database, &self.cachedItems)
            self.cachedItems = self.cachedItems.sortedForDisplay()
            self.postChange()
        }
    }

    private func postChange() {
        // 通知其它进程（如主 App）共享库已被本进程（如键盘）写入
        CrossProcessNotifier.post()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        }
    }

    // MARK: - v1.0 → v2.0 迁移（加密 JSON → SQLite）

    private func legacyFileURL() -> URL? {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppGroupConfig.groupIdentifier)
                ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return container.appendingPathComponent("ClipboardHistory/history.enc")
    }

    private func migrateLegacyStoreIfNeeded() {
        // 已有数据库记录则不迁移
        guard database.count() == 0,
              let url = legacyFileURL(),
              fileManager.fileExists(atPath: url.path),
              let encrypted = try? Data(contentsOf: url),
              encrypted.count > 16 else { return }

        let key = KeychainHelper.masterKey()
        let iv = encrypted.prefix(16)
        let cipher = encrypted.dropFirst(16)
        guard let plain = CryptoHelper.aesDecrypt(Data(cipher), key: key, iv: Data(iv)) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let legacy = try? decoder.decode([ClipItem].self, from: plain), !legacy.isEmpty else { return }

        database.bulkInsert(legacy)
        // 迁移完成后将旧文件改名备份，不直接删除用户数据
        let backupURL = url.deletingLastPathComponent().appendingPathComponent("history.enc.migrated")
        try? fileManager.moveItem(at: url, to: backupURL)
    }
}
