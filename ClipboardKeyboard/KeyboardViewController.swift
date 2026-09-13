//
//  KeyboardViewController.swift
//  ClipboardKeyboard
//
//  自定义键盘扩展 v2.3
//  - 与系统键盘等高（heightAnchor 固定，空数据也不塌陷），iPhone / iPad 自适应
//  - 唤起即双向同步，列表直接展示历史，点按一键复制并插入
//  - 毛玻璃原生键盘观感；正常浏览/复制路径绝不跳转宿主 App
//

import UIKit
import ClipKit

final class KeyboardViewController: UIInputViewController {

    // MARK: - 高度（与官方键盘等高，任何状态都不塌陷）

    private var heightConstraint: NSLayoutConstraint?
    private var currentHeight: CGFloat = 0

    /// 按设备与方向给出与系统键盘一致的高度
    private func desiredKeyboardHeight() -> CGFloat {
        let idiom = UIDevice.current.userInterfaceIdiom
        let size = view.window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        let landscape = size.width > size.height
        if idiom == .pad {
            return landscape ? 264 : 320   // iPad 官方键盘高度
        } else {
            return landscape ? 204 : 291   // iPhone 竖屏 291（含候选条）
        }
    }

    private func installKeyboardHeight() {
        let h = desiredKeyboardHeight()
        guard view.bounds.width > 0 else { return }
        guard abs(h - currentHeight) > 0.5 || heightConstraint == nil else { return }
        currentHeight = h
        if let c = heightConstraint { c.constant = h } else {
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

    // MARK: - 工具栏

    private lazy var toolbar = UIView()

    private lazy var titleLabel: UILabel = {
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

    // MARK: - 列表

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.delegate = self; tv.dataSource = self
        tv.register(KeyboardHistoryCell.self, forCellReuseIdentifier: KeyboardHistoryCell.reuseID)
        tv.estimatedRowHeight = 58
        tv.rowHeight = UITableView.automaticDimension
        tv.separatorStyle = .none
        tv.backgroundColor = .clear
        tv.contentInset = UIEdgeInsets(top: 2, left: 0, bottom: 8, right: 0)
        tv.keyboardDismissMode = .none
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
        // 去掉 iPad 顶部系统撤销/重做/粘贴助理条，避免与自定义 UI 重叠
        inputAssistantItem.leadingBarButtonGroups = []
        inputAssistantItem.trailingBarButtonGroups = []
        setupUI()
        NotificationCenter.default.addObserver(
            self, selector: #selector(clipboardChanged),
            name: UIPasteboard.changedNotification, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        syncAndReload()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        installKeyboardHeight()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
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

        view.addSubview(blurView)
        let c = blurView.contentView
        c.addSubview(toolbar)
        toolbar.addSubview(globeButton); toolbar.addSubview(titleLabel)
        toolbar.addSubview(searchButton); toolbar.addSubview(dismissButton)
        c.addSubview(searchBar); c.addSubview(scope)
        c.addSubview(tableView); c.addSubview(emptyLabel)

        noAccessView.translatesAutoresizingMaskIntoConstraints = false
        noAccessView.isHidden = true
        c.addSubview(noAccessView)

        tableTopToToolbar = tableView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 2)
        tableTopToScope = tableView.topAnchor.constraint(equalTo: scope.bottomAnchor, constant: 6)
        tableTopToScope.isActive = false

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

            searchBar.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 4),
            searchBar.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -8),
            searchBar.heightAnchor.constraint(equalToConstant: 34),

            scope.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 6),
            scope.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 8),
            scope.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -8),
            scope.heightAnchor.constraint(equalToConstant: 30),

            tableTopToToolbar,
            tableView.leadingAnchor.constraint(equalTo: c.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: c.safeAreaLayoutGuide.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: c.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: c.centerYAnchor, constant: 16),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: c.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: c.trailingAnchor, constant: -24),

            noAccessView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            noAccessView.leadingAnchor.constraint(equalTo: c.leadingAnchor),
            noAccessView.trailingAnchor.constraint(equalTo: c.trailingAnchor),
            noAccessView.bottomAnchor.constraint(equalTo: c.bottomAnchor)
        ])
    }

    // MARK: - 数据

    private func syncAndReload() {
        let granted = hasFullAccess
        RuntimeEnvironment.shared.reportKeyboardHeartbeat(fullAccess: granted)
        noAccessView.isHidden = granted
        tableView.isHidden = !granted
        toolbar.isUserInteractionEnabled = granted
        titleLabel.text = granted ? "剪贴历史" : "开启完全访问"
        guard granted else { return }
        _ = PasteboardSync.shared.performSync(sourceApp: "keyboard")
        reloadData()
    }

    @objc private func clipboardChanged() {
        guard hasFullAccess else { return }
        _ = PasteboardSync.shared.performSync(sourceApp: "keyboard-notify")
        reloadData()
    }

    private func reloadData() {
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

    // MARK: - Actions

    @objc private func toggleSearch() {
        let show = searchBar.isHidden
        searchBar.isHidden = false; scope.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.searchBar.alpha = show ? 1 : 0
            self.scope.alpha = show ? 1 : 0
            self.tableTopToToolbar.isActive = !show
            self.tableTopToScope.isActive = show
            self.blurView.contentView.layoutIfNeeded()
        } completion: { _ in
            if !show {
                self.searchBar.isHidden = true; self.scope.isHidden = true
                self.searchBar.text = nil; self.keyword = ""
                self.applyFilter()
            } else { self.searchBar.becomeFirstResponder() }
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
            t.bottomAnchor.constraint(equalTo: blurView.contentView.safeAreaLayoutGuide.bottomAnchor, constant: -14),
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

    /// 仅未授权遮罩使用：沿响应链打开本 App 系统设置
    private func openHostSettings() {
        let sel = NSSelectorFromString("openURL:")
        var r: UIResponder? = self
        while let cur = r {
            if cur.responds(to: sel) {
                _ = cur.perform(sel, with: URL(string: UIApplication.openSettingsURLString))
                return
            }
            r = cur.next
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
        return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { [weak self] _ in
            let insert = UIAction(title: "复制并插入", image: UIImage(systemName: "text.cursor")) { _ in self?.copyAndInsert(item) }
            let copy = UIAction(title: "仅复制", image: UIImage(systemName: "doc.on.doc")) { _ in self?.copyOnly(item) }
            return UIMenu(title: "", children: [insert, copy])
        }
    }
}
