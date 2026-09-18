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

        // 信号 3：Bundle 或主目录位于 LiveContainer 的应用/数据容器路径下（大小写不敏感）
        let bundlePath = Bundle.main.bundlePath
        let homePath = NSHomeDirectory()
        let markers = ["/LiveContainer/", "/Documents/Applications/", "/LiveContainer/Applications/",
                       "/Data/Applications/", "/LiveContainer/Data/"]
        let haystack = (bundlePath + " " + homePath).lowercased()
        if markers.contains(where: { haystack.contains($0.lowercased()) }) {
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
    //
    // 采用「共享容器心跳文件为准、UserDefaults 为辅」双通道：
    // 文件系统跨进程一致性比 NSUserDefaults(suiteName:) 更可靠，
    // 后者在另一进程的偏好缓存可能不刷新，导致主 App 一直显示「未检测到」。

    /// 键盘状态文件（位于 App Group 共享数据目录，主 App 与键盘都可读写）
    private var keyboardStatusFile: URL {
        dataDirectory.appendingPathComponent("keyboard-status.json")
    }

    private struct KeyboardStatus: Codable { let timestamp: Double; let fullAccess: Bool }
    private static let metaKey = "keyboard.status"

    /// 键盘扩展每次出现时上报心跳：运行标记无论是否完全访问都写，另记完全访问标记。
    public func reportKeyboardHeartbeat(fullAccess: Bool) {
        let now = Date().timeIntervalSince1970
        let status = KeyboardStatus(timestamp: now, fullAccess: fullAccess)
        // 通道1：共享 SQLite meta（与历史同一文件、同一已验证共享通道，最可靠）
        if let data = try? JSONEncoder().encode(status),
           let json = String(data: data, encoding: .utf8) {
            ClipDatabase.shared.setMeta(json, for: RuntimeEnvironment.metaKey)
        }
        // 通道2：共享容器文件（原子写入）
        if let data = try? JSONEncoder().encode(status) {
            try? data.write(to: keyboardStatusFile, options: .atomic)
        }
        // 通道3：共享 UserDefaults（兜底）
        let d = defaults
        d.set(now, forKey: AppGroupConfig.DefaultsKey.keyboardHeartbeat)
        d.set(fullAccess, forKey: AppGroupConfig.DefaultsKey.keyboardFullAccess)
        d.synchronize()
    }

    /// 读取键盘状态：优先共享 SQLite meta，再共享文件，最后 UserDefaults（键盘从未运行为 nil）
    private func readKeyboardStatus() -> KeyboardStatus? {
        if let json = ClipDatabase.shared.getMeta(RuntimeEnvironment.metaKey),
           let data = json.data(using: .utf8),
           let s = try? JSONDecoder().decode(KeyboardStatus.self, from: data) {
            return s
        }
        if let data = try? Data(contentsOf: keyboardStatusFile),
           let s = try? JSONDecoder().decode(KeyboardStatus.self, from: data) {
            return s
        }
        let d = defaults; d.synchronize()
        let ts = d.double(forKey: AppGroupConfig.DefaultsKey.keyboardHeartbeat)
        guard ts > 0 else { return nil }
        return KeyboardStatus(timestamp: ts, fullAccess: d.bool(forKey: AppGroupConfig.DefaultsKey.keyboardFullAccess))
    }

    /// 是否曾检测到键盘扩展成功运行（无法在主 App 直接枚举自定义键盘，故用心跳推断）
    public var keyboardEverActivated: Bool { readKeyboardStatus() != nil }

    /// 最近一次键盘出现时是否已授予完全访问（键盘从未运行为 nil）
    public var keyboardFullAccessGranted: Bool? { readKeyboardStatus()?.fullAccess }

    /// 最近一次键盘心跳距现在的秒数（从未运行为 nil）
    public func keyboardHeartbeatAge() -> TimeInterval? {
        guard let s = readKeyboardStatus() else { return nil }
        return Date().timeIntervalSince1970 - s.timestamp
    }
}
