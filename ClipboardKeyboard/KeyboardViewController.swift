//
//  KeyboardViewController.swift
//  ClipboardKeyboard
//
//  自定义键盘扩展 v2.2
//  - 唤起即双向同步，列表直接展示历史，点按一键复制并插入
//  - 毛玻璃原生键盘观感，适配最新 iOS 风格与 iPhone / iPad
//  - 正常浏览/复制路径绝不跳转宿主 App；仅「未授权遮罩」可去系统设置
//

import UIKit
import ClipKit

final class KeyboardViewController: UIInputViewController {

    // MARK: - 背景毛玻璃（贴合系统键盘材质）

    private lazy var blurView: UIVisualEffectView = {
        let effect = UIBlurEffect(style: .systemChromeMaterial)
        let v = UIVisualEffectView(effect: effect)
        v.translatesAutoresizingMaskIntoConstraints = false
        v.contentView.backgroundColor = .clear
        return v
    }()

    // MARK: - 顶部工具栏

    private lazy var toolbar: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        return v
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "剪贴历史"
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        return label
    }()

    private func makeCapsuleButton(_ symbol: String, action: Selector) -> UIButton {
        var cfg = UIButton.Configuration.gray()
        cfg.cornerStyle = .capsule
        cfg.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        cfg.buttonSize = .small
        let btn = UIButton(configuration: cfg)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(systemName: symbol), for: .normal)
        btn.tintColor = .label
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    private lazy var globeButton = makeCapsuleButton("globe", action: #selector(handleSwitchKeyboard))
    private lazy var dismissButton = makeCapsuleButton("keyboard.chevron.compact.down", action: #selector(handleDismiss))
    private lazy var searchButton = makeCapsuleButton("magnifyingglass", action: #selector(toggleSearch))

    private lazy var searchBar: UISearchTextField = {
        let tf = UISearchTextField()
        tf.translatesAutoresizingMaskIntoConstraints = false
        tf.placeholder = "搜索历史"
        tf.font = .systemFont(ofSize: 14)
        tf.addTarget(self, action: #selector(searchChanged), for: .editingChanged)
        tf.isHidden = true
        tf.alpha = 0
        return tf
    }()

    private lazy var scope: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["全部", "文本", "链接", "图片"])
        sc.translatesAutoresizingMaskIntoConstraints = false
        sc.selectedSegmentIndex = 0
        sc.addTarget(self, action: #selector(scopeChanged), for: .valueChanged)
        sc.isHidden = true
        sc.alpha = 0
        return sc
    }()

    // MARK: - 列表

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.delegate = self
        tv.dataSource = self
        tv.register(KeyboardHistoryCell.self, forCellReuseIdentifier: KeyboardHistoryCell.reuseID)
        tv.estimatedRowHeight = 60
        tv.rowHeight = UITableView.automaticDimension
        tv.separatorStyle = .none
        tv.backgroundColor = .clear
        tv.contentInset = UIEdgeInsets(top: 2, left: 0, bottom: 6, right: 0)
        tv.keyboardDismissMode = .none
        return tv
    }()

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "暂无历史记录"
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.isHidden = true
        return label
    }()

    /// 未开启「完全访问」时的引导遮罩（唯一可能跳设置的入口，与历史列表隔离）
    private lazy var noAccessView = KeyboardAccessGuideView(openSettings: { [weak self] in
        self?.openHostSettings()
    })

    // MARK: - 约束 / 数据

    private var tableTopToToolbar: NSLayoutConstraint!
    private var tableTopToScope: NSLayoutConstraint!
    private var allItems: [ClipItem] = []
    private var visibleItems: [ClipItem] = []
    private var keyword = ""
    private var scopeType: ClipContentType?
    private var didLayout = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        performKeyboardSync()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyKeyboardHeight()
        reloadData()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        applyKeyboardHeight()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .clear
        view.addSubview(blurView)
        blurView.contentView.addSubview(toolbar)
        toolbar.addSubview(globeButton)
        toolbar.addSubview(titleLabel)
        toolbar.addSubview(searchButton)
        toolbar.addSubview(dismissButton)
        blurView.contentView.addSubview(searchBar)
        blurView.contentView.addSubview(scope)
        blurView.contentView.addSubview(tableView)
        blurView.contentView.addSubview(emptyLabel)

        noAccessView.translatesAutoresizingMaskIntoConstraints = false
        noAccessView.isHidden = true
        blurView.contentView.addSubview(noAccessView)

        tableTopToToolbar = tableView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 2)
        tableTopToScope = tableView.topAnchor.constraint(equalTo: scope.bottomAnchor, constant: 6)
        tableTopToScope.isActive = false

        NSLayoutConstraint.activate([
            blurView.topAnchor.constraint(equalTo: view.topAnchor),
            blurView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            blurView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            blurView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            toolbar.topAnchor.constraint(equalTo: blurView.contentView.topAnchor, constant: 4),
            toolbar.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
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
            searchBar.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -8),
            searchBar.heightAnchor.constraint(equalToConstant: 34),

            scope.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 6),
            scope.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor, constant: 8),
            scope.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor, constant: -8),
            scope.heightAnchor.constraint(equalToConstant: 30),

            tableTopToToolbar,
            tableView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: blurView.contentView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: blurView.contentView.centerYAnchor, constant: 18),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: blurView.contentView.leadingAnchor, constant: 24),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: blurView.contentView.trailingAnchor, constant: -24),

            noAccessView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            noAccessView.leadingAnchor.constraint(equalTo: blurView.contentView.leadingAnchor),
            noAccessView.trailingAnchor.constraint(equalTo: blurView.contentView.trailingAnchor),
            noAccessView.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor)
        ])
    }

    /// iPhone / iPad 键盘高度自适应
    private func applyKeyboardHeight() {
        guard !didLayout || view.bounds.width > 0 else { return }
        didLayout = true
        let regular = traitCollection.horizontalSizeClass == .regular
        let height: CGFloat = regular ? 340 : 296
        preferredContentSize = CGSize(width: view.bounds.width, height: height)
    }

    // MARK: - 同步

    private func performKeyboardSync() {
        let granted = hasFullAccess
        RuntimeEnvironment.shared.reportKeyboardHeartbeat(fullAccess: granted)
        noAccessView.isHidden = granted
        tableView.isHidden = !granted
        toolbar.isUserInteractionEnabled = granted
        guard granted else {
            titleLabel.text = "开启完全访问"
            return
        }
        titleLabel.text = "剪贴历史"
        _ = PasteboardSync.shared.performSync(sourceApp: "keyboard")
        ClipStore.shared.reloadSync()
    }

    /// 仅「未授权遮罩」调用：沿响应链打开本 App 的系统设置
    private func openHostSettings() {
        let selector = NSSelectorFromString("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current.responds(to: selector) {
                _ = current.perform(selector, with: URL(string: UIApplication.openSettingsURLString))
                return
            }
            responder = current.next
        }
    }

    private func reloadData() {
        allItems = ClipStore.shared.fetchAll()
        applyFilter()
    }

    private func applyFilter() {
        var filter = ClipFilter(keyword: keyword, type: scopeType)
        filter.includeSensitive = false
        visibleItems = ClipStore.shared.fetch(filter: filter)
        emptyLabel.isHidden = !visibleItems.isEmpty
        emptyLabel.text = keyword.isEmpty ? "暂无历史记录\n唤起键盘会自动同步剪贴板" : "没有匹配记录"
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func toggleSearch() {
        let show = searchBar.isHidden
        searchBar.isHidden = false
        scope.isHidden = false
        UIView.animate(withDuration: 0.2) {
            self.searchBar.alpha = show ? 1 : 0
            self.scope.alpha = show ? 1 : 0
            self.tableTopToToolbar.isActive = !show
            self.tableTopToScope.isActive = show
            self.blurView.contentView.layoutIfNeeded()
        } completion: { _ in
            if !show {
                self.searchBar.isHidden = true
                self.scope.isHidden = true
                self.searchBar.text = nil
                self.keyword = ""
                self.applyFilter()
            } else {
                self.searchBar.becomeFirstResponder()
            }
        }
    }

    @objc private func searchChanged() {
        keyword = searchBar.text ?? ""
        applyFilter()
    }

    @objc private func scopeChanged() {
        switch scope.selectedSegmentIndex {
        case 1: scopeType = .text
        case 2: scopeType = .url
        case 3: scopeType = .image
        default: scopeType = nil
        }
        applyFilter()
    }

    @objc private func handleDismiss() { super.dismissKeyboard() }
    @objc private func handleSwitchKeyboard() { advanceToNextInputMode() }

    // MARK: - 复制 / 插入（均不跳转 App）

    /// 一键复制：写入剪贴板；文本同时插入当前输入框
    private func copyAndInsert(_ item: ClipItem) {
        PasteboardSync.shared.writeToPasteboard(item)
        switch item.type {
        case .text, .url, .color, .other:
            if let text = item.text {
                textDocumentProxy.insertText(text)
                showToast("已复制并插入")
            } else {
                showToast("已复制")
            }
        case .image:
            showToast("图片已复制")
        }
        HapticHelper.tap()
    }

    /// 仅复制，不插入
    private func copyOnly(_ item: ClipItem) {
        PasteboardSync.shared.writeToPasteboard(item)
        HapticHelper.tap()
        showToast("已复制")
    }

    private var toastWorkItem: DispatchWorkItem?
    private func showToast(_ message: String) {
        toastWorkItem?.cancel()
        let toast = UILabel()
        toast.text = message
        toast.textColor = .white
        toast.backgroundColor = UIColor.label.withAlphaComponent(0.82)
        toast.font = .systemFont(ofSize: 13, weight: .medium)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 16
        toast.layer.cornerCurve = .continuous
        toast.clipsToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.alpha = 0
        blurView.contentView.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: blurView.contentView.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: blurView.contentView.bottomAnchor, constant: -18),
            toast.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            toast.heightAnchor.constraint(equalToConstant: 32)
        ])
        UIView.animate(withDuration: 0.18) { toast.alpha = 1 }
        let work = DispatchWorkItem {
            UIView.animate(withDuration: 0.25) { toast.alpha = 0 } completion: { _ in toast.removeFromSuperview() }
        }
        toastWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }
}

// MARK: - DataSource & Delegate

extension KeyboardViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: KeyboardHistoryCell.reuseID, for: indexPath) as! KeyboardHistoryCell
        cell.configure(with: visibleItems[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        copyAndInsert(visibleItems[indexPath.row])
    }

    /// 长按菜单：复制并插入 / 仅复制（都不跳转）
    func tableView(_ tableView: UITableView,
                   contextMenuConfigurationForRowAt indexPath: IndexPath,
                   point: CGPoint) -> UIContextMenuConfiguration? {
        let item = visibleItems[indexPath.row]
        return UIContextMenuConfiguration(identifier: indexPath as NSCopying, previewProvider: nil) { [weak self] _ in
            let insert = UIAction(title: "复制并插入", image: UIImage(systemName: "text.cursor")) { _ in
                self?.copyAndInsert(item)
            }
            let copy = UIAction(title: "仅复制", image: UIImage(systemName: "doc.on.doc")) { _ in
                self?.copyOnly(item)
            }
            return UIMenu(title: "", children: [insert, copy])
        }
    }
}
