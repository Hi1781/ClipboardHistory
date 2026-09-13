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
        BackgroundMonitor.shared.handleBecomeActive()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        BackgroundMonitor.shared.handleEnterBackground()
    }
}

extension Notification.Name {
    static let appDidBecomeActive = Notification.Name("com.clipboard.appDidBecomeActive")
}
