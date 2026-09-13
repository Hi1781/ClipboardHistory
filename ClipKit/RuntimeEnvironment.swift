//
//  RuntimeEnvironment.swift
//  ClipKit
//
//  v2.1：运行环境识别与能力降级
//  - 标准安装（SideStore/AltStore 直装）：App Group / 键盘扩展 / Widget 全部可用
//  - LiveContainer 容器内运行：系统扩展（键盘、Widget）无法注册，App Group 通常不可用，
//    Keychain 与沙盒被重定向到独立容器 —— 统一在此检测并降级，保证主 App 功能完整可用。
//

import Foundation
import UIKit
import MachO

public enum RuntimeMode: Equatable {
    /// 标准安装（系统中真正注册的 App，含自签直装）
    case standardInstall
    /// 作为 guest App 运行在 LiveContainer 容器内
    case liveContainer
}

public final class RuntimeEnvironment {
    public static let shared = RuntimeEnvironment()

    /// 数据子目录名
    private let dataFolderName = "ClipboardHistory"

    public private(set) lazy var mode: RuntimeMode = detect()

    private init() {}

    // MARK: - 便捷判断

    /// 是否运行在 LiveContainer 容器内
    public var isLiveContainer: Bool { mode == .liveContainer }

    /// 系统级扩展（自定义键盘、Widget）是否可用。
    /// LiveContainer 官方限制：guest App 无法注册 widgets/plugins/extensions（需要额外 App ID）。
    public var systemExtensionsAvailable: Bool { !isLiveContainer }

    /// 运行模式的中文展示名
    public var modeDisplayName: String {
        isLiveContainer ? "LiveContainer 容器" : "标准安装"
    }

    // MARK: - 检测（多信号交叉，避免误判）

    private func detect() -> RuntimeMode {
        let env = ProcessInfo.processInfo.environment

        // 信号 1：LiveContainer 启动 guest 时注入的环境变量 LC_HOME_PATH
        if env["LC_HOME_PATH"] != nil { return .liveContainer }

        // 信号 2：任意 LC_ 前缀环境变量
        for key in env.keys where key.hasPrefix("LC_") {
            return .liveContainer
        }

        // 信号 3：Bundle 位于 LiveContainer 的应用/共享容器路径下
        let bundlePath = Bundle.main.bundlePath
        let markers = ["/LiveContainer/", "/Documents/Applications/", "/LiveContainer/Applications/"]
        if markers.contains(where: { bundlePath.contains($0) }) {
            return .liveContainer
        }

        // 信号 4：进程内被注入 LiveContainer / TweakLoader 镜像
        let imageCount = _dyld_image_count()
        for index in 0..<imageCount {
            guard let raw = _dyld_get_image_name(index) else { continue }
            let name = String(cString: raw).lowercased()
            if name.contains("livecontainer") || name.contains("tweakloader") {
                return .liveContainer
            }
        }
        return .standardInstall
    }

    // MARK: - UserDefaults 降级

    /// 可用的 UserDefaults：优先 App Group 共享套件（主 App 与键盘互通），
    /// 套件不可用（LiveContainer / 未建 group）时回退到标准库，保证设置一定能持久化。
    public var defaults: UserDefaults {
        if let suite = UserDefaults(suiteName: AppGroupConfig.groupIdentifier) {
            return suite
        }
        return .standard
    }

    // MARK: - 容器 / 存储路径

    /// App Group 共享容器（不可用时为 nil）
    public var appGroupContainer: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupConfig.groupIdentifier)
    }

    /// 统一的数据目录：优先共享容器，其次沙盒 Documents
    /// （LiveContainer 下 Documents 已被重定向到其独立数据容器，天然隔离）。
    public var dataDirectory: URL {
        let fm = FileManager.default
        let base: URL
        if let container = appGroupContainer {
            base = container
        } else if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            base = docs
        } else {
            base = URL(fileURLWithPath: NSTemporaryDirectory())
        }
        let folder = base.appendingPathComponent(dataFolderName, isDirectory: true)
        if !fm.fileExists(atPath: folder.path) {
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// SQLite 数据库文件位置
    public var databaseURL: URL {
        dataDirectory.appendingPathComponent("history.sqlite")
    }

    // MARK: - 键盘心跳（主 App 据此判断键盘扩展是否已启用并授予完全访问）

    /// 键盘扩展每次以「完全访问」状态出现时上报心跳
    public func reportKeyboardHeartbeat(fullAccess: Bool) {
        guard fullAccess else { return }
        defaults.set(Date().timeIntervalSince1970,
                     forKey: AppGroupConfig.DefaultsKey.keyboardHeartbeat)
    }

    /// 是否曾检测到键盘扩展成功运行（无法在主 App 直接枚举自定义键盘，故用心跳推断）
    public var keyboardEverActivated: Bool {
        let ts = defaults.double(forKey: AppGroupConfig.DefaultsKey.keyboardHeartbeat)
        return ts > 0
    }

    /// 最近一次键盘心跳距现在的秒数（从未运行为 nil）
    public func keyboardHeartbeatAge() -> TimeInterval? {
        let ts = defaults.double(forKey: AppGroupConfig.DefaultsKey.keyboardHeartbeat)
        guard ts > 0 else { return nil }
        return Date().timeIntervalSince1970 - ts
    }
}
