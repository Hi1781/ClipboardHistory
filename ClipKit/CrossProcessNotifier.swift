//
//  CrossProcessNotifier.swift
//  ClipKit
//
//  v2.5：主 App 与键盘扩展是两个独立进程。键盘写入共享 SQLite 后，
//  通过 Darwin 通知（系统级、按名字投递、同 team 进程可收）即时唤醒主 App
//  从磁盘 reloadSync，解决「键盘→App」方向内存缓存不刷新的问题。
//  相比 UserDefaults 跨进程 KVO，Darwin 通知不依赖偏好缓存，投递更可靠。
//

import Foundation

public enum CrossProcessNotifier {
    /// 本进程内收到外部变更后发出的 NotificationCenter 事件
    public static let localDidChange = Notification.Name("com.clipboard.history.crossProcessDidChange")
    private static let darwinName = "com.clipboard.history.store.externalChange"

    /// 桥接对象：需在观察期间常驻，保证 observer 指针有效
    private static let bridge = ObserverBridge()

    private final class ObserverBridge {
        var handler: (() -> Void)?
    }

    /// 写入共享数据后调用：通知同 team 的其它进程
    public static func post() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let name = CFNotificationName(darwinName as CFString)
        CFNotificationCenterPostNotification(center, name, nil, nil, true)
    }

    /// 进程启动时调用一次：收到其它进程的变更通知后在主线程回调
    public static func startObserving(_ handler: @escaping () -> Void) {
        bridge.handler = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(bridge).toOpaque()
        // @convention(c) 闭包不能捕获上下文，故用回调第 2 个参数回拿 bridge
        let callback: CFNotificationCallback = { _, observerPtr, _, _, _ in
            guard let observerPtr else { return }
            let b = Unmanaged<ObserverBridge>.fromOpaque(observerPtr).takeUnretainedValue()
            DispatchQueue.main.async { b.handler?() }
        }
        CFNotificationCenterAddObserver(
            center, observer, callback,
            darwinName as CFString, nil,
            CFNotificationSuspensionBehavior.deliverImmediately)
    }
}
