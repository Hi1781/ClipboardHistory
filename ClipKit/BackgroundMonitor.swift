//
//  BackgroundMonitor.swift
//  ClipKit
//
//  v2.0：后台剪贴板监听
//
//  【能力边界，务必知悉】
//  iOS 沙盒与隐私限制下，非越狱设备无法做到 7×24 静默实时捕获剪贴板。
//  本类组合三条合规路径，尽可能提高捕获率：
//   1. BGTaskScheduler（BGAppRefreshTask）：系统按用电情况调度的后台轮询；
//   2. 场景切换：进入后台/回到前台时比较 changeCount；
//   3. 可选「静音音频保活」：仅侧载（SideStore/AltStore）可用，App Store 会拒绝。
//  真正的实时捕获仍发生在「打开 App / 唤起键盘」时，由 PasteboardSync 完成。
//

import Foundation
import UIKit
import BackgroundTasks

public final class BackgroundMonitor {
    public static let shared = BackgroundMonitor()

    public static let refreshTaskIdentifier = "com.clipboard.history.refresh"

    private var pollTimer: Timer?
    private var lastSeenCount: Int = 0

    private init() {}

    /// 是否在设置中启用
    public var isEnabled: Bool {
        AppGroupConfig.sharedDefaults?.bool(forKey: AppGroupConfig.DefaultsKey.backgroundMonitorEnabled) ?? false
    }

    // MARK: - 注册（App 启动时调用）

    public func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleRefresh(task as? BGAppRefreshTask)
        }
    }

    /// 调度下一次后台刷新
    public func scheduleNextRefresh(after seconds: TimeInterval = 900) {
        guard isEnabled else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: seconds)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handleRefresh(_ task: BGAppRefreshTask?) {
        scheduleNextRefresh()
        let work = Task.detached(priority: .utility) {
            // 后台只比较 changeCount；真正读取内容会触发系统权限弹窗，故仅标记“有变化”
            let changed = PasteboardSync.shared.didChangeCount()
            if changed {
                AppGroupConfig.sharedDefaults?.set(Date().timeIntervalSince1970,
                                                   forKey: AppGroupConfig.DefaultsKey.lastBackgroundPoll)
                // 后台读到内容则直接入库并发通知；否则发占位通知，等用户下拉扩展读取
                let result = PasteboardSync.shared.performSync(sourceApp: "bgtask")
                if case .imported(let item) = result {
                    ClipNotificationManager.shared.notifyCaptured(item)
                } else {
                    ClipNotificationManager.shared.notifyChangeCountOnly()
                }
            }
        }
        task?.expirationHandler = { work.cancel() }
        Task {
            _ = await work.result
            task?.setTaskCompleted(success: true)
        }
    }

    // MARK: - 前台轮询（App 在前台时定时检查 changeCount，实现近实时）

    public func startForegroundPolling(interval: TimeInterval = 2.0) {
        stopForegroundPolling()
        lastSeenCount = PasteboardSync.shared.currentChangeCount()
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = PasteboardSync.shared.currentChangeCount()
            guard current != self.lastSeenCount else { return }
            self.lastSeenCount = current
            // 前台可安全读取内容
            let result = PasteboardSync.shared.performSync(sourceApp: "foreground-poll")
            if case .imported = result {
                NotificationCenter.default.post(name: .clipboardCapturedInBackground, object: nil)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    public func stopForegroundPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - 场景生命周期

    public func handleEnterBackground() {
        stopForegroundPolling()
        scheduleNextRefresh()
    }

    public func handleBecomeActive() {
        guard isEnabled else { return }
        startForegroundPolling()
    }
}

public extension Notification.Name {
    static let clipboardCapturedInBackground = Notification.Name("com.clipboard.kit.capturedInBackground")
}
