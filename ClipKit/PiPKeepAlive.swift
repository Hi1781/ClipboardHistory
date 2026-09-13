//
//  PiPKeepAlive.swift
//  ClipKit
//
//  路径1：画中画（Picture in Picture）保活 + 高频轮询 changeCount
//
//  原理：在界面中放置一个 1×1、播放纯黑循环视频的 AVPlayerLayer，由用户
//  一次点击开启系统画中画。只要画中画悬浮窗保持显示，系统就会维持本 App
//  的进程，Timer 即可按较高频率比对 UIPasteboard.changeCount，变化即入库
//  并发本地通知。相比静音音频，PiP 在前台/后台都能保持、且有可见悬浮窗，
//  被杀概率更低；代价是屏幕上常驻一个小窗。
//
//  【边界】必须由用户主动点按开启（系统限制，无法无交互自动进入 PiP）；
//  不支持画中画的设备会优雅降级。
//

import Foundation
import UIKit
import AVFoundation
import AVKit

public final class PiPKeepAlive: NSObject {
    public static let shared = PiPKeepAlive()

    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var pipController: AVPictureInPictureController?
    private var pollTimer: Timer?
    private var lastCount: Int = 0
    private weak var hostView: UIView?

    public var enabled: Bool {
        AppGroupConfig.sharedDefaults?.bool(forKey: AppGroupConfig.DefaultsKey.pipKeepAliveEnabled) ?? false
    }

    /// 画中画当前是否处于活动状态
    public private(set) var isActive = false

    private override init() { super.init() }

    /// 系统是否支持画中画
    public static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    // MARK: 安装

    /// 在宿主视图上挂载隐藏的播放层（App 主界面 viewDidLoad 后调用一次）
    public func install(in hostView: UIView) {
        guard Self.isSupported, self.hostView !== hostView else { return }
        self.hostView = hostView
        guard let url = Bundle.main.url(forResource: "blank_pip", withExtension: "mp4") else { return }

        let item = AVPlayerItem(url: url)
        NotificationCenter.default.addObserver(
            self, selector: #selector(itemEnded(_:)),
            name: .AVPlayerItemDidPlayToEndTime, object: item)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        let layer = AVPlayerLayer(player: player)
        layer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        layer.opacity = 0.02   // 几乎不可见，但必须在层级中才能开启 PiP
        hostView.layer.addSublayer(layer)

        self.player = player
        self.playerLayer = layer
        if let controller = AVPictureInPictureController(playerLayer: layer) {
            controller.delegate = self
            self.pipController = controller
        }
    }

    @objc private func itemEnded(_ note: Notification) {
        if let ended = note.object as? AVPlayerItem { ended.seek(to: .zero) }
        player?.play()
    }

    // MARK: 开启 / 关闭（需用户点击触发）

    /// 返回是否成功发起画中画请求
    @discardableResult
    public func startPiP() -> Bool {
        guard enabled, Self.isSupported, let pip = pipController else { return false }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
        if pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
            beginPolling()
            return true
        }
        return false
    }

    public func stopPiP() {
        pipController?.stopPictureInPicture()
        stopPolling()
        player?.pause()
    }

    // MARK: 轮询

    private func beginPolling() {
        stopPolling()
        lastCount = PasteboardSync.shared.currentChangeCount()
        // PiP 保活下可用较高频率（默认 1.5s）
        let timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let current = PasteboardSync.shared.currentChangeCount()
            guard current != self.lastCount else { return }
            self.lastCount = current
            let result = PasteboardSync.shared.performSync(sourceApp: "pip-keepalive")
            if case .imported(let item) = result {
                NotificationCenter.default.post(name: .clipboardCapturedInBackground, object: item)
                ClipNotificationManager.shared.notifyCaptured(item)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }
}

extension PiPKeepAlive: AVPictureInPictureControllerDelegate {
    public func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        isActive = true
        beginPolling()
        NotificationCenter.default.post(name: .pipKeepAliveStateChanged, object: true)
    }

    public func pictureInPictureControllerDidStopPictureInPicture(_ controller: AVPictureInPictureController) {
        isActive = false
        stopPolling()
        NotificationCenter.default.post(name: .pipKeepAliveStateChanged, object: false)
    }

    public func pictureInPictureController(_ controller: AVPictureInPictureController,
                                           failedToStartPictureInPictureWithError error: Error) {
        isActive = false
        stopPolling()
        NotificationCenter.default.post(name: .pipKeepAliveStateChanged, object: false)
    }
}

public extension Notification.Name {
    static let pipKeepAliveStateChanged = Notification.Name("com.clipboard.kit.pipStateChanged")
}
