//
//  ClipNotificationManager.swift
//  ClipKit
//
//  路径3：本地通知 + Notification Content Extension
//
//  当 PiP / 静音音频 / BGTask 在后台仅能比对 changeCount 时，先发出一条本地
//  通知；用户下拉展开通知，系统会拉起 ClipboardNotify（通知内容扩展），
//  由扩展在被系统唤起的时机真正读取剪贴板并入库、展示内容，从而绕开
//  「后台读不到跨 App 剪贴板内容」的限制。
//

import Foundation
import UserNotifications

public final class ClipNotificationManager {
    public static let shared = ClipNotificationManager()

    /// 与 ClipboardNotify 扩展 Info.plist 中 UNNotificationExtensionCategory 一致
    public static let captureCategoryID = "CLIP_CAPTURED"

    private init() {}

    public var enabled: Bool {
        AppGroupConfig.sharedDefaults?.bool(forKey: AppGroupConfig.DefaultsKey.notifyCaptureEnabled) ?? true
    }

    // MARK: 授权

    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let category = UNNotificationCategory(
            identifier: Self.captureCategoryID,
            actions: [],
            intentIdentifiers: [],
            options: [.hiddenPreviewsShowTitle])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: 发送捕获通知

    public func notifyCaptured(_ item: ClipItem) {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "已捕获新剪贴板"
        var body = item.previewText
        if body.count > 60 { body = String(body.prefix(60)) + "…" }
        content.body = body.isEmpty ? "下拉查看并保存" : body
        content.categoryIdentifier = Self.captureCategoryID
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// 仅检测到 changeCount 变化、尚读不到内容时的占位通知（等用户下拉扩展读取）
    public func notifyChangeCountOnly() {
        guard enabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "剪贴板发生变化"
        content.body = "下拉展开以读取并保存最新内容"
        content.categoryIdentifier = Self.captureCategoryID
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
