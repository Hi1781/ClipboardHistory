//
//  NotificationViewController.swift
//  ClipboardNotify
//
//  路径3 的「读取端」：用户下拉本地通知时，系统拉起本内容扩展。
//  扩展被唤起的瞬间读取剪贴板 → 经 ClipKit 入库 → 在通知卡片内展示。
//

import UIKit
import UserNotifications
import UserNotificationsUI
import ClipKit

@objc(NotificationViewController)
final class NotificationViewController: UIViewController, UNNotificationContentExtension {

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 15, weight: .semibold)
        l.textColor = .label
        l.numberOfLines = 1
        return l
    }()

    private let bodyLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 14)
        l.textColor = .secondaryLabel
        l.numberOfLines = 0
        return l
    }()

    private let iconView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)
        iv.tintColor = .systemBlue
        return iv
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.addSubview(iconView)
        view.addSubview(titleLabel)
        view.addSubview(bodyLabel)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            iconView.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 14),

            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            bodyLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -14)
        ])
    }

    func didReceive(_ notification: UNNotification) {
        titleLabel.text = notification.request.content.title
        // 被系统拉起时执行一次真正的读取入库
        let result = PasteboardSync.shared.performSync(sourceApp: "notify-content")
        switch result {
        case .imported(let item):
            iconView.image = UIImage(systemName: item.type.symbolName)
            bodyLabel.text = "已保存：" + item.previewText
        case .alreadyExists:
            if let latest = ClipStore.shared.fetchLatest() {
                iconView.image = UIImage(systemName: latest.type.symbolName)
                bodyLabel.text = latest.previewText
            } else {
                bodyLabel.text = notification.request.content.body
            }
        default:
            bodyLabel.text = notification.request.content.body
        }
    }
}
