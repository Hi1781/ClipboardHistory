//
//  HistoryTextCell.swift
//  ClipboardHistory
//
//  文本类剪贴记录 Cell（v2.0：置顶标识 / 标签）
//

import UIKit
import ClipKit

final class HistoryTextCell: UITableViewCell {
    static let reuseID = "HistoryTextCell"

    /// 点击右侧箭头的回调（与点整行复制区分开）
    var onTapAccessory: (() -> Void)?

    private lazy var accessoryButton: UIButton = {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: "chevron.right",
                           withConfiguration: UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)),
                   for: .normal)
        b.tintColor = .tertiaryLabel
        b.frame = CGRect(x: 0, y: 0, width: 44, height: 44)   // 放大点击热区
        b.contentHorizontalAlignment = .right
        b.addTarget(self, action: #selector(accessoryTapped), for: .touchUpInside)
        return b
    }()

    @objc private func accessoryTapped() { onTapAccessory?() }

    private let previewLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.textColor = .label
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
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

    private let typeIcon: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .secondaryLabel
        iv.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        return iv
    }()

    private let pinIcon: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .systemIndigo
        iv.image = UIImage(systemName: "pin.fill")
        iv.isHidden = true
        iv.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        return iv
    }()

    private let tagLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11)
        label.textColor = .systemIndigo
        label.isHidden = true
        return label
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupLayout() {
        accessoryView = accessoryButton
        contentView.addSubview(typeIcon)
        contentView.addSubview(previewLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(pinIcon)
        contentView.addSubview(tagLabel)

        NSLayoutConstraint.activate([
            typeIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            typeIcon.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            typeIcon.widthAnchor.constraint(equalToConstant: 20),
            typeIcon.heightAnchor.constraint(equalToConstant: 20),

            previewLabel.leadingAnchor.constraint(equalTo: typeIcon.trailingAnchor, constant: 12),
            previewLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            previewLabel.trailingAnchor.constraint(lessThanOrEqualTo: timeLabel.leadingAnchor, constant: -8),

            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            timeLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 64),

            pinIcon.leadingAnchor.constraint(equalTo: previewLabel.leadingAnchor),
            pinIcon.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 4),
            pinIcon.widthAnchor.constraint(equalToConstant: 12),
            pinIcon.heightAnchor.constraint(equalToConstant: 12),

            tagLabel.leadingAnchor.constraint(equalTo: pinIcon.trailingAnchor, constant: 4),
            tagLabel.centerYAnchor.constraint(equalTo: pinIcon.centerYAnchor),
            tagLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    func configure(with item: ClipItem) {
        previewLabel.text = item.previewText
        timeLabel.text = item.timeString
        pinIcon.isHidden = !item.isPinned

        if item.tags.isEmpty {
            tagLabel.isHidden = true
        } else {
            tagLabel.isHidden = false
            tagLabel.text = item.tags.prefix(3).map { "#\($0)" }.joined(separator: " ")
        }

        switch item.type {
        case .url:
            typeIcon.image = UIImage(systemName: "link")
            previewLabel.textColor = .systemBlue
        case .color:
            typeIcon.image = UIImage(systemName: "paintpalette")
            previewLabel.textColor = .label
        default:
            typeIcon.image = UIImage(systemName: item.type.symbolName)
            previewLabel.textColor = .label
        }
    }
}
