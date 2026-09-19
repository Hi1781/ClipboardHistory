//
//  KeyboardViewController.swift
//  ClipboardKeyboard
//
//  自定义键盘扩展 v2.7（全面重构，iPhone / iPad 适配）
//  - 与系统官方键盘严格等高：分设备类型/方向的常量 + 安全区，多时机重算，空数据也不塌陷
//  - iPad：清掉系统撤销/重做助理条，regular 宽度下内容居中限宽，避免超宽行
//  - 唤起即重开共享连接读取最新历史，点按一键复制并插入，长按弹出完整菜单
//  - 正常浏览/复制绝不跳转宿主；仅长按菜单「在 App 中编辑」与未授权「去设置」会 openURL
//

import UIKit
import ClipKit

final class KeyboardViewController: UIInputViewController {

    // MARK: - 高度（与官方键盘等高，任何状态都不塌陷）

    private var heightConstraint: NSLayoutConstraint?
    private var lastAppliedHeight: CGFloat = 0

    /// 与系统键盘等高的总高度（含底部 Home 指示条区域），按设备类型/方向取常量。
    /// 现代全面屏 iPhone 竖屏约 336–342、横屏约 211；非全面屏 260/271、横屏 162；
    /// iPad 竖屏 313/324、横屏 253/270（12.9 寸略高）。
    private func desiredKeyboardHeight() -> CGFloat {
        let idiom = UIDevice.current.userInterfaceIdiom
        let screen = view.window?.windowScene?.screen.bounds ?? UIScreen.main.bounds
        let landscape = screen.width > screen.height
        let longSide = max(screen.width, screen.height)

        if idiom == .pad {
            // iPad 全宽键盘高度；12.9 寸（长边 1366）略高
            let isLarge = longSide >= 1366
            return landscape ? (isLarge ? 270 : 253) : (isLarge ? 324 : 313)
        } else {
            // 全面屏（长边 >= 812，含刘海 / Home 指示条）
            let isModern = longSide >= 812
            if isModern {
                if landscape { return 211 }
                return longSide >= 900 ? 342 : 336
            } else {
                if landscape { return 162 }
                return longSide >= 736 ? 271 : 260
            }
        }
    }

    /// 安装 / 更新高度约束（priority 999，避免与系统旋转临时约束冲突）
    private func installKeyboardHeight() {
        guard view.bounds.width > 0 else { return }
        let h = desiredKeyboardHeight()
        guard abs(h - lastAppliedHeight) > 0.5 || heightConstraint == nil else { return }
        lastAppliedHeight = h
        if let c = heightConstraint {
            c.constant = h
        } else {
            let c = view.heightAnchor.constraint(equalToConstant: h)
            c.priority = UILayoutPriority(999)
            c.isActive = true
            heightConstraint = c
        }
    }

    // MARK: - 背景毛玻璃

    private lazy var blurView: UIVisualEffectView = {
        let v = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
        v.translatesAutoresizingMaskIntoConstraints = false
        v.contentView.backgroundColor = .clear
        return v
    }()

    /// iPad 上把功能内容限制在居中的可读宽度内
    private let bodyContainer = UIView()

    // MARK: - 工具栏

    private let toolbar = UIView()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.text = "剪贴历史"
        l.font = .systemFont(ofSize: 15, weight: .semibold)
        l.textColor = .label
        return l
    }()

    private func makeCapsule(_ symbol: String, _ action: Selector) -> UIButton {
        var cfg = UIButton.Configuration.gray()
        cfg.cornerStyle = .capsule
        cfg.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        cfg.buttonSize = .small
        let b = UIButton(configuration: cfg)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.setImage(UIImage(systemName: symbol), for: .normal)
        b.tintColor = .label
        b.addTarget(self, action: action, for: .touchUpInside)
        return b
    }

    private lazy var globeButton = makeCapsule("globe", #selector(handleSwitchKeyboard))
    private lazy var dismissButton = makeCapsule("keyboard.chevron.compact.down", #selector(handleDismiss))
    private lazy var searchButton = makeCapsule("magnifyingglass", #selector(toggleSearch))

    private lazy var searchBar: UISearchTextField = {
        let tf = UISearchTextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.placeholder = "搜索历史"
        tf.font = .systemFont(ofSize: 14)
        tf.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        tf.isHidden = true; tf.alpha = 0
        return tf
    }()

    private lazy var scope: UISegmentedControl = {
        let s = UISegmentedControl(items: ["全部", "文本", "链接", "图片"])
        s.translatesAutoresizingMaskIntoConstraints = false
        s.selectedSegmentIndex = 0
        s.addTarget(self, action: #selector(scopeChanged), for: .valueChanged)
        s.isHidden = true; s.alpha = 0
        return s
    }()

    // MARK: - 列表 / 空态 / 未授权

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.delegate = self; tv.dataSource = self
        tv.register(KeyboardHistoryCell.self, forCellReuseIdentifier: KeyboardHistoryCell.reuseID)
        tv.estimatedRowHeight = 60
        tv.rowHeight = UITableView.automaticDimension
        tv.separatorStyle = .none
        tv.backgroundColor = .clear
        tv.contentInset = UIEdgeInsets(top: 2, left: 0, bottom: 6, right: 0)
        tv.keyboardDismissMode = .none
        tv.showsVerticalScrollIndicator = true
        return tv
    }()

    private lazy var emptyLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.text = "暂无历史记录\n复制内容后再次唤起键盘即可看到"
        l.textColor = .secondaryLabel
        l.font = .systemFont(ofSize: 14)
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()

    private lazy var noAccessView = KeyboardAccessGuideView(openSettings: { [weak self] in
        self?.openHostSettings()
    })

    // MARK: - 约束 / 数据

    private var tableTopToToolbar: NSLayoutConstraint!
    private var tableTopToScope: NSLayoutConstraint!
    private var storedItems: [ClipItem] = []
    private var transientItems: [ClipItem] = []   // 共享库为空时用当前剪贴板兜底
    private var visibleItems: [ClipItem] = []
    private var keyword = ""
    private var scopeType: ClipContentType?

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        // iPad：去掉顶部系统撤销/重做/粘贴助理条，避免挤压高度或与自定义 UI 重叠
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        setupUI()
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipboardChanged),
            name: UIPasteboard.changedNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        installKeyboardHeight()
        syncAndReload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installKeyboardHeight()
        // hasFullAccess 此刻已稳定，补一次心跳，避免早期 false 漏报
        RuntimeEnvironment.shared.reportKeyboardHeartbeat(fullAccess: hasFullAccess)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        installKeyboardHeight()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        installKeyboardHeight()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in self.installKeyboardHeight() }
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .clear
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        bodyContainer.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(blurView)
        let c = blurView.contentView

        // 工具栏全宽
        c.addSubview(toolbar)
        toolbar.addSubview(globeButton); toolbar.addSubview(titleLabel)
        toolbar.addSubview(searchButton); toolbar.addSubview(dismissButton)

        // 功能内容放进居中限宽容器
        c.addSubview(bodyContainer)
        bodyContainer.addSubview(searchBar); bodyContainer.addSubview(scope)
        bodyContainer.addSubview(tableView); bodyContainer.addSubview(emptyLabel)

        noAccessView.translatesAutoresizingMaskIntoConstraints = false
        noAccessView.isHidden = true
        bodyContainer.addSubview(noAccessView)

        tableTopToToolbar = tableView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 2)
        tableTopToScope = tableView.topAnchor.constraint(equalTo: scope.bottomAnchor, constant: 6)
        tableTopToScope.isActive = false

        // body 水平约束：手机填满、iPad 居中限宽（等宽约束用 defaultHigh，可被 760 上限收窄）
        let bodyLead = bodyContainer.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 8)
        let bodyTrail = bodyContainer.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -8)
        bodyLead.priority = .defaultHigh
        bodyTrail.priority = .defaultHigh

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            toolbar.topAnchor.constraint(equalTo: c.topAnchor, constant: 4),
            toolbar.leadingAnchor.constraint(equalTo: c.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 40),

            globeButton.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 8),
            globeButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            globeButton.widthAnchor.constraint(equalToConstant: 38),
            globeButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerXAnchor.constraint(equalTo: toolbar.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),

            dismissButton.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -8),
            dismissButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 38),
            dismissButton.heightAnchor.constraint(equalToConstant: 32),

            searchButton.trailingAnchor.constraint(equalTo: dismissButton.leadingAnchor, constant: -6),
            searchButton.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: 38),
            searchButton.heightAnchor.constraint(equalToConstant: 32),

            // body 容器：竖向铺满工具栏以下；水平居中
            bodyContainer.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            bodyContainer.bottomAnchor.constraint(equalTo: c.bottomAnchor),
            bodyContainer.centerXAnchor.constraint(equalTo: c.centerXAnchor),
            bodyLead, bodyTrail,
            bodyContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 760),

            searchBar.topAnchor.constraint(equalTo: bodyContainer.topAnchor, constant: 4),
            searchBar.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            searchBar.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            searchBar.heightAnchor.constraint(equalToConstant: 34),

            scope.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 6),
            scope.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            scope.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            scope.heightAnchor.constraint(equalToConstant: 30),

            tableTopToToolbar,
            tableView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: bodyContainer.safeAreaLayoutGuide.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: bodyContainer.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: bodyContainer.centerYAnchor, constant: 10),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: bodyContainer.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: bodyContainer.trailingAnchor, constant: -24),

            noAccessView.topAnchor.constraint(equalTo: bodyContainer.topAnchor),
            noAccessView.leadingAnchor.constraint(equalTo: bodyContainer.leadingAnchor),
            noAccessView.trailingAnchor.constraint(equalTo: bodyContainer.trailingAnchor),
            noAccessView.bottomAnchor.constraint(equalTo: bodyContainer.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    // MARK: - 数据

    private func syncAndReload() {
        let granted = hasFullAccess
        RuntimeEnvironment.shared.reportKeyboardHeartbeat(fullAccess: granted)
        noAccessView.isHidden = granted
        tableView.isHidden = !granted
        searchButton.isEnabled = granted
        titleLabel.text = granted ? "剪贴历史" : "开启完全访问"
        guard granted else {
            storedItems = []; transientItems = []; visibleItems = []
            tableView.reloadData()
            return
        }
        _ = PasteboardSync.shared.performSync(sourceApp: "keyboard")
        reloadData()
    }

    @objc private func clipboardChanged() {
        guard hasFullAccess else { return }
        _ = PasteboardSync.shared.performSync(sourceApp: "keyboard-notify")
        reloadData()
    }

    private func reloadData() {
        // 重开共享连接，确保拿到主 App 进程最新落盘数据
        ClipStore.shared.reloadSync()
        storedItems = ClipStore.shared.fetchAll()
        // 兜底：共享库为空时把当前剪贴板作为临时条目，保证键盘里始终有可复制项
        transientItems = storedItems.isEmpty ? (currentPasteboardItem().map { [$0] } ?? []) : []
        applyFilter()
    }

    private func currentPasteboardItem() -> ClipItem? {
        let pb = UIPasteboard.general
        if pb.hasImages, let img = pb.image { return ClipItem.makeImage(img, sourceApp: "current") }
        if pb.hasURLs, let u = pb.url { return ClipItem.makeText(u.absoluteString, sourceApp: "current") }
        if pb.hasStrings, let s = pb.string, !s.isEmpty { return ClipItem.makeText(s, sourceApp: "current") }
        return nil
    }

    private func applyFilter() {
        var result = transientItems + storedItems
        if let t = scopeType { result = result.filter { $0.type == t } }
        if !keyword.isEmpty {
            let k = keyword.lowercased()
            result = result.filter { $0.searchableText.lowercased().contains(k) }
        }
        result = result.filter { !$0.isSensitive }
        visibleItems = result
        emptyLabel.isHidden = !visibleItems.isEmpty
        tableView.reloadData()
    }

    // MARK: - 工具按钮

    @objc private func toggleSearch() {
        let show = searchBar.isHidden
        searchBar.isHidden = false; scope.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.searchBar.alpha = show ? 1 : 0
            self.scope.alpha = show ? 1 : 0
            self.tableTopToToolbar.isActive = !show
            self.tableTopToScope.isActive = show
            self.blurView.contentView.layoutIfNeeded()
        } completion: { [weak self] _ in
            guard let self else { return }
            if !show {
                self.searchBar.isHidden = true; self.scope.isHidden = true
                self.searchBar.text = nil; self.keyword = ""
                self.applyFilter()
            } else {
                self.searchBar.becomeFirstResponder()
            }
        }
    }

    @objc private func searchChanged() { keyword = searchBar.text ?? ""; applyFilter() }

    @objc private func scopeChanged() {
        switch scope.selectedSegmentIndex {
        case 1: scopeType = .text
        case 2: scopeType = .url
        case 3: scopeType = .image
        default: scopeType = nil
        }
        applyFilter()
    }

    @objc private func handleDismiss() { dismissKeyboard() }
    @objc private func handleSwitchKeyboard() { advanceToNextInputMode() }

    // MARK: - 复制 / 插入（不跳转 App）

    private func copyAndInsert(_ item: ClipItem) {
        PasteboardSync.shared.writeToPasteboard(item)
        switch item.type {
        case .text, .url, .color, .other:
            if let text = item.text {
                textDocumentProxy.insertText(text)
                showToast("已复制并插入")
            } else { showToast("已复制") }
        case .image: showToast("图片已复制，到输入框长按粘贴")
        }
        HapticHelper.tap()
    }

    private func copyOnly(_ item: ClipItem) {
        PasteboardSync.shared.writeToPasteboard(item)
        HapticHelper.tap(); showToast("已复制")
    }

    private var toastWorkItem: DispatchWorkItem?
    private func showToast(_ message: String) {
        toastWorkItem?.cancel()
        let t = UILabel()
        t.text = message; t.textColor = .white
        t.backgroundColor = UIColor.label.withAlphaComponent(0.82)
        t.font = .systemFont(ofSize: 13, weight: .medium)
        t.textAlignment = .center
        t.layer.cornerRadius = 16; t.layer.cornerCurve = .continuous; t.clipsToBounds = true
        t.translatesAutoresizingMaskIntoConstraints = false; t.alpha = 0
        blurView.contentView.addSubview(t)
        NSLayoutConstraint.activate([
            t.centerXAnchor.constraint(equalTo: blurView.contentView.centerXAnchor),
            t.bottomAnchor.constraint(equalTo: blurView.contentView.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            t.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            t.heightAnchor.constraint(equalToConstant: 32)
        ])
        UIView.animate(withDuration: 0.18) { t.alpha = 1 }
        let w = DispatchWorkItem {
            UIView.animate(withDuration: 0.25) { t.alpha = 0 } completion: { _ in t.removeFromSuperview() }
        }
        toastWorkItem = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: w)
    }

    // MARK: - 长按菜单动作

    private func deleteItem(_ item: ClipItem) {
        ClipStore.shared.delete(id: item.id)
        HapticHelper.warning()
        reloadData()
        showToast("已删除")
    }

    /// 仅长按菜单「在 App 中编辑」：沿响应链 openURL 跳转主 App
    private func openEditorInHostApp(id: UUID) {
        guard let url = URL(string: "clipboardhistory://edit/\(id.uuidString)") else { return }
        performOpenURL(url)
    }

    /// 仅未授权遮罩使用：打开本 App 系统设置
    private func openHostSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        performOpenURL(url)
    }

    /// 键盘扩展没有 UIApplication.shared，沿 responder 链找到能 openURL: 的对象
    private func performOpenURL(_ url: URL) {
        let sel = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let cur = responder {
            if cur.responds(to: sel) {
                _ = cur.perform(sel, with: url)
                return
            }
            responder = cur.next
        }
    }
}

extension KeyboardViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { visibleItems.count }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: KeyboardHistoryCell.reuseID, for: indexPath) as! KeyboardHistoryCell
        cell.configure(with: visibleItems[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        copyAndInsert(visibleItems[indexPath.row])
    }

    func tableView(_ tableView: UITableView,
                   contextMenuConfigurationForRowAt indexPath: IndexPath,
                   point: CGPoint) -> UIContextMenuConfiguration? {
        let item = visibleItems[indexPath.row]
        let isStored = storedItems.contains(where: { $0.id == item.id })
        return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { [weak self] _ in
            let insert = UIAction(title: "复制并插入", image: UIImage(systemName: "text.cursor")) { _ in self?.copyAndInsert(item) }
            let copy = UIAction(title: "仅复制", image: UIImage(systemName: "doc.on.doc")) { _ in self?.copyOnly(item) }
            var children: [UIMenuElement] = [insert, copy]
            if isStored, item.text != nil {
                let edit = UIAction(title: "在 App 中编辑", image: UIImage(systemName: "square.and.pencil")) { _ in
                    self?.openEditorInHostApp(id: item.id)
                }
                children.append(edit)
            }
            if isStored {
                let delete = UIAction(title: "删除", image: UIImage(systemName: "trash"),
                                      attributes: .destructive) { _ in self?.deleteItem(item) }
                children.append(UIMenu(options: .displayInline, children: [delete]))
            }
            return UIMenu(title: "", children: children)
        }
    }
}
