//
//  AppGroupConfig.swift
//  ClipKit
//
//  App Group 与全局常量配置（v2.0）
//

import Foundation

public enum AppGroupConfig {
    /// App Group 标识，必须与 entitlements 中一致
    public static let groupIdentifier = "group.com.clipboard.history"

    /// iCloud KVS / CloudKit 容器标识
    public static let iCloudContainer = "iCloud.com.clipboard.history"
    public static let cloudKitContainer = "iCloud.com.clipboard.history"

    /// 共享 UserDefaults 中的键
    public enum DefaultsKey {
        // 同步
        public static let lastChangeCount = "lastPasteboardChangeCount"
        public static let autoImportOnLaunch = "autoImportOnLaunch"
        public static let autoRestoreWhenEmpty = "autoRestoreWhenEmpty"
        public static let deduplicateEnabled = "deduplicateEnabled"
        public static let autoDeleteDays = "autoDeleteDays"
        public static let backgroundMonitorEnabled = "backgroundMonitorEnabled"
        // v1.1
        public static let iCloudSyncEnabled = "iCloudSyncEnabled"
        public static let hapticFeedbackEnabled = "hapticFeedbackEnabled"
        // v1.2
        public static let defaultTag = "defaultTag"
        public static let showPinnedFirst = "showPinnedFirst"
        // v2.0
        public static let maxRecordCount = "maxRecordCount"
        public static let keychainMigrated = "keychainMigrated"
        public static let lastBackgroundPoll = "lastBackgroundPoll"
        // Widget
        public static let widgetLatestPreview = "widgetLatestPreview"
        public static let widgetLatestTime = "widgetLatestTime"
    }

    /// 共享 UserDefaults 实例
    public static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: groupIdentifier)
    }

    /// 注册出厂默认值
    public static func registerDefaults() {
        sharedDefaults?.register(defaults: [
            DefaultsKey.autoImportOnLaunch: true,
            DefaultsKey.autoRestoreWhenEmpty: false,
            DefaultsKey.deduplicateEnabled: true,
            DefaultsKey.autoDeleteDays: 0,
            DefaultsKey.backgroundMonitorEnabled: false,
            DefaultsKey.iCloudSyncEnabled: false,
            DefaultsKey.hapticFeedbackEnabled: true,
            DefaultsKey.showPinnedFirst: true,
            DefaultsKey.maxRecordCount: 1000
        ])
    }
}
