//
//  SilentAudioKeepAlive.swift
//  ClipKit
//
//  路径2：静音音频后台保活 + 低频轮询 changeCount
//
//  原理：声明 audio 后台模式后，播放一段无限循环的静音音频，系统会在后台
//  维持本 App 的音频进程存活，从而让 Timer 持续运行，按设定间隔比对
//  UIPasteboard.changeCount；一旦变化则尝试读取并入库（后台读取自身
//  触发的剪贴板不会弹前台粘贴提示），并发本地通知交由「通知内容扩展」展示。
//
//  【边界】仅面向侧载（SideStore/AltStore/LiveContainer 独立签名）场景；
//  App Store 审核会拒绝静音保活。锁屏很久、系统内存紧张时仍可能被挂起，
//  因此它与 BGTask / PiP / 键盘 / 前台同步互为补充，而非唯一手段。
//

import Foundation
import UIKit
import AVFoundation

public final class SilentAudioKeepAlive {
    public static let shared = SilentAudioKeepAlive()

    private var player: AVAudioPlayer?
    private var pollTimer: Timer?
    private var lastCount: Int = 0
    private var isRunning = false

    private init() {}

    public var enabled: Bool {
        AppGroupConfig.sharedDefaults?.bool(forKey: AppGroupConfig.DefaultsKey.audioKeepAliveEnabled) ?? false
    }

    /// 当前是否正在保活
    public var active: Bool { isRunning }

    // MARK: 生命周期

    public func start() {
        guard enabled, !isRunning else { return }
        configureSessionAndPlay()
        lastCount = PasteboardSync.shared.currentChangeCount()
        let interval = AppGroupConfig.sharedDefaults?
            .double(forKey: AppGroupConfig.DefaultsKey.backgroundPollInterval) ?? 3
        let timer = Timer.scheduledTimer(withTimeInterval: max(1, interval), repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        isRunning = true
    }

    public func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isRunning = false
    }

    private func configureSessionAndPlay() {
        let session = AVAudioSession.sharedInstance()
        do {
            // mixWithOthers：不打断用户正在听的音乐；playback：允许后台出声
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            // 会话被其它音频占用时忽略，下一次进入后台再试
        }
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "wav") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1   // 无限循环
            player.volume = 0
            player.prepareToPlay()
            player.play()
            self.player = player
        } catch {
            // 资源缺失时静默失败，不影响其它捕获路径
        }
    }

    // MARK: 轮询

    private func tick() {
        let current = PasteboardSync.shared.currentChangeCount()
        guard current != lastCount else { return }
        lastCount = current
        let result = PasteboardSync.shared.performSync(sourceApp: "audio-keepalive")
        if case .imported(let item) = result {
            NotificationCenter.default.post(name: .clipboardCapturedInBackground, object: item)
            ClipNotificationManager.shared.notifyCaptured(item)
        }
    }
}
