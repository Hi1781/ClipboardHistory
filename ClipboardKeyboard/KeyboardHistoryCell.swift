//
//  KeyboardHistoryCell.swift
//  ClipboardKeyboard
//
//  键盘内历史记录卡片 Cell（v2.2：iOS 原生键盘风格、圆角卡片、一键复制标识）
//

import UIKit
import ClipKit

final class KeyboardHistoryCell: UITableViewCell {
    static let reuseID = "KeyboardHistoryCell"

    /// 卡片容器（做圆角与高亮）
    private let card: UIView = {
        let v = UIView()
        v.translatesAutoresizingMaskIntoConstraints = false
        v.backgroundColor = UIColor.secondarySystemBackground
        v.layer.cornerRadius = 12
        v.layer.cornerCurve = .continuous
        v.clipsToBounds = true
        return v
    }()

    private let previewLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .regular)
        label.textColor = .label
        label.numberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        return label
    }()

    private let metaLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .regular)
        label.textColor = .secondaryLabel
        return label
    }()

    private let typeIcon: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .systemBlue
        iv.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        return iv
    }()

    private let thumbnailView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = 8
        iv.layer.cornerCurve = .continuous
        iv.isHidden = true
        return iv
    }()

    private let copyGlyph: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .tertiaryLabel
        iv.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        iv.image = UIImage(systemName: "doc.on.doc")
        return iv
    }()

    private let pinIcon: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.contentMode = .scaleAspectFit
        iv.tintColor = .systemIndigo
        iv.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        iv.image = UIImage(systemName: "pin.fill")
        iv.isHidden = true
        return iv
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        selectionStyle = .none
        setupLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupLayout() {
        contentView.addSubview(card)
        card.addSubview(typeIcon)
        card.addSubview(thumbnailView)
        card.addSubview(previewLabel)
        card.addSubview(metaLabel)
        card.addSubview(pinIcon)
        card.addSubview(copyGlyph)

        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 3),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -3),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 10),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -10),

            typeIcon.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
            typeIcon.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            typeIcon.widthAnchor.constraint(equalToConstant: 20),
            typeIcon.heightAnchor.constraint(equalToConstant: 20),

            thumbnailView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            thumbnailView.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            thumbnailView.widthAnchor.constraint(equalToConstant: 40),
            thumbnailView.heightAnchor.constraint(equalToConstant: 40),

            previewLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 9),
            previewLabel.leadingAnchor.constraint(equalTo: typeIcon.trailingAnchor, constant: 10),
            previewLabel.trailingAnchor.constraint(equalTo: copyGlyph.leadingAnchor, constant: -8),

            metaLabel.topAnchor.constraint(equalTo: previewLabel.bottomAnchor, constant: 3),
            metaLabel.leadingAnchor.constraint(equalTo: previewLabel.leadingAnchor),
            metaLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -9),

            pinIcon.centerYAnchor.constraint(equalTo: metaLabel.centerYAnchor),
            pinIcon.leadingAnchor.constraint(equalTo: metaLabel.trailingAnchor, constant: 5),
            pinIcon.widthAnchor.constraint(equalToConstant: 10),
            pinIcon.heightAnchor.constraint(equalToConstant: 10),

            copyGlyph.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            copyGlyph.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            copyGlyph.widthAnchor.constraint(equalToConstant: 20),
            copyGlyph.heightAnchor.constraint(equalToConstant: 20)
        ])
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        let transform: () -> Void = {
            self.card.backgroundColor = highlighted
                ? UIColor.systemFill : UIColor.secondarySystemBackground
            self.card.transform = highlighted ? CGAffineTransform(scaleX: 0.985, y: 0.985) : .identity
        }
        if animated { UIView.animate(withDuration: 0.12, animations: transform) } else { transform() }
    }

    func configure(with item: ClipItem) {
        metaLabel.text = item.timeString + " · " + item.type.displayName
        pinIcon.isHidden = !item.isPinned

        if item.type == .image {
            typeIcon.isHidden = true
            thumbnailView.isHidden = false
            thumbnailView.image = item.image
            previewLabel.text = "[图片] 点按复制"
        } else {
            typeIcon.isHidden = false
            thumbnailView.isHidden = true
            previewLabel.text = item.previewText
            typeIcon.image = UIImage(systemName: item.type.symbolName)
        }
    }
}
