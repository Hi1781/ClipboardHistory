//
//  AppDelegate.swift
//  ClipboardHistory
//

import UIKit
import BackgroundTasks
import ClipKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // 出厂默认设置
        AppGroupConfig.registerDefaults()
        // 后台监听任务注册
        BackgroundMonitor.shared.register()
        // 启动时执行一次同步与清理
        ClipStore.shared.reloadSync()
        scheduleRoutinePurge()
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        BackgroundMonitor.shared.handleEnterBackground()
    }

    /// 按设置执行例行清理
    private func scheduleRoutinePurge() {
        let days = AppGroupConfig.sharedDefaults?.integer(forKey: AppGroupConfig.DefaultsKey.autoDeleteDays) ?? 0
        if days > 0 { ClipStore.shared.purgeOldRecords(days: days) }
    }
}
