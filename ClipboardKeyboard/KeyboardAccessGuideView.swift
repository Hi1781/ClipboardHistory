//
//  KeyboardAccessGuideView.swift
//  ClipboardKeyboard
//
//  v2.1：键盘未授予「允许完全访问」时的引导视图
//

import UIKit

final class KeyboardAccessGuideView: UIView {

    private let openSettings: () -> Void

    init(openSettings: @escaping () -> Void) {
        self.openSettings = openSettings
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        setup()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .leading

        let icon = UIImageView(image: UIImage(systemName: "lock.trianglebadge.exclamationmark"))
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = .systemOrange
        icon.contentMode = .scaleAspectFit
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        icon.image = UIImage(systemName: "lock.trianglebadge.exclamationmark", withConfiguration: iconConfig)

        let title = UILabel()
        title.text = "需要开启完全访问"
        title.font = .systemFont(ofSize: 16, weight: .bold)
        title.textColor = .label

        let steps: [(String, String)] = [
            ("1", "设置 → 通用 → 键盘"),
            ("2", "键盘 → 剪贴板"),
            ("3", "打开「允许完全访问」")
        ]
        let stepStack = UIStackView()
        stepStack.axis = .vertical
        stepStack.spacing = 6
        steps.forEach { num, text in
            stepStack.addArrangedSubview(Self.stepRow(num: num, text: text))
        }

        let note = UILabel()
        note.text = "仅用于在键盘与 App 间共享本地历史，数据不上传。"
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0

        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle("去设置", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        button.backgroundColor = .systemIndigo
        button.tintColor = .white
        button.layer.cornerRadius = 10
        button.contentEdgeInsets = UIEdgeInsets(top: 9, left: 20, bottom: 9, right: 20)
        button.addTarget(self, action: #selector(tapped), for: .touchUpInside)

        addSubview(stack)
        [icon, title, stepStack, note, button].forEach { stack.addArrangedSubview($0) }
        stack.setCustomSpacing(14, after: icon)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            button.heightAnchor.constraint(equalToConstant: 40)
        ])
    }

    @objc private func tapped() { openSettings() }

    private static func stepRow(num: String, text: String) -> UIView {
        let badge = UILabel()
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.text = num
        badge.font = .systemFont(ofSize: 12, weight: .bold)
        badge.textColor = .white
        badge.backgroundColor = .systemIndigo
        badge.textAlignment = .center
        badge.layer.cornerRadius = 11
        badge.clipsToBounds = true
        badge.widthAnchor.constraint(equalToConstant: 22).isActive = true
        badge.heightAnchor.constraint(equalToConstant: 22).isActive = true

        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 14)
        label.textColor = .label

        let row = UIStackView(arrangedSubviews: [badge, label])
        row.spacing = 10
        row.alignment = .center
        return row
    }
}
