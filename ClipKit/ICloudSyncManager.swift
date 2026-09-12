//
//  ICloudSyncManager.swift
//  ClipKit
//
//  v1.1：iCloud 同步
//  - 文本类轻量记录走 CloudKit 私有数据库（图片体积大，仅本地，避免流量/配额问题）
//  - 设置项走 NSUbiquitousKeyValueStore
//  - 未登录 iCloud / 未开 iCloud 能力时全部静默降级为纯本地
//

import Foundation
import CloudKit

public final class ICloudSyncManager {
    public static let shared = ICloudSyncManager()

    private let database: CKDatabase?
    private let recordType = "ClipItem"
    private let kvs = NSUbiquitousKeyValueStore.default
    private var isSyncing = false

    /// iCloud 是否可用（容器可达）
    public var isAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    public var isEnabled: Bool {
        AppGroupConfig.sharedDefaults?.bool(forKey: AppGroupConfig.DefaultsKey.iCloudSyncEnabled) ?? false
    }

    private init() {
        // 未配置 iCloud 能力时，后续操作由 isAvailable 静默降级
        self.database = CKContainer(identifier: AppGroupConfig.cloudKitContainer).privateCloudDatabase
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(remoteChangeNotification(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvs
        )
        kvs.synchronize()
    }

    // MARK: - 上传单条

    public func upload(_ item: ClipItem, completion: ((Bool) -> Void)? = nil) {
        guard isEnabled, isAvailable, item.type != .image, let database else {
            completion?(false)
            return
        }
        let recordID = CKRecord.ID(recordName: item.id.uuidString)
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["text"] = item.text as CKRecordValue?
        record["type"] = item.type.rawValue as CKRecordValue
        record["hash"] = item.contentHash as CKRecordValue
        record["timestamp"] = item.timestamp as CKRecordValue
        record["pinned"] = (item.isPinned ? 1 : 0) as CKRecordValue
        if let tags = try? JSONEncoder().encode(item.tags) {
            record["tags"] = tags as CKRecordValue
        }
        database.save(record) { _, error in
            DispatchQueue.main.async { completion?(error == nil) }
        }
    }

    // MARK: - 拉取增量（最近 N 秒）

    public func pullChanges(since date: Date = Date().addingTimeInterval(-30 * 86_400),
                            completion: @escaping ([ClipItem]) -> Void) {
        guard isEnabled, isAvailable, let database else {
            completion([])
            return
        }
        let predicate = NSPredicate(format: "timestamp >= %@", date as NSDate)
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        database.perform(query, inZoneWith: nil) { records, _ in
            guard let records else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            let items: [ClipItem] = records.compactMap { Self.makeItem(from: $0) }
            DispatchQueue.main.async { completion(items) }
        }
    }

    /// 拉取并合并到本地（去重）
    public func syncDown(completion: (() -> Void)? = nil) {
        guard !isSyncing else { completion?(); return }
        isSyncing = true
        pullChanges { [weak self] remote in
            defer { self?.isSyncing = false }
            let store = ClipStore.shared
            for item in remote where !store.exists(contentHash: item.contentHash) {
                store.add(item)
            }
            completion?()
        }
    }

    private static func makeItem(from record: CKRecord) -> ClipItem? {
        guard let typeRaw = record["type"] as? String,
              let type = ClipContentType(rawValue: typeRaw),
              let hash = record["hash"] as? String,
              let timestamp = record["timestamp"] as? Date else { return nil }
        let tags: [String]
        if let data = record["tags"] as? Data {
            tags = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        } else { tags = [] }
        let pinned = (record["pinned"] as? Int) == 1
        return ClipItem(
            id: UUID(uuidString: record.recordID.recordName) ?? UUID(),
            type: type,
            text: record["text"] as? String,
            timestamp: timestamp,
            contentHash: hash,
            isPinned: pinned,
            tags: tags,
            category: type.displayName
        )
    }

    // MARK: - 删除

    public func remove(id: UUID, completion: ((Bool) -> Void)? = nil) {
        guard isEnabled, isAvailable, let database else { completion?(false); return }
        database.delete(withRecordID: CKRecord.ID(recordName: id.uuidString)) { _, error in
            DispatchQueue.main.async { completion?(error == nil) }
        }
    }

    // MARK: - 设置项 KVS

    public func pushSetting(_ value: Any?, forKey key: String) {
        guard isEnabled, isAvailable else { return }
        if value == nil { kvs.removeObject(forKey: key) }
        else if let v = value { kvs.set(v, forKey: key) }
        kvs.synchronize()
    }

    @objc private func remoteChangeNotification(_ note: Notification) {
        NotificationCenter.default.post(name: .iCloudSettingsChanged, object: nil)
    }
}

public extension Notification.Name {
    static let iCloudSettingsChanged = Notification.Name("com.clipboard.kit.iCloudSettingsChanged")
}
