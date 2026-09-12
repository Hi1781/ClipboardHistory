//
//  PasteboardSync.swift
//  ClipKit
//
//  剪贴板双向同步核心逻辑（v2.0）
//  - 剪贴板有内容且未记录 → 导入历史
//  - 剪贴板为空 → 回填最新历史
//  - 同步后写入 Widget 共享预览
//

import Foundation
import UIKit

public final class PasteboardSync {
    public static let shared = PasteboardSync()

    private init() {}

    /// 同步结果
    public enum SyncResult: Equatable {
        case imported(item: ClipItem)
        case restored(item: ClipItem)
        case alreadyExists
        case emptyPasteboardNoHistory
        case skipped(reason: String)
    }

    // MARK: - 核心同步入口

    /// 执行双向同步（App 前台激活 / 键盘唤起时调用）
    @discardableResult
    public func performSync(sourceApp: String? = nil) -> SyncResult {
        let pasteboard = UIPasteboard.general
        let hasContent = pasteboard.hasStrings || pasteboard.hasImages || pasteboard.hasURLs || pasteboard.hasColors

        if hasContent {
            return importIfNeeded(pasteboard: pasteboard, sourceApp: sourceApp)
        } else {
            return restoreIfNeeded()
        }
    }

    // MARK: - 导入：剪贴板 → 历史

    private func importIfNeeded(pasteboard: UIPasteboard, sourceApp: String?) -> SyncResult {
        let autoImport = AppGroupConfig.sharedDefaults?
            .object(forKey: AppGroupConfig.DefaultsKey.autoImportOnLaunch) as? Bool ?? true
        guard autoImport else { return .skipped(reason: "自动导入已关闭") }

        let currentChangeCount = pasteboard.changeCount
        let lastChangeCount = AppGroupConfig.sharedDefaults?
            .integer(forKey: AppGroupConfig.DefaultsKey.lastChangeCount) ?? 0

        guard currentChangeCount != lastChangeCount else { return .alreadyExists }

        let item = buildItem(from: pasteboard, sourceApp: sourceApp)

        guard let newItem = item else {
            AppGroupConfig.sharedDefaults?.set(currentChangeCount, forKey: AppGroupConfig.DefaultsKey.lastChangeCount)
            return .skipped(reason: "不支持的剪贴板类型")
        }

        let added = ClipStore.shared.add(newItem)
        AppGroupConfig.sharedDefaults?.set(currentChangeCount, forKey: AppGroupConfig.DefaultsKey.lastChangeCount)

        if added { updateWidgetSnapshot(with: newItem) }
        return added ? .imported(item: newItem) : .alreadyExists
    }

    /// 从剪贴板构造 ClipItem（图片优先于字符串，避免图片被读成描述文本）
    private func buildItem(from pasteboard: UIPasteboard, sourceApp: String?) -> ClipItem? {
        if pasteboard.hasImages, let image = pasteboard.image {
            return ClipItem.makeImage(image, sourceApp: sourceApp)
        }
        if pasteboard.hasURLs, let url = pasteboard.url {
            return ClipItem.makeText(url.absoluteString, sourceApp: sourceApp)
        }
        if pasteboard.hasStrings, let text = pasteboard.string, !text.isEmpty {
            return ClipItem.makeText(text, sourceApp: sourceApp)
        }
        if pasteboard.hasColors, let color = pasteboard.color {
            return ClipItem.makeColor(color)
        }
        return nil
    }

    // MARK: - 回填：历史 → 剪贴板

    private func restoreIfNeeded() -> SyncResult {
        let autoRestore = AppGroupConfig.sharedDefaults?
            .bool(forKey: AppGroupConfig.DefaultsKey.autoRestoreWhenEmpty) ?? false
        guard autoRestore else { return .skipped(reason: "自动回填已关闭") }

        guard let latest = ClipStore.shared.fetchLatest() else {
            return .emptyPasteboardNoHistory
        }
        writeToPasteboard(latest)
        return .restored(item: latest)
    }

    /// 将记录写入系统剪贴板
    public func writeToPasteboard(_ item: ClipItem) {
        let pasteboard = UIPasteboard.general
        // iOS16+：设置过期时间为永不，且标记为本地自有内容，减少系统提示
        switch item.type {
        case .text, .url, .other:
            if let text = item.text {
                pasteboard.string = text
            }
        case .image:
            if let image = item.image {
                pasteboard.image = image
            }
        case .color:
            if let text = item.text, let color = UIColor(hex: text) {
                pasteboard.color = color
            }
        }
        AppGroupConfig.sharedDefaults?.set(
            pasteboard.changeCount,
            forKey: AppGroupConfig.DefaultsKey.lastChangeCount
        )
    }

    // MARK: - 轻量轮询（后台/场景切换，不读取内容不弹窗）

    public func currentChangeCount() -> Int { UIPasteboard.general.changeCount }

    public func hasContent() -> Bool {
        let pb = UIPasteboard.general
        return pb.hasStrings || pb.hasImages || pb.hasURLs || pb.hasColors
    }

    /// changeCount 是否发生变化（仅比较计数，不触发内容读取权限弹窗）
    public func didChangeCount() -> Bool {
        let current = UIPasteboard.general.changeCount
        let last = AppGroupConfig.sharedDefaults?
            .integer(forKey: AppGroupConfig.DefaultsKey.lastChangeCount) ?? 0
        return current != last
    }

    // MARK: - Widget 快照

    private func updateWidgetSnapshot(with item: ClipItem) {
        let defaults = AppGroupConfig.sharedDefaults
        var preview = item.previewText
        if preview.count > 120 { preview = String(preview.prefix(120)) + "…" }
        defaults?.set(preview, forKey: AppGroupConfig.DefaultsKey.widgetLatestPreview)
        defaults?.set(item.timestamp.timeIntervalSince1970, forKey: AppGroupConfig.DefaultsKey.widgetLatestTime)
    }

    /// 主动刷新 Widget 快照（列表复制 / 删除后调用）
    public func refreshWidgetSnapshot() {
        guard let latest = ClipStore.shared.fetchLatest() else {
            AppGroupConfig.sharedDefaults?.removeObject(forKey: AppGroupConfig.DefaultsKey.widgetLatestPreview)
            return
        }
        updateWidgetSnapshot(with: latest)
    }
}
