//
//  OnboardingViewController.swift
//  ClipboardHistory
//
//  v2.1：首次启动 / 设置内可重复查看的「权限与使用引导」
//  原生分页（UIPageViewController），随运行环境（标准安装 / LiveContainer）动态生成。
//

import UIKit
import ClipKit

// MARK: - 单页内容模型

private struct GuidePage {
    let icon: String
    let tint: UIColor
    let title: String
    let sections: [GuideSection]

    enum GuideSection {
        case bullet(String)          // 普通要点
        case step(Int, String)       // 编号步骤
        case status(String, Bool)    // 状态行（标题，是否正常）
        case note(String)            // 灰色说明
    }
}

// MARK: - 单页视图控制器

private final class GuidePageViewController: UIViewController {
    private let page: GuidePage

    private lazy var scrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.translatesAutoresizingMaskIntoConstraints = false
        sv.showsVerticalScrollIndicator = true
        sv.alwaysBounceVertical = true
        return sv
    }()

    private lazy var iconView: UIImageView = {
        let iv = UIImageView()
        iv.translatesAutoresizingMaskIntoConstraints = false
        let config = UIImage.SymbolConfiguration(pointSize: 46, weight: .regular)
        iv.image = UIImage(systemName: page.icon, withConfiguration: config)
        iv.tintColor = page.tint
        iv.contentMode = .scaleAspectFit
        return iv
    }()

    private lazy var titleLabel: UILabel = {
        let l = UILabel()
        l.translatesAutoresizingMaskIntoConstraints = false
        l.text = page.title
        l.font = .systemFont(ofSize: 26, weight: .bold)
        l.textColor = .label
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()

    private let stack: UIStackView = {
        let s = UIStackView()
        s.translatesAutoresizingMaskIntoConstraints = false
        s.axis = .vertical
        s.spacing = 12
        s.alignment = .fill
        return s
    }()

    /// 点击「去设置」回调
    var openSettingsHandler: (() -> Void)?

    init(page: GuidePage) {
        self.page = page
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        view.addSubview(scrollView)
        scrollView.addSubview(iconView)
        scrollView.addSubview(titleLabel)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            iconView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 24),
            iconView.centerXAnchor.constraint(equalTo: scrollView.frameLayoutGuide.centerXAnchor),
            iconView.heightAnchor.constraint(equalToConstant: 60),
            iconView.widthAnchor.constraint(equalToConstant: 60),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -28),

            stack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24)
        ])
        buildSections()
    }

    private func makeCard() -> UIView {
        let card = UIView()
        card.backgroundColor = .secondarySystemGroupedBackground
        card.layer.cornerRadius = 14
        card.layer.cornerCurve = .continuous
        return card
    }

    private func buildSections() {
        for section in page.sections {
            switch section {
            case .bullet(let text):
                stack.addArrangedSubview(row(icon: "checkmark.circle.fill", iconColor: .systemGreen, text: text))
            case .step(let index, let text):
                stack.addArrangedSubview(row(icon: "\(index).circle.fill", iconColor: .systemIndigo, text: text))
            case .status(let text, let ok):
                stack.addArrangedSubview(row(icon: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                                             iconColor: ok ? .systemGreen : .systemOrange, text: text))
            case .note(let text):
                let l = UILabel()
                l.text = text
                l.font = .systemFont(ofSize: 13)
                l.textColor = .secondaryLabel
                l.numberOfLines = 0
                let wrap = UIStackView(arrangedSubviews: [l])
                wrap.isLayoutMarginsRelativeArrangement = true
                wrap.layoutMargins = UIEdgeInsets(top: 0, left: 6, bottom: 0, right: 6)
                stack.addArrangedSubview(wrap)
            }
        }

        // 需要跳转系统设置的页面（键盘、后台）提供按钮
        let needsButton = page.title.contains("键盘") || page.title.contains("后台")
        if needsButton {
            let btn = UIButton(type: .system)
            btn.setTitle("打开系统设置", for: .normal)
            btn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
            btn.backgroundColor = .systemIndigo
            btn.tintColor = .white
            btn.layer.cornerRadius = 12
            btn.layer.cornerCurve = .continuous
            btn.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
            btn.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
            btn.heightAnchor.constraint(equalToConstant: 48).isActive = true
            stack.addArrangedSubview(btn)
        }
    }

    private func row(icon: String, iconColor: UIColor, text: String) -> UIView {
        let card = makeCard()
        let iv = UIImageView(image: UIImage(systemName: icon))
        iv.translatesAutoresizingMaskIntoConstraints = false
        iv.tintColor = iconColor
        iv.contentMode = .scaleAspectFit
        iv.setContentHuggingPriority(.required, for: .horizontal)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = text
        label.font = .systemFont(ofSize: 15)
        label.textColor = .label
        label.numberOfLines = 0

        card.addSubview(iv)
        card.addSubview(label)
        NSLayoutConstraint.activate([
            iv.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
            iv.topAnchor.constraint(greaterThanOrEqualTo: card.topAnchor, constant: 14),
            iv.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -14),
            iv.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iv.widthAnchor.constraint(equalToConstant: 22),
            iv.heightAnchor.constraint(equalToConstant: 22),

            label.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
            label.topAnchor.constraint(equalTo: card.topAnchor, constant: 13),
            label.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -13)
        ])
        return card
    }

    @objc private func openSettings() {
        openSettingsHandler?()
    }
}

// MARK: - 引导容器

final class OnboardingViewController: UIViewController {
    private var pages: [UIViewController] = []
    private var pageVC: UIPageViewController!
    private let pageControl = UIPageControl()
    private let nextButton = UIButton(type: .system)
    private let skipButton = UIButton(type: .system)

    /// 完成（含跳过）回调
    var onFinish: (() -> Void)?

    private var currentIndex: Int = 0 {
        didSet { updateChrome() }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        buildPages()
        setupPageController()
        setupChrome()
    }

    // MARK: 页面装配

    private func buildPages() {
        let env = RuntimeEnvironment.shared
        var models: [GuidePage] = []

        // 1. 欢迎与核心用法
        models.append(GuidePage(icon: "clipboard.fill", tint: .systemIndigo, title: "剪贴板历史", sections: [
            .bullet("进入 App 或唤起键盘时：剪贴板有新内容会自动入库"),
            .bullet("若剪贴板为空，可自动回填最新一条记录（可在设置开启）"),
            .bullet("主界面上下滑动即可翻找全部历史，支持搜索、置顶、标签"),
            .note("当前运行模式：\(env.modeDisplayName)")
        ]))

        if env.systemExtensionsAvailable {
            // 2. 标准安装：键盘扩展引导
            let activated = env.keyboardEverActivated
            models.append(GuidePage(icon: "keyboard", tint: .systemIndigo, title: "开启键盘扩展", sections: [
                .step(1, "打开「设置 → 通用 → 键盘 → 键盘」"),
                .step(2, "点「添加新键盘」，选择「剪贴板」"),
                .step(3, "选中后打开「允许完全访问」（读写共享历史所必需）"),
                .status(activated ? "已检测到键盘成功运行" : "尚未检测到键盘运行，按上面步骤开启", activated),
                .note("完全访问仅用于在键盘与 App 间共享本地历史，数据不会上传。")
            ]))
        } else {
            // 2'. LiveContainer：扩展不可用说明
            models.append(GuidePage(icon: "shippingbox.fill", tint: .systemOrange, title: "容器模式说明", sections: [
                .status("运行在 LiveContainer 容器内", true),
                .bullet("受系统限制，容器内无法注册键盘扩展与桌面小组件"),
                .bullet("请直接在 LiveContainer 中打开本 App 使用全部历史功能"),
                .bullet("数据保存在当前容器内，删除容器会一并删除数据"),
                .note("如需系统级键盘，请改用 SideStore/AltStore 直接安装本 IPA。")
            ]))
        }

        // 3. 粘贴权限
        models.append(GuidePage(icon: "doc.on.clipboard", tint: .systemBlue, title: "粘贴权限", sections: [
            .bullet("iOS 16 起，App 读取剪贴板会弹出「允许粘贴」提示"),
            .bullet("选择「允许」即可自动导入；该授权系统会记住选择"),
            .bullet("仅比较计数时不读取内容，不会频繁弹窗"),
            .note("所有内容仅保存在本机，SQLite 字段级 AES-256 加密。")
        ]))

        // 4. 后台刷新（可选）
        if env.systemExtensionsAvailable {
            let bgOK = UIApplication.shared.backgroundRefreshStatus == .available
            models.append(GuidePage(icon: "arrow.triangle.2.circlepath", tint: .systemTeal, title: "后台刷新（可选）", sections: [
                .step(1, "「设置 → 通用 → 后台 App 刷新」打开总开关"),
                .step(2, "在本 App 设置中开启「后台监听」"),
                .status(bgOK ? "系统后台刷新当前可用" : "后台刷新当前关闭，按步骤开启", bgOK),
                .note("iOS 不允许任何 App 常驻后台静默读取剪贴板，后台仅由系统调度附加刷新。")
            ]))
        }

        // 5. 完成
        models.append(GuidePage(icon: "checkmark.circle.fill", tint: .systemGreen, title: "准备就绪", sections: [
            .bullet("复制任意内容，再回到这里即可看到它出现在列表顶部"),
            .bullet("可随时在「设置」中重新查看本引导、调整同步与清理策略"),
            .note("点「开始使用」进入主界面。")
        ]))

        pages = models.map { model in
            let vc = GuidePageViewController(page: model)
            vc.openSettingsHandler = { [weak self] in self?.openSystemSettings() }
            return vc
        }
    }

    private func setupPageController() {
        pageVC = UIPageViewController(transitionStyle: .scroll,
                                      navigationOrientation: .horizontal)
        pageVC.dataSource = self
        pageVC.setViewControllers([pages[0]], direction: .forward, animated: false)
        addChild(pageVC)
        view.addSubview(pageVC.view)
        pageVC.view.translatesAutoresizingMaskIntoConstraints = false
        pageVC.didMove(toParent: self)
    }

    private func setupChrome() {
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        pageControl.numberOfPages = pages.count
        pageControl.currentPage = 0
        pageControl.pageIndicatorTintColor = .systemGray4
        pageControl.currentPageIndicatorTintColor = .systemIndigo
        pageControl.isUserInteractionEnabled = false

        nextButton.translatesAutoresizingMaskIntoConstraints = false
        nextButton.setTitle("下一步", for: .normal)
        nextButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        nextButton.backgroundColor = .systemIndigo
        nextButton.tintColor = .white
        nextButton.layer.cornerRadius = 12
        nextButton.layer.cornerCurve = .continuous
        nextButton.contentEdgeInsets = UIEdgeInsets(top: 11, left: 22, bottom: 11, right: 22)
        nextButton.addTarget(self, action: #selector(nextTapped), for: .touchUpInside)

        skipButton.translatesAutoresizingMaskIntoConstraints = false
        skipButton.setTitle("跳过", for: .normal)
        skipButton.titleLabel?.font = .systemFont(ofSize: 16)
        skipButton.tintColor = .secondaryLabel
        skipButton.addTarget(self, action: #selector(finish), for: .touchUpInside)

        view.addSubview(pageControl)
        view.addSubview(nextButton)
        view.addSubview(skipButton)

        NSLayoutConstraint.activate([
            pageVC.view.topAnchor.constraint(equalTo: view.topAnchor),
            pageVC.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pageVC.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            pageVC.view.bottomAnchor.constraint(equalTo: pageControl.topAnchor, constant: -8),

            pageControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pageControl.bottomAnchor.constraint(equalTo: nextButton.topAnchor, constant: -10),
            pageControl.heightAnchor.constraint(equalToConstant: 20),

            nextButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            nextButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nextButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 160),
            nextButton.heightAnchor.constraint(equalToConstant: 46),

            skipButton.centerYAnchor.constraint(equalTo: nextButton.centerYAnchor),
            skipButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])
        updateChrome()
    }

    private func updateChrome() {
        let isLast = currentIndex == pages.count - 1
        nextButton.setTitle(isLast ? "开始使用" : "下一步", for: .normal)
        pageControl.currentPage = currentIndex
        skipButton.isHidden = isLast
    }

    // MARK: Actions

    @objc private func nextTapped() {
        if currentIndex == pages.count - 1 {
            finish()
            return
        }
        let target = currentIndex + 1
        pageVC.setViewControllers([pages[target]], direction: .forward, animated: true) { [weak self] _ in
            self?.currentIndex = target
        }
    }

    @objc private func finish() {
        AppGroupConfig.sharedDefaults?.set(true, forKey: AppGroupConfig.DefaultsKey.onboardingCompleted)
        onFinish?()
        dismiss(animated: true)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - PageViewController 数据源

extension OnboardingViewController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let idx = pages.firstIndex(of: viewController), idx > 0 else { return nil }
        return pages[idx - 1]
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let idx = pages.firstIndex(of: viewController), idx < pages.count - 1 else { return nil }
        return pages[idx + 1]
    }
}
