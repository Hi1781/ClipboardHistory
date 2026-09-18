//
//  SettingsViewController.swift
//  ClipboardHistory
//
//  设置页 v2.0：同步 / 后台 / iCloud / 存储 / 外观 / 关于
//

import UIKit
import ClipKit

final class SettingsViewController: UITableViewController {

    private enum Section: Int, CaseIterable {
        case permission, sync, background, cloud, storage, appearance, about
        var title: String {
            switch self {
            case .permission: return "权限与引导"
            case .sync: return "同步"
            case .background: return "后台监听"
            case .cloud: return "iCloud"
            case .storage: return "存储"
            case .appearance: return "外观与交互"
            case .about: return "关于"
            }
        }
    }

    private struct Row {
        enum Kind { case toggle(String, String, Selector, Bool), detail(String, String), action(String, UIColor) }
        let kind: Kind
    }

    private var sections: [(Section, [Row])] = []

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "设置"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(dismissSelf))
        NotificationCenter.default.addObserver(
            self, selector: #selector(pipStateChanged),
            name: .pipKeepAliveStateChanged, object: nil)
        buildModel()
    }

    @objc private func pipStateChanged() {
        buildModel(); tableView.reloadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        buildModel()
        tableView.reloadData()
    }

    @objc private func dismissSelf() { dismiss(animated: true) }

    // MARK: - 模型

    private func d(_ key: String, _ fallback: Bool) -> Bool {
        AppGroupConfig.sharedDefaults?.object(forKey: key) as? Bool ?? fallback
    }

    private func buildModel() {
        let k = AppGroupConfig.DefaultsKey.self
        let env = RuntimeEnvironment.shared
        sections = [
            (.permission, [
                Row(kind: .action("查看权限与使用引导", .systemIndigo)),
                Row(kind: .detail("运行模式", env.modeDisplayName)),
                Row(kind: .action("键盘扩展：\(keyboardStatusText())", keyboardStatusColor())),
                Row(kind: .detail("后台 App 刷新", backgroundRefreshText()))
            ]),
            (.sync, [
                Row(kind: .toggle("进入 App 时自动导入剪贴板", k.autoImportOnLaunch, #selector(toggleAutoImport(_:)), d(k.autoImportOnLaunch, true))),
                Row(kind: .toggle("剪贴板为空时回填最新记录", k.autoRestoreWhenEmpty, #selector(toggleAutoRestore(_:)), d(k.autoRestoreWhenEmpty, false))),
                Row(kind: .toggle("自动去重（相同内容不重复保存）", k.deduplicateEnabled, #selector(toggleDedup(_:)), d(k.deduplicateEnabled, true)))
            ]),
            (.background, [
                Row(kind: .toggle("路径5/6 前台轮询 + 系统后台刷新", k.backgroundMonitorEnabled, #selector(toggleBackground(_:)), d(k.backgroundMonitorEnabled, false))),
                Row(kind: .toggle("路径1 画中画保活轮询", k.pipKeepAliveEnabled, #selector(togglePiP(_:)), d(k.pipKeepAliveEnabled, false))),
                Row(kind: .action("立即开启画中画悬浮窗", .systemBlue)),
                Row(kind: .toggle("路径2 静音音频后台保活", k.audioKeepAliveEnabled, #selector(toggleAudioKeepAlive(_:)), d(k.audioKeepAliveEnabled, false))),
                Row(kind: .toggle("路径3 捕获后发本地通知", k.notifyCaptureEnabled, #selector(toggleNotify(_:)), d(k.notifyCaptureEnabled, true))),
                Row(kind: .detail("画中画状态", PiPKeepAlive.shared.isActive ? "运行中" : "未开启")),
                Row(kind: .detail("捕获路径", "键盘/前台/PiP/音频/BGTask/通知"))
            ]),
            (.cloud, [
                Row(kind: .toggle("iCloud 多设备同步（仅文本）", k.iCloudSyncEnabled, #selector(toggleCloud(_:)), d(k.iCloudSyncEnabled, false))),
                Row(kind: .action("立即同步", .systemBlue))
            ]),
            (.storage, [
                Row(kind: .detail("自动清理历史记录", autoDeleteText())),
                Row(kind: .detail("最大记录条数", "\(maxRecordText())")),
                Row(kind: .action("立即清理过期记录", .systemBlue)),
                Row(kind: .action("清除全部历史", .systemRed))
            ]),
            (.appearance, [
                Row(kind: .toggle("置顶记录排在最前", k.showPinnedFirst, #selector(togglePinnedFirst(_:)), d(k.showPinnedFirst, true))),
                Row(kind: .toggle("触感反馈", k.hapticFeedbackEnabled, #selector(toggleHaptic(_:)), d(k.hapticFeedbackEnabled, true))),
                Row(kind: .action("管理全部标签", .systemBlue))
            ]),
            (.about, [
                Row(kind: .detail("版本", "2.6.1")),
                Row(kind: .detail("数据存储", "本地 SQLite + AES-256 加密")),
                Row(kind: .detail("密钥保护", "iOS Keychain")),
                Row(kind: .detail("隐私说明", "数据不出设备，iCloud 走私有库"))
            ])
        ]
    }

    private func keyboardStatusText() -> String {
        let env = RuntimeEnvironment.shared
        if env.isLiveContainer { return "LiveContainer 不支持（点此查看）" }
        switch env.keyboardFullAccessGranted {
        case .some(true): return "已启用"
        case .some(false): return "已添加，未开完全访问"
        case .none: return "未检测到（点此查看）"
        }
    }

    private func keyboardStatusColor() -> UIColor {
        let env = RuntimeEnvironment.shared
        if env.isLiveContainer { return .systemOrange }
        switch env.keyboardFullAccessGranted {
        case .some(true): return .systemGreen
        default: return .systemOrange
        }
    }

    private func showKeyboardGuide() {
        let env = RuntimeEnvironment.shared
        if env.isLiveContainer {
            showAlert(title: "LiveContainer 无法使用键盘扩展",
                      message: "LiveContainer 官方限制：容器内的 App 不能注册自定义键盘 / Widget（需要额外 App ID）。\n\n如需在系统键盘里查看历史，请用 SideStore / AltStore 直装本 IPA（不要放进 LiveContainer），再到：设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → 选「剪贴板」，并打开「允许完全访问」。")
            return
        }
        switch env.keyboardFullAccessGranted {
        case .some(true):
            showAlert(title: "键盘扩展已启用", message: "在任意输入框长按地球键切换到「剪贴板」键盘即可查看历史、一键复制。\n若刚重装仍显示旧状态，唤起一次键盘后回到本页会自动刷新。")
        case .some(false):
            showAlert(title: "请开启完全访问",
                      message: "设置 → 通用 → 键盘 → 键盘 → 剪贴板 → 打开「允许完全访问」。\n未开完全访问时键盘无法读取共享历史。")
        case .none:
            showAlert(title: "尚未检测到键盘",
                      message: "1. 设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → 选「剪贴板」\n2. 点开「剪贴板」→ 打开「允许完全访问」\n3. 到任意输入框切换到该键盘一次，再回到本 App，状态会自动变为「已启用」。")
        }
    }

    private func backgroundRefreshText() -> String {
        UIApplication.shared.backgroundRefreshStatus == .available ? "可用" : "已关闭"
    }

    private func autoDeleteText() -> String {
        let days = AppGroupConfig.sharedDefaults?.integer(forKey: AppGroupConfig.DefaultsKey.autoDeleteDays) ?? 0
        return days == 0 ? "关闭" : "\(days) 天前"
    }

    private func maxRecordText() -> String {
        "\(AppGroupConfig.sharedDefaults?.integer(forKey: AppGroupConfig.DefaultsKey.maxRecordCount) ?? 1000)"
    }

    // MARK: - DataSource

    override func numberOfSections(in tableView: UITableView) -> Int { sections.count }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        sections[section].0.title
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        sections[section].1.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell")
            ?? UITableViewCell(style: .value1, reuseIdentifier: "cell")
        cell.textLabel?.font = .systemFont(ofSize: 16)
        cell.textLabel?.textColor = .label
        cell.accessoryView = nil
        cell.accessoryType = .none
        cell.detailTextLabel?.text = nil
        cell.selectionStyle = .default

        let row = sections[indexPath.section].1[indexPath.row]
        switch row.kind {
        case let .toggle(title, _, action, isOn):
            cell.textLabel?.text = title
            let sw = UISwitch()
            sw.isOn = isOn
            sw.onTintColor = .systemGreen
            sw.addTarget(self, action: action, for: .valueChanged)
            cell.accessoryView = sw
            cell.selectionStyle = .none
        case let .detail(title, value):
            cell.textLabel?.text = title
            cell.detailTextLabel?.text = value
            cell.selectionStyle = .none
        case let .action(title, color):
            cell.textLabel?.text = title
            cell.textLabel?.textColor = color
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let section = sections[indexPath.section].0
        let rowIndex = indexPath.row
        switch (section, rowIndex) {
        case (.permission, 0): showOnboarding()
        case (.permission, 2): showKeyboardGuide()
        case (.background, 2): startPiPNow()
        case (.storage, 0): showAutoDeletePicker()
        case (.storage, 1): showMaxRecordPicker()
        case (.storage, 2): purgeNow()
        case (.storage, 3): showClearConfirmation()
        case (.cloud, 1): syncNow()
        case (.appearance, 2): showTagManager()
        default: break
        }
    }

    // MARK: - Toggle Actions

    @objc private func toggleAutoImport(_ s: UISwitch) { AppGroupConfig.sharedDefaults?.set(s.isOn, forKey: AppGroupConfig.DefaultsKey.autoImportOnLaunch) }
    @objc private func toggleAutoRestore(_ s: UISwitch) { AppGroupConfig.sharedDefaults?.set(s.isOn, forKey: AppGroupConfig.DefaultsKey.autoRestoreWhenEmpty) }
    @objc private func toggleDedup(_ s: UISwitch) { AppGroupConfig.sharedDefaults?.set(s.isOn, forKey: AppGroupConfig.DefaultsKey.deduplicateEnabled) }
    @objc private func togglePinnedFirst(_ s: UISwitch) { AppGroupConfig.sharedDefaults?.set(s.isOn, forKey: AppGroupConfig.DefaultsKey.showPinnedFirst) }
    @objc private func toggleHaptic(_ s: UISwitch) { AppGroupConfig.sharedDefaults?.set(s.isOn, forKey: AppGroupConfig.DefaultsKey.hapticFeedbackEnabled) }

    @objc private func toggleBackground(_ s: UISwitch) {
        AppGroupConfig.sharedDefaults?.set(s.isOn, forKey: AppGroupConfig.DefaultsKey.backgroundMonitorEnabled)
        if s.isOn {
            BackgroundMonitor.shared.startForegroundPolling()
            BackgroundMonitor.shared.scheduleNextRefresh()
        } else {
            BackgroundMonitor.shared.stopForegroundPolling()
        }
    }

    @objc private func togglePiP(_ s: UISwitch) {
        guard PiPKeepAlive.isSupported else {
            s.isOn = false
            AppGroupConfig.sharedDefaults?.set(false, forKey: AppGroupConfig.DefaultsKey.pipKeepAliveEnabled)
            showAlert(title: "设备不支持画中画", message: "当前设备/系统状态无法开启画中画，请改用其它捕获路径")
            return
        }
        AppGroupConfig.sharedDefaults?.set(s.isOn, forKey: AppGroupConfig.DefaultsKey.pipKeepAliveEnabled)
        if s.isOn { startPiPNow() } else { PiPKeepAlive.shared.stopPiP() }
    }

    @objc private func toggleAudioKeepAlive(_ s: UISwitch) {
        AppGroupConfig.sharedDefaults?.set(s.isOn, forKey: AppGroupConfig.DefaultsKey.audioKeepAliveEnabled)
        if s.isOn { SilentAudioKeepAlive.shared.start() } else { SilentAudioKeepAlive.shared.stop() }
    }

    @objc private func toggleNotify(_ s: UISwitch) {
        AppGroupConfig.sharedDefaults?.set(s.isOn, forKey: AppGroupConfig.DefaultsKey.notifyCaptureEnabled)
        if s.isOn { ClipNotificationManager.shared.requestAuthorization() }
    }

    private func startPiPNow() {
        AppGroupConfig.sharedDefaults?.set(true, forKey: AppGroupConfig.DefaultsKey.pipKeepAliveEnabled)
        let ok = PiPKeepAlive.shared.startPiP()
        if !ok {
            showAlert(title: "无法开启画中画",
                      message: "当前设备不支持画中画，或视频资源缺失。请改用静音音频 / 键盘 / 前台同步等其它捕获路径。")
        } else {
            // KVO 会在视频就绪后自动弹出悬浮小窗；回到主界面上滑回桌面小窗即常驻
            showAlert(title: "画中画已启动",
                      message: "屏幕角落会出现一个黑色小悬浮窗（属正常现象）。保持小窗显示即可在后台每 1.5 秒轮询并自动入库；若未立即出现，停留本页 1–2 秒会自动弹出。")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.buildModel(); self?.tableView.reloadData()
        }
        buildModel(); tableView.reloadData()
    }

    @objc private func toggleCloud(_ s: UISwitch) {
        AppGroupConfig.sharedDefaults?.set(s.isOn, forKey: AppGroupConfig.DefaultsKey.iCloudSyncEnabled)
        if s.isOn {
            if ICloudSyncManager.shared.isAvailable {
                ICloudSyncManager.shared.syncDown { [weak self] in self?.showAlert(title: "已同步", message: "iCloud 记录已合并到本地") }
            } else {
                s.isOn = false
                AppGroupConfig.sharedDefaults?.set(false, forKey: AppGroupConfig.DefaultsKey.iCloudSyncEnabled)
                showAlert(title: "iCloud 不可用", message: "请在系统设置中登录 iCloud 并为本 App 开启 iCloud 能力")
            }
        }
    }

    // MARK: - Actions

    private func syncNow() {
        ICloudSyncManager.shared.syncDown { [weak self] in
            DispatchQueue.main.async { self?.showAlert(title: "同步完成", message: "已合并云端记录") }
        }
    }

    private func purgeNow() {
        let days = AppGroupConfig.sharedDefaults?.integer(forKey: AppGroupConfig.DefaultsKey.autoDeleteDays) ?? 7
        ClipStore.shared.purgeOldRecords(days: max(days, 1))
        showAlert(title: "已清理", message: "已删除 \(max(days, 1)) 天前的未置顶记录")
    }

    private func showAutoDeletePicker() {
        let alert = UIAlertController(title: "自动清理", message: "选择保留时长（置顶记录不受影响）", preferredStyle: .actionSheet)
        for (days, title) in [(0, "关闭"), (7, "7 天"), (30, "30 天"), (90, "90 天"), (365, "1 年")] {
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                AppGroupConfig.sharedDefaults?.set(days, forKey: AppGroupConfig.DefaultsKey.autoDeleteDays)
                self?.buildModel(); self?.tableView.reloadData()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        present(alert, animated: true)
    }

    private func showMaxRecordPicker() {
        let alert = UIAlertController(title: "最大记录条数", message: "超出后自动删除最旧的未置顶记录", preferredStyle: .actionSheet)
        for count in [200, 500, 1000, 2000, 5000] {
            alert.addAction(UIAlertAction(title: "\(count) 条", style: .default) { [weak self] _ in
                AppGroupConfig.sharedDefaults?.set(count, forKey: AppGroupConfig.DefaultsKey.maxRecordCount)
                self?.buildModel(); self?.tableView.reloadData()
            })
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.popoverPresentationController?.sourceView = view
        present(alert, animated: true)
    }

    private func showClearConfirmation() {
        let alert = UIAlertController(title: "清除全部历史", message: "此操作不可恢复，确定继续？", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { [weak self] _ in
            ClipStore.shared.clearAll()
            self?.showAlert(title: "已清除", message: "全部历史记录已删除")
        })
        present(alert, animated: true)
    }

    private func showTagManager() {
        let vc = TagManagerViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showOnboarding() {
        let vc = OnboardingViewController()
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true) { [weak self, weak vc] in
            vc?.onFinish = { self?.buildModel(); self?.tableView.reloadData() }
        }
    }

    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好的", style: .default))
        present(alert, animated: true)
    }
}
