//
//  ClipTextEditorViewController.swift
//  ClipboardHistory
//
//  v2.4：点词条右侧箭头弹出的文本编辑窗口
//  - 「保存」：用编辑后的内容原地替换原词条（保留 id / 标签 / 置顶）
//  - 「另存为」：把编辑后的内容作为一条全新记录加入，原词条保留
//

import UIKit
import ClipKit

final class ClipTextEditorViewController: UIViewController {

    private let original: ClipItem
    private let onReplace: (String) -> Void
    private let onSaveAs: (String) -> Void

    private let textView: UITextView = {
        let tv = UITextView()
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.font = .systemFont(ofSize: 16)
        tv.textColor = .label
        tv.backgroundColor = .secondarySystemBackground
        tv.layer.cornerRadius = 12
        tv.layer.cornerCurve = .continuous
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 10, bottom: 12, right: 10)
        tv.autocorrectionType = .no
        tv.smartDashesType = .no
        tv.smartQuotesType = .no
        tv.alwaysBounceVertical = true
        return tv
    }()

    private let counterLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.font = .systemFont(ofSize: 12)
        l.textColor = .secondaryLabel
        return l
    }()

    private lazy var saveAsButton: UIButton = {
        var cfg = UIButton.Configuration.bordered()
        cfg.cornerStyle = .large
        cfg.title = "另存为新词条"
        cfg.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        cfg.image = UIImage(systemName: "doc.badge.plus")
        cfg.imagePadding = 6
        let b = UIButton(configuration: cfg)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(saveAsTapped), for: .touchUpInside)
        return b
    }()

    private lazy var replaceButton: UIButton = {
        var cfg = UIButton.Configuration.filled()
        cfg.cornerStyle = .large
        cfg.title = "保存（替换原词条）"
        cfg.baseBackgroundColor = .systemIndigo
        cfg.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        cfg.image = UIImage(systemName: "square.and.arrow.down")
        cfg.imagePadding = 6
        let b = UIButton(configuration: cfg)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.addTarget(self, action: #selector(replaceTapped), for: .touchUpInside)
        return b
    }()

    private let buttonBar = UIView()

    init(item: ClipItem,
         onReplace: @escaping (String) -> Void,
         onSaveAs: @escaping (String) -> Void) {
        self.original = item
        self.onReplace = onReplace
        self.onSaveAs = onSaveAs
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
        if let sheet = sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "编辑文本"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))

        textView.text = original.text ?? original.previewText
        NotificationCenter.default.addObserver(
            self, selector: #selector(textChanged),
            name: UITextView.textDidChangeNotification, object: textView)

        buttonBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView); view.addSubview(counterLabel)
        view.addSubview(buttonBar)
        buttonBar.addSubview(saveAsButton); buttonBar.addSubview(replaceButton)

        let guide = view.safeAreaLayoutGuide
        // iOS16 键盘布局向导：键盘弹出时按钮条自动上移
        let kbGuide = view.keyboardLayoutGuide
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            counterLabel.topAnchor.constraint(equalTo: textView.bottomAnchor, constant: 8),
            counterLabel.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 4),

            buttonBar.topAnchor.constraint(equalTo: counterLabel.bottomAnchor, constant: 10),
            buttonBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            buttonBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            buttonBar.bottomAnchor.constraint(equalTo: kbGuide.topAnchor, constant: -12),
            buttonBar.heightAnchor.constraint(equalToConstant: 50),

            saveAsButton.leadingAnchor.constraint(equalTo: buttonBar.leadingAnchor),
            saveAsButton.topAnchor.constraint(equalTo: buttonBar.topAnchor),
            saveAsButton.bottomAnchor.constraint(equalTo: buttonBar.bottomAnchor),

            replaceButton.trailingAnchor.constraint(equalTo: buttonBar.trailingAnchor),
            replaceButton.topAnchor.constraint(equalTo: buttonBar.topAnchor),
            replaceButton.bottomAnchor.constraint(equalTo: buttonBar.bottomAnchor),
            replaceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 190),
            saveAsButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 150)
        ])
        textChanged()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    @objc private func textChanged() {
        let n = textView.text.count
        counterLabel.text = "\(n) 字"
        let trimmed = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = trimmed != (original.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        replaceButton.isEnabled = !trimmed.isEmpty && changed
        saveAsButton.isEnabled = !trimmed.isEmpty
        replaceButton.alpha = replaceButton.isEnabled ? 1 : 0.45
    }

    @objc private func cancelTapped() { dismiss(animated: true) }

    @objc private func replaceTapped() {
        let value = textView.text ?? ""
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onReplace(value)
        dismiss(animated: true)
    }

    @objc private func saveAsTapped() {
        let value = textView.text ?? ""
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSaveAs(value)
        dismiss(animated: true)
    }
}
