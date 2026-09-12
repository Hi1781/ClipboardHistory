//
//  KeyboardHistoryCell.swift
//  ClipboardKeyboard
//
//  键盘内历史记录 Cell（v2.0：置顶标识）
//

import UIKit
import ClipKit

final class KeyboardHistoryCell: UITableViewCell {
    static let reuseID = "KeyboardHistoryCell"

    private let previewLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let timeLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabel
        label.textAlignment = .right
        return label
    }()

    private let typeIcon: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .secondaryLabel
        return iv
    }()

    private let thumbnailView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 4
        iv.isHidden = true
        return iv
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
        backgroundColor = .clear
        contentView.addSubview(typeIcon)
        contentView.addSubview(thumbnailView)
        contentView.addSubview(previewLabel)
        contentView.addSubview(timeLabel)
        contentView.addSubview(pinIcon)

        NSLayoutConstraint.activate([
            typeIcon.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            typeIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            typeIcon.widthAnchor.constraint(equalToConstant: 18),
            typeIcon.heightAnchor.constraint(equalToConstant: 18),

            thumbnailView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            thumbnailView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 36),
            thumbnailView.heightAnchor.constraint(equalToConstant: 36),

            previewLabel.leadingAnchor.constraint(equalTo: typeIcon.trailingAnchor, constant: 10),
            previewLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            previewLabel.trailingAnchor.constraint(lessThanOrEqualTo: pinIcon.leadingAnchor, constant: -6),

            pinIcon.trailingAnchor.constraint(equalTo: timeLabel.leadingAnchor, constant: -6),
            pinIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            pinIcon.widthAnchor.constraint(equalToConstant: 10),
            pinIcon.heightAnchor.constraint(equalToConstant: 10),

            timeLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            timeLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            timeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 46)
        ])
    }

    func configure(with item: ClipItem) {
        timeLabel.text = item.timeString
        pinIcon.isHidden = !item.isPinned

        if item.type == .image {
            typeIcon.isHidden = true
            thumbnailView.isHidden = false
            thumbnailView.image = item.image
            previewLabel.text = "[图片]"
            previewLabel.textColor = .label
        } else {
            typeIcon.isHidden = false
            thumbnailView.isHidden = true
            previewLabel.text = item.previewText
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
}
