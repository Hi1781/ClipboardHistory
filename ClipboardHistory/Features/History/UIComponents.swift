//
//  UIComponents.swift
//  ClipboardHistory
//
//  主界面复用 UI：标签筛选栏 / 空状态 / 同步横幅 / Toast
//

import UIKit

// MARK: - 标签横向筛选栏

final class TagFilterBar: UIView {
    var onSelectTag: ((String?) -> Void)?

    private let scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsHorizontalScrollIndicator = false
        sv.contentInset = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        return sv
    }()

    private let stackView: UIStackView = {
        let sv = UIStackView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.axis = .horizontal
        sv.spacing = 8
        sv.alignment = .center
        return sv
    }()

    private var tags: [String] = []
    private var selectedTag: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemGroupedBackground
        addSubview(scrollView)
        scrollView.addSubview(stackView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(tags: [String], selected: String?) {
        self.tags = tags
        self.selectedTag = selected
        rebuild()
        isHidden = tags.isEmpty && selected == nil
    }

    private func rebuild() {
        stackView.arrangedSubviews.forEach {
            stackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let all = chip(title: "全部", isSelected: selectedTag == nil)
        all.tag = -1
        stackView.addArrangedSubview(all)
        for (idx, tag) in tags.enumerated() {
            let chip = chip(title: "# \(tag)", isSelected: selectedTag == tag)
            chip.tag = idx
            stackView.addArrangedSubview(chip)
        }
    }

    private func chip(title: String, isSelected: Bool) -> UIButton {
        var config = UIButton.Configuration.tinted()
        config.title = title
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        let button = UIButton(configuration: config)
        button.tintColor = isSelected ? .systemIndigo : .systemGray
        button.addTarget(self, action: #selector(handleTap(_:)), for: .touchUpInside)
        return button
    }

    @objc private func handleTap(_ sender: UIButton) {
        if sender.tag == -1 {
            selectedTag = nil
            onSelectTag?(nil)
        } else {
            let tag = tags[sender.tag]
            selectedTag = (selectedTag == tag) ? nil : tag
            onSelectTag?(selectedTag)
        }
        rebuild()
    }
}

// MARK: - 空状态

final class EmptyStateView: UIView {
    private let iconView = UIImageView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        isHidden = true

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .secondaryLabel
        iconView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 44, weight: .regular)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = .secondaryLabel
        label.font = .systemFont(ofSize: 15)

        addSubview(iconView)
        addSubview(label)
        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -30),
            iconView.widthAnchor.constraint(equalToConstant: 56),
            iconView.heightAnchor.constraint(equalToConstant: 56),
            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 16),
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(icon: String, text: String) {
        iconView.image = UIImage(systemName: icon)
        label.text = text
    }
}

// MARK: - 同步横幅

final class SyncBanner: UIView {
    private let label = UILabel()
    private var hideWorkItem: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = UIColor.label.withAlphaComponent(0.85)
        layer.cornerRadius = 16
        clipsToBounds = true
        isHidden = true

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .systemBackground
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ text: String, in container: UIView) {
        if superview == nil {
            container.addSubview(self)
            centerXAnchor.constraint(equalTo: container.centerXAnchor).isActive = true
        }
        label.text = text
        alpha = 0
        isHidden = false
        hideWorkItem?.cancel()
        UIView.animate(withDuration: 0.2, animations: { self.alpha = 1 }) { [weak self] _ in
            let work = DispatchWorkItem {
                UIView.animate(withDuration: 0.3) { self?.alpha = 0 } completion: { _ in self?.isHidden = true }
            }
            self?.hideWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: work)
        }
    }
}

// MARK: - Toast

enum ToastView {
    static func show(_ message: String, in container: UIView) {
        let toast = UILabel()
        toast.text = message
        toast.textColor = .white
        toast.backgroundColor = UIColor.label.withAlphaComponent(0.85)
        toast.font = .systemFont(ofSize: 14, weight: .medium)
        toast.textAlignment = .center
        toast.layer.cornerRadius = 20
        toast.clipsToBounds = true
        toast.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            toast.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -72),
            toast.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            toast.heightAnchor.constraint(equalToConstant: 40)
        ])
        toast.alpha = 0
        UIView.animate(withDuration: 0.2, animations: { toast.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.3, delay: 1.0, options: [], animations: { toast.alpha = 0 }) { _ in
                toast.removeFromSuperview()
            }
        }
    }
}
