//
//  TagManagerViewController.swift
//  ClipboardHistory
//
//  v1.2：标签管理（查看使用次数、删除标签）
//

import UIKit
import ClipKit

final class TagManagerViewController: UITableViewController {

    private var tags: [String] = []

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "标签管理"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "tag")
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tags = ClipStore.shared.allTags()
        tableView.reloadData()
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        tags.isEmpty ? nil : "全部标签（点击移除，记录本身不会删除）"
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(tags.count, 1)
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "tag", for: indexPath)
        if tags.isEmpty {
            cell.textLabel?.text = "暂无标签，长按记录即可添加"
            cell.textLabel?.textColor = .secondaryLabel
            cell.imageView?.image = nil
        } else {
            let tag = tags[indexPath.row]
            let count = ClipStore.shared.fetchAll().filter { $0.tags.contains(tag) }.count
            cell.textLabel?.text = "# \(tag)"
            cell.textLabel?.textColor = .label
            cell.detailTextLabel?.text = "\(count) 条"
            cell.imageView?.image = UIImage(systemName: "tag")
            cell.imageView?.tintColor = .systemIndigo
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard !tags.isEmpty else { return }
        let tag = tags[indexPath.row]
        let alert = UIAlertController(title: "移除标签「\(tag)」", message: "将从所有记录中移除该标签，不删除记录", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "移除", style: .destructive) { [weak self] _ in
            let all = ClipStore.shared.fetchAll()
            for item in all where item.tags.contains(tag) {
                ClipStore.shared.setTags(id: item.id, tags: item.tags.filter { $0 != tag })
            }
            self?.tags = ClipStore.shared.allTags()
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
    }
}
