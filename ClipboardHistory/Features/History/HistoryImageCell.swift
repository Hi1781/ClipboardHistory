//
//  HistoryImageCell.swift
//  ClipboardHistory
//
//  图片类剪贴记录 Cell（v2.0：置顶标识）
//

import UIKit
import ClipKit

final class HistoryImageCell: UITableViewCell {
    static let reuseID = "HistoryImageCell"

    /// 点击右侧箭头的回调（图片为查看大图）
    var onTapAccessory: (() -> Void)?

    private lazy var accessoryButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "chevron.right",
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)),
                   for: .normal)
        b.tintColor = .tertiaryLabel
        b.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        b.contentHorizontalAlignment = .right
        b.addTarget(self, action: #selector(accessoryTapped), for: .touchUpInside)
        return b
    }()

    @objc private func accessoryTapped() { onTapAccessory?() }

    private let thumbnailView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 8
        iv.backgroundColor = .secondarySystemBackground
        return iv
    }()

    private let infoLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label
        label.text = "[图片]"
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        return label
    }()

    private let pinIcon: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .systemIndigo
        iv.image = UIImage(systemName: "pin.fill")
        iv.isHidden = true
        return iv
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupLayout() {
        accessoryView = accessoryButton
        contentView.addSubview(thumbnailView)
        contentView.addSubview(infoLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(pinIcon)

        NSLayoutConstraint.activate([
            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            thumbnailView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            thumbnailView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10),
            thumbnailView.widthAnchor.constraint(equalToConstant: 56),
            thumbnailView.heightAnchor.constraint(equalToConstant: 56),

            infoLabel.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 12),
            infoLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -8),

            pinIcon.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor, constant: 12),
            pinIcon.topAnchor.constraint(equalTo: infoLabel.bottomAnchor, constant: 6),
            pinIcon.widthAnchor.constraint(equalToConstant: 12),
            pinIcon.heightAnchor.constraint(equalToConstant: 12),

            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            timeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60)
        ])
    }

    func configure(with item: ClipItem) {
        thumbnailView.image = item.image
        timeLabel.text = item.timeString
        pinIcon.isHidden = !item.isPinned
        if let data = item.imageData {
            let kb = Double(data.count) / 1024.0
            if kb >= 1024 {
                infoLabel.text = String(format: "[图片] %.2f MB", kb / 1024.0)
            } else {
                infoLabel.text = String(format: "[图片] %.1f KB", kb)
            }
        }
    }
}
