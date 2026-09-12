//
//  ClipPreviewViewController.swift
//  ClipboardHistory
//
//  v1.1：长按 / 上下文菜单全屏预览（文本可滚动、图片可缩放）
//

import UIKit
import ClipKit

final class ClipPreviewViewController: UIViewController {

    private let item: ClipItem
    private let scrollView = UIScrollView()
    private let contentLabel = UILabel()
    private let imageView = UIImageView()

    init(item: ClipItem) {
        self.item = item
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = CGSize(width: 360, height: 480)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setup()
    }

    private func setup() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        switch item.type {
        case .image:
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.contentMode = .scaleAspectFit
            imageView.image = item.image
            scrollView.addSubview(imageView)
        default:
            contentLabel.translatesAutoresizingMaskIntoConstraints = false
            contentLabel.numberOfLines = 0
            contentLabel.font = .systemFont(ofSize: 16)
            contentLabel.textColor = .label
            contentLabel.text = item.text ?? item.previewText
            scrollView.addSubview(contentLabel)
        }

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])

        if item.type == .image {
            NSLayoutConstraint.activate([
                imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                contentLabel.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
                contentLabel.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
                contentLabel.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
                contentLabel.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
                contentLabel.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
            ])
        }

        // 顶部信息
        let meta = "\(item.type.displayName) · \(ClipItem.formatted(item.timestamp))"
        navigationItem.title = meta
    }
}
