//
//  PiPKeepAlive.swift
//  ClipKit
//
//  路径1：画中画（Picture in Picture）保活 + 高频轮询 changeCount
//
//  原理：在界面中放置一个 1×1、播放纯黑循环视频的 AVPlayerLayer，由用户
//  一次点击开启系统画中画。只要画中画悬浮窗保持显示，系统就会维持本 App
//  的进程，Timer 即可按较高频率比对 UIPasteboard.changeCount，变化即入库
//  并发本地通知。
//
//  v2.6 修复「点了却不出小窗」：
//  - 用 AVPlayerLooper + AVQueuePlayer 无缝循环，避免到结尾 seek 造成的停顿把 PiP 打断
//  - 首次点击时视频可能尚未就绪，isPictureInPicturePossible 为 false；
//    现用 KVO 监听该属性，一旦变 true 立即 startPictureInPicture，不再一次性失败
//  - 提前激活 .playback 音频会话，保证可进入后台悬浮小窗
//

import Foundation
import UIKit
import AVFoundation
import AVKit

public final class PiPKeepAlive: NSObject {
    public static let shared = PiPKeepAlive()

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?
    private var pipController: AVPictureInPictureController?
    private var pollTimer: Timer?
    private var lastCount: Int = 0
    private weak var hostView: UIView?

    private var possibleObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var wantsToStart = false

    public var enabled: Bool {
        AppGroupConfig.sharedDefaults?.bool(forKey: AppGroupConfig.DefaultsKey.pipKeepAliveEnabled) ?? false
    }

    /// 画中画当前是否处于活动状态
    public private(set) var isActive = false

    private override init() { super.init() }

    /// 系统是否支持画中画
    public static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    // MARK: 安装

    /// 在宿主视图上挂载隐藏的播放层（App 主界面 window 建立后调用一次）
    public func install(in hostView: UIView) {
        guard Self.isSupported, self.hostView !== hostView else { return }
        self.hostView = hostView
        guard let url = Bundle.main.url(forResource: "blank_pip", withExtension: "mp4") else { return }

        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        let looper = AVPlayerLooper(player: player, templateItem: item)

        let layer = AVPlayerLayer(player: player)
        layer.frame = CGRect(x: 0, y: 0, width: 2, height: 2)
        layer.opacity = 0.02   // 几乎不可见，但必须在层级中且在屏才能开启 PiP
        hostView.layer.addSublayer(layer)

        self.player = player
        self.looper = looper
        self.playerLayer = layer

        if let controller = AVPictureInPictureController(playerLayer: layer) {
            controller.delegate = self
            self.pipController = controller
            // 关键：可画中画状态会随视频就绪翻转，监听后自动发起
            possibleObservation = controller.observe(\.isPictureInPicturePossible,
                                                       options: [.initial, .new]) { [weak self] ctrl, _ in
                guard let self, self.wantsToStart, ctrl.isPictureInPicturePossible, !self.isActive else { return }
                ctrl.startPictureInPicture()
            }
        }

        // 视频就绪后自动播放（用户已请求开启时）
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            guard let self, it.status == .readyToPlay, self.wantsToStart else { return }
            self.player?.play()
        }
    }

    // MARK: 开启 / 关闭（需用户点击触发）

    /// 请求开启画中画：立即激活会话并播放；若此刻尚不可进入，KVO 会在就绪后自动发起
    @discardableResult
    public func startPiP() -> Bool {
        guard enabled, Self.isSupported, pipController != nil else {
            NotificationCenter.default.post(name: .pipKeepAliveStateChanged, object: false)
            return false
        }
        wantsToStart = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
        if let pip = pipController, pip.isPictureInPicturePossible {
            pip.startPictureInPicture()
        }
        // 即便此刻返回 true/false，KVO 都会兜底在就绪后发起
        return true
    }

    public func stopPiP() {
        wantsToStart = false
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
