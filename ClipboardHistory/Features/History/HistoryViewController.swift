//
//  HistoryViewController.swift
//  ClipboardHistory
//
//  主界面（v2.0）：搜索 / 类型标签筛选 / 批量管理 / 置顶 / 长按预览
//

import UIKit
import ClipKit

final class HistoryViewController: UIViewController {

    // MARK: - UI

    private lazy var tableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .insetGrouped)
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.delegate = self
        tv.dataSource = self
        tv.register(HistoryTextCell.self, forCellReuseIdentifier: HistoryTextCell.reuseID)
        tv.register(HistoryImageCell.self, forCellReuseIdentifier: HistoryImageCell.reuseID)
        tv.rowHeight = UITableView.automaticDimension
        tv.estimatedRowHeight = 72
        tv.allowsMultipleSelectionDuringEditing = true
        tv.refreshControl = refreshControl
        return tv
    }()

    private lazy var searchController: UISearchController = {
        let sc = UISearchController(searchResultsController: nil)
        sc.searchResultsUpdater = self
        sc.obscuresBackgroundDuringPresentation = false
        sc.searchBar.placeholder = "搜索文本、链接、标签"
        sc.searchBar.scopeButtonTitles = ["全部", "文本", "链接", "图片"]
        sc.searchBar.delegate = self
        return sc
    }()

    /// 筛选胶囊栏（标签横向滚动）
    private lazy var tagBar: TagFilterBar = {
        let bar = TagFilterBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.onSelectTag = { [weak self] tag in
            self?.currentFilter.tag = tag
            self?.reloadData()
        }
        return bar
    }()

    private lazy var refreshControl: UIRefreshControl = {
        let rc = UIRefreshControl()
        rc.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        return rc
    }()

    private lazy var emptyStateView = EmptyStateView()

    private lazy var syncBanner: SyncBanner = SyncBanner()

    /// 批量管理底部工具栏
    private lazy var batchToolbar: UIToolbar = {
        let tb = UIToolbar()
        tb.translatesAutoresizingMaskIntoConstraints = false
        let pin = UIBarButtonItem(image: UIImage(systemName: "pin"), style: .plain, target: self, action: #selector(batchPin))
        let tag = UIBarButtonItem(image: UIImage(systemName: "tag"), style: .plain, target: self, action: #selector(batchTag))
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let delete = UIBarButtonItem(image: UIImage(systemName: "trash"), style: .plain, target: self, action: #selector(batchDelete))
        delete.tintColor = .systemRed
        tb.items = [pin, spacer, tag, spacer, delete]
        tb.isHidden = true
        return tb
    }()

    // MARK: - Data

    private var allItems: [ClipItem] = []
    private var visibleItems: [ClipItem] = []
    private var currentFilter = ClipFilter()
    private var selectedIDs = Set<UUID>()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigationBar()
        setupObservers()
        reloadData()
        runSyncOnLaunch()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ClipStore.shared.reloadSync()   // 拾取键盘扩展在另一进程写入的记录
        reloadData()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .systemGroupedBackground
        view.addSubview(tagBar)
        view.addSubview(tableView)
        view.addSubview(emptyStateView)
        view.addSubview(syncBanner)
        view.addSubview(batchToolbar)

        NSLayoutConstraint.activate([
            tagBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tagBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tagBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tagBar.heightAnchor.constraint(equalToConstant: 44),

            tableView.topAnchor.constraint(equalTo: tagBar.bottomAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            syncBanner.topAnchor.constraint(equalTo: tagBar.bottomAnchor, constant: 6),
            syncBanner.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            emptyStateView.topAnchor.constraint(equalTo: tagBar.bottomAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            batchToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            batchToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            batchToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            batchToolbar.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func setupNavigationBar() {
        title = "剪贴板"
        navigationController?.navigationBar.prefersLargeTitles = true
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        let selectItem = UIBarButtonItem(
            title: "管理",
            style: .plain,
            target: self,
            action: #selector(toggleBatchMode)
        )
        let settingsItem = UIBarButtonItem(
            image: UIImage(systemName: "gearshape"),
            style: .plain,
            target: self,
            action: #selector(openSettings)
        )
        navigationItem.leftBarButtonItem = selectItem
        navigationItem.rightBarButtonItem = settingsItem
    }

    private func setupObservers() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAppActive),
            name: .appDidBecomeActive, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleStoreChange),
            name: ClipStore.didChangeNotification, object: nil)
    }

    // MARK: - Data

    private func reloadData() {
        allItems = ClipStore.shared.fetchAll()
        tagBar.update(tags: ClipStore.shared.allTags(), selected: currentFilter.tag)
        applyFilter()
    }

    private func applyFilter() {
        visibleItems = ClipStore.shared.fetch(filter: currentFilter)
        emptyStateView.isHidden = !visibleItems.isEmpty
        if !currentFilter.keyword.isEmpty || currentFilter.type != nil || currentFilter.tag != nil {
            emptyStateView.configure(icon: "magnifyingglass",
                                     text: "没有匹配的记录\n换个关键词试试")
        } else {
            emptyStateView.configure(icon: "clipboard",
                                     text: "剪贴板历史为空\n复制内容后会自动出现在这里")
        }
        tableView.reloadData()
    }

    private func runSyncOnLaunch() {
        let result = PasteboardSync.shared.performSync()
        showSyncBanner(result: result)
        reloadData()
    }

    // MARK: - Actions

    @objc private func handleAppActive() {
        ClipStore.shared.reloadSync()
        let result = PasteboardSync.shared.performSync()
        showSyncBanner(result: result)
        reloadData()
    }

    @objc private func handleStoreChange() {
        reloadData()
    }

    @objc private func handleRefresh() {
        let result = PasteboardSync.shared.performSync()
        showSyncBanner(result: result)
        reloadData()
        refreshControl.endRefreshing()
    }

    @objc private func openSettings() {
        let settingsVC = SettingsViewController()
        let nav = UINavigationController(rootViewController: settingsVC)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    private func copyItem(_ item: ClipItem) {
        PasteboardSync.shared.writeToPasteboard(item)
        HapticHelper.copy()
        showToast("已复制")
    }

    // MARK: - 批量管理

    @objc private func toggleBatchMode() {
        let entering = !tableView.isEditing
        tableView.setEditing(entering, animated: true)
        selectedIDs.removeAll()
        navigationItem.leftBarButtonItem?.title = entering ? "完成" : "管理"
        navigationItem.rightBarButtonItem?.isEnabled = !entering
        searchController.searchBar.isUserInteractionEnabled = !entering
        // 为底部工具栏腾出空间，避免最后一行被遮挡
        UIView.animate(withDuration: 0.25) {
            self.batchToolbar.isHidden = !entering
            self.tableView.contentInset.bottom = entering ? 60 : 0
            self.tableView.verticalScrollIndicatorInsets.bottom = entering ? 60 : 0
        }
        if !entering { reloadData() }
    }

    @objc private func batchPin() {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        ids.forEach { ClipStore.shared.togglePinned(id: $0) }
        HapticHelper.success()
        showToast("已更新置顶")
    }

    @objc private func batchTag() {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        presentTagEditor(for: ids)
    }

    @objc private func batchDelete() {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        let alert = UIAlertController(title: "删除 \(ids.count) 条记录？", message: "此操作不可恢复", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "删除", style: .destructive) { [weak self] _ in
            ClipStore.shared.delete(ids: ids)
            self?.selectedIDs.removeAll()
            HapticHelper.warning()
            self?.reloadData()
        })
        present(alert, animated: true)
    }

    // MARK: - 标签编辑

    private func presentTagEditor(for ids: [UUID]) {
        let alert = UIAlertController(title: "添加标签", message: "多个标签用逗号分隔", preferredStyle: .alert)
        alert.addTextField { $0.placeholder = "例如：工作, 验证码" }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "保存", style: .default) { [weak self] _ in
            guard let text = alert.textFields?.first?.text else { return }
            let newTags = text.split(whereSeparator: { $0 == "," || $0 == "，" }).map(String.init)
            for id in ids {
                if let item = ClipStore.shared.item(id: id) {
                    let merged = Array(Set(item.tags + newTags))
                    ClipStore.shared.setTags(id: id, tags: merged)
                }
            }
            self?.reloadData()
        })
        present(alert, animated: true)
    }

    private func showSyncBanner(result: PasteboardSync.SyncResult) {
        switch result {
        case .imported: syncBanner.show("已导入剪贴板内容", in: view)
        case .restored: syncBanner.show("已回填最新历史记录", in: view)
        default: break
        }
    }

    private func showToast(_ message: String) {
        ToastView.show(message, in: view)
    }
}

// MARK: - DataSource & Delegate

extension HistoryViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        visibleItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = visibleItems[indexPath.row]
        if item.type == .image {
            let cell = tableView.dequeueReusableCell(withIdentifier: HistoryImageCell.reuseID, for: indexPath) as! HistoryImageCell
            cell.configure(with: item)
            cell.onTapAccessory = { [weak self] in self?.presentImagePreview(for: item) }
            return cell
        }
        let cell = tableView.dequeueReusableCell(withIdentifier: HistoryTextCell.reuseID, for: indexPath) as! HistoryTextCell
        cell.configure(with: item)
        cell.onTapAccessory = { [weak self] in self?.presentTextEditor(for: item) }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = visibleItems[indexPath.row]
        if tableView.isEditing {
            selectedIDs.insert(item.id)
            return
        }
        tableView.deselectRow(at: indexPath, animated: true)
        copyItem(item)
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            selectedIDs.remove(visibleItems[indexPath.row].id)
        }
    }

    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath)
    -> UISwipeActionsConfiguration? {
        guard !tableView.isEditing else { return nil }
        let item = visibleItems[indexPath.row]

        let delete = UIContextualAction(style: .destructive, title: "删除") { [weak self] _, _, completion in
            ClipStore.shared.delete(id: item.id)
            self?.reloadData()
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")

        let pin = UIContextualAction(style: .normal, title: item.isPinned ? "取消置顶" : "置顶") { [weak self] _, _, completion in
            ClipStore.shared.togglePinned(id: item.id)
            self?.reloadData()
            completion(true)
        }
        pin.backgroundColor = .systemIndigo
        pin.image = UIImage(systemName: item.isPinned ? "pin.slash" : "pin")

        let sensitive = UIContextualAction(style: .normal, title: item.isSensitive ? "取消敏感" : "敏感") { [weak self] _, _, completion in
            ClipStore.shared.toggleSensitive(id: item.id)
            self?.reloadData()
            completion(true)
        }
        sensitive.backgroundColor = .systemOrange
        sensitive.image = UIImage(systemName: item.isSensitive ? "eye.slash.fill" : "eye.slash")

        return UISwipeActionsConfiguration(actions: [delete, pin, sensitive])
    }

    func tableView(_ tableView: UITableView,
                   contextMenuConfigurationForRowAt indexPath: IndexPath,
                   point: CGPoint) -> UIContextMenuConfiguration? {
        guard !tableView.isEditing else { return nil }
        let item = visibleItems[indexPath.row]
        return UIContextMenuConfiguration(identifier: item.id.uuidString as NSString,
                                          previewProvider: { ClipPreviewViewController(item: item) }) { [weak self] _ in
            guard let self else { return UIMenu() }

            let copy = UIAction(title: "复制", image: UIImage(systemName: "doc.on.doc")) { _ in self.copyItem(item) }
            let pin = UIAction(title: item.isPinned ? "取消置顶" : "置顶",
                               image: UIImage(systemName: item.isPinned ? "pin.slash" : "pin")) { _ in
                ClipStore.shared.togglePinned(id: item.id); self.reloadData()
            }
            let tag = UIAction(title: "添加标签", image: UIImage(systemName: "tag")) { _ in
                self.presentTagEditor(for: [item.id])
            }
            let share = UIAction(title: "分享", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                self.shareItem(item)
            }
            let delete = UIAction(title: "删除", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                ClipStore.shared.delete(id: item.id); self.reloadData()
            }
            return UIMenu(children: [copy, pin, tag, share, delete])
        }
    }

    /// 点击预览后的动作：直接复制
    func tableView(_ tableView: UITableView,
                   willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
                   animator: UIContextMenuInteractionCommitAnimating) {
        guard let idString = configuration.identifier as? String,
              let id = UUID(uuidString: idString),
              let item = ClipStore.shared.item(id: id) else { return }
        animator.addCompletion { [weak self] in self?.copyItem(item) }
    }

    /// 供键盘扩展「在 App 中编辑」经 URL scheme 跳转调用
    func openItemForEditing(idString: String) {
        ClipStore.shared.reloadSync()
        guard let id = UUID(uuidString: idString),
              let item = ClipStore.shared.item(id: id), item.text != nil else { return }
        reloadData()
        if presentedViewController != nil {
            dismiss(animated: true) { self.presentTextEditor(for: item) }
        } else {
            presentTextEditor(for: item)
        }
    }

    /// 点右侧箭头：弹出文本编辑（保存替换 / 另存为新词条）
    func presentTextEditor(for item: ClipItem) {
        guard item.text != nil else { presentImagePreview(for: item); return }
        let editor = ClipTextEditorViewController(
            item: item,
            onReplace: { [weak self] edited in
                ClipStore.shared.replaceText(id: item.id, edited: edited)
                self?.reloadData()
                self?.showToast("已替换原词条")
            },
            onSaveAs: { [weak self] edited in
                let newItem = ClipItem.makeText(edited, sourceApp: "edited")
                ClipStore.shared.add(newItem)
                self?.reloadData()
                self?.showToast("已另存为新词条")
            })
        let nav = UINavigationController(rootViewController: editor)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    /// 点图片右侧箭头：查看大图
    private func presentImagePreview(for item: ClipItem) {
        let vc = ClipPreviewViewController(item: item)
        vc.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(dismissPresented))
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        present(nav, animated: true)
    }

    @objc private func dismissPresented() { dismiss(animated: true) }

    private func shareItem(_ item: ClipItem) {
        var activityItems: [Any] = []
        if let text = item.text { activityItems.append(text) }
        else if let image = item.image { activityItems.append(image) }
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = view
        present(vc, animated: true)
    }
}

// MARK: - 搜索

extension HistoryViewController: UISearchResultsUpdating, UISearchBarDelegate {
    func updateSearchResults(for searchController: UISearchController) {
        currentFilter.keyword = searchController.searchBar.text ?? ""
        applyFilter()
    }

    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {
        switch selectedScope {
        case 1: currentFilter.type = .text
        case 2: currentFilter.type = .url
        case 3: currentFilter.type = .image
        default: currentFilter.type = nil
        }
        applyFilter()
    }
}
