//
//  SceneDelegate.swift
//  ClipboardHistory
//

import UIKit
import ClipKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let window = UIWindow(windowScene: windowScene)
        let historyVC = HistoryViewController()
        let nav = UINavigationController(rootViewController: historyVC)
        nav.navigationBar.prefersLargeTitles = true
        window.rootViewController = nav
        self.window = window
        window.makeKeyAndVisible()
        // 路径1：挂载画中画保活所需的隐藏播放层（真正开启由用户在设置内点按）
        PiPKeepAlive.shared.install(in: window)
        presentOnboardingIfNeeded(from: nav)
    }

    /// 首次启动（或版本升级后未完成引导）呈现权限引导
    private func presentOnboardingIfNeeded(from host: UIViewController) {
        AppGroupConfig.registerDefaults()
        let done = AppGroupConfig.sharedDefaults?
            .bool(forKey: AppGroupConfig.DefaultsKey.onboardingCompleted) ?? false
        guard !done else { return }
        let onboarding = OnboardingViewController()
        onboarding.modalPresentationStyle = .fullScreen
        onboarding.isModalInPresentation = true
        host.present(onboarding, animated: true)
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        NotificationCenter.default.post(name: .appDidBecomeActive, object: nil)
        // 路径6：进入前台立即双向同步（有则入库，空则按设置回填）
        _ = PasteboardSync.shared.performSync(sourceApp: "become-active")
        BackgroundMonitor.shared.handleBecomeActive()
        // 回到前台后停止静音音频保活，避免占用音频会话
        SilentAudioKeepAlive.shared.stop()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        BackgroundMonitor.shared.handleEnterBackground()
        // 路径2：退到后台时，若用户开启，则用静音音频保活并低频轮询
        SilentAudioKeepAlive.shared.start()
    }
}

extension Notification.Name {
    static let appDidBecomeActive = Notification.Name("com.clipboard.appDidBecomeActive")
}
