//
//  KeyboardViewController.swift
//  ClipboardKeyboard
//
//  自定义键盘扩展 v2.0：搜索 / 置顶 / 类型筛选 / 唤起即同步
//

import UIKit
import ClipKit

final class KeyboardViewController: UIInputViewController {

    // MARK: - UI

    private lazy var headerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .secondarySystemBackground
        return view
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "剪贴历史"
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.textColor = .secondaryLabel
        return label
    }()

    private lazy var searchButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(systemName: "magnifyingglass"), for: .normal)
        btn.tintColor = .label
        btn.addTarget(self, action: #selector(toggleSearch), for: .touchUpInside)
        return btn
    }()

    private lazy var dismissButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(systemName: "keyboard.chevron.compact.down"), for: .normal)
        btn.tintColor = .label
        btn.addTarget(self, action: #selector(handleDismiss), for: .touchUpInside)
        return btn
    }()

    private lazy var switchKeyboardButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.setImage(UIImage(systemName: "globe"), for: .normal)
        btn.tintColor = .label
        btn.addTarget(self, action: #selector(handleSwitchKeyboard), for: .touchUpInside)
        return btn
    }()

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

    /// 类型筛选分段控件
    private lazy var scope: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["全部", "文本", "链接", "图片"])
        sc.translatesAutoresizingMaskIntoConstraints = false
        sc.selectedSegmentIndex = 0
        sc.addTarget(self, action: #selector(scopeChanged), for: .valueChanged)
        sc.isHidden = true
        return sc
    }()

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.delegate = self
        tv.dataSource = self
        tv.register(KeyboardHistoryCell.self, forCellReuseIdentifier: KeyboardHistoryCell.reuseID)
        tv.rowHeight = 52
        tv.separatorInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        tv.backgroundColor = .systemBackground
        return tv
    }()

    private lazy var emptyLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = "暂无历史记录"
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 14)
        label.textAlignment = .center
        label.isHidden = true
        return label
    }()

    /// 未开启「完全访问」时的引导遮罩
    private lazy var noAccessView = KeyboardAccessGuideView(openSettings: { [weak self] in
        self?.openHostSettings()
    })

    // MARK: - 布局约束（搜索展开/收起时切换）

    private var headerHeight: NSLayoutConstraint!
    private var tableTopToHeader: NSLayoutConstraint!
    private var tableTopToScope: NSLayoutConstraint!

    // MARK: - Data

    private var allItems: [ClipItem] = []
    private var visibleItems: [ClipItem] = []
    private var keyword = ""
    private var scopeType: ClipContentType?

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
        reloadData()
    }

    // MARK: - UI Setup

    private func setupUI() {
        view.backgroundColor = .systemBackground

        view.addSubview(headerView)
        headerView.addSubview(dismissButton)
        headerView.addSubview(titleLabel)
        headerView.addSubview(searchButton)
        headerView.addSubview(switchKeyboardButton)
        view.addSubview(searchBar)
        view.addSubview(scope)
        view.addSubview(tableView)
        view.addSubview(emptyLabel)

        noAccessView.translatesAutoresizingMaskIntoConstraints = false
        noAccessView.isHidden = true
        view.addSubview(noAccessView)

        headerHeight = headerView.heightAnchor.constraint(equalToConstant: 40)
        tableTopToHeader = tableView.topAnchor.constraint(equalTo: headerView.bottomAnchor)
        tableTopToScope = tableView.topAnchor.constraint(equalTo: scope.bottomAnchor, constant: 4)
        tableTopToScope.isActive = false

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: view.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            headerHeight,

            dismissButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            dismissButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 32),
            dismissButton.heightAnchor.constraint(equalToConstant: 32),

            titleLabel.centerXAnchor.constraint(equalTo: headerView.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            searchButton.trailingAnchor.constraint(equalTo: switchKeyboardButton.leadingAnchor, constant: -4),
            searchButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            searchButton.widthAnchor.constraint(equalToConstant: 32),
            searchButton.heightAnchor.constraint(equalToConstant: 32),

            switchKeyboardButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            switchKeyboardButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            switchKeyboardButton.widthAnchor.constraint(equalToConstant: 32),
            switchKeyboardButton.heightAnchor.constraint(equalToConstant: 32),

            searchBar.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 4),
            searchBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            searchBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            searchBar.heightAnchor.constraint(equalToConstant: 34),

            scope.topAnchor.constraint(equalTo: searchBar.bottomAnchor, constant: 4),
            scope.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scope.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scope.heightAnchor.constraint(equalToConstant: 28),

            tableTopToHeader,
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 20),

            noAccessView.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            noAccessView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            noAccessView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            noAccessView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Sync

    private func performKeyboardSync() {
        let granted = hasFullAccess
        // 上报心跳，供主 App 判断键盘是否已启用并授权
        RuntimeEnvironment.shared.reportKeyboardHeartbeat(fullAccess: granted)
        noAccessView.isHidden = granted
        tableView.isHidden = !granted
        guard granted else {
            titleLabel.text = "请开启完全访问"
            titleLabel.textColor = .systemOrange
            return
        }
        titleLabel.text = "剪贴历史"
        titleLabel.textColor = .secondaryLabel
        _ = PasteboardSync.shared.performSync(sourceApp: "keyboard")
        ClipStore.shared.reloadSync()
    }

    /// 键盘扩展内跳转宿主设置（需完全访问；沿响应链找到能 openURL 的对象）
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
        emptyLabel.text = keyword.isEmpty ? "暂无历史记录" : "没有匹配记录"
        tableView.reloadData()
    }

    // MARK: - Actions

    @objc private func toggleSearch() {
        let show = searchBar.isHidden
        searchBar.isHidden = false
        scope.isHidden = false
        UIView.animate(withDuration: 0.22) {
            self.searchBar.alpha = show ? 1 : 0
            self.scope.alpha = show ? 1 : 0
            self.tableTopToHeader.isActive = !show
            self.tableTopToScope.isActive = show
            self.view.layoutIfNeeded()
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

    private func insertItem(_ item: ClipItem) {
        PasteboardSync.shared.writeToPasteboard(item)
        switch item.type {
        case .text, .url, .color, .other:
            if let text = item.text { textDocumentProxy.insertText(text) }
        case .image:
            showToast("已复制图片")
        }
        HapticHelper.tap()
    }

    private func showToast(_ message: String) {
        let toast = UILabel()
        toast.text = message
        toast.textColor = .white
        toast.backgroundColor = UIColor.label.withAlphaComponent(0.8)
        toast.font = .systemFont(ofSize: 13, weight: .medium)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 16
        toast.clipsToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            toast.widthAnchor.constraint(equalToConstant: 140),
            toast.heightAnchor.constraint(equalToConstant: 32)
        ])
        toast.alpha = 0
        UIView.animate(withDuration: 0.2, animations: { toast.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.3, delay: 0.8, options: [], animations: { toast.alpha = 0 }) { _ in
                toast.removeFromSuperview()
            }
        }
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
        insertItem(visibleItems[indexPath.row])
    }
}
