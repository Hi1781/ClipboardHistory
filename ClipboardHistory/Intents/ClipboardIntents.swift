//
//  ClipboardIntents.swift
//  ClipboardHistory
//
//  v2.0：App Intents（Siri / 快捷指令 / 聚焦）
//

import AppIntents
import UIKit
import ClipKit

/// 复制最新一条剪贴记录
struct CopyLatestClipIntent: AppIntent {
    static var title: LocalizedStringResource = "复制最新剪贴记录"
    static var description = IntentDescription("把剪贴板历史中最新的一条重新复制到系统剪贴板")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let latest = ClipStore.shared.fetchLatest() else {
            return .result(dialog: "剪贴板历史为空")
        }
        PasteboardSync.shared.writeToPasteboard(latest)
        let preview = latest.previewText.prefix(40)
        return .result(dialog: "已复制：\(preview)")
    }
}

/// 按关键词搜索记录并复制最匹配的一条
struct SearchAndCopyClipIntent: AppIntent {
    static var title: LocalizedStringResource = "搜索并复制剪贴记录"
    static var description = IntentDescription("按关键词搜索历史记录，并复制最匹配的一条")

    @Parameter(title: "关键词")
    var keyword: String

    static var parameterSummary: some ParameterSummary {
        Summary("搜索并复制包含「\(\.$keyword)」的记录")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let results = ClipStore.shared.search(keyword)
        guard let match = results.first else {
            return .result(dialog: "没有找到包含 \(keyword) 的记录")
        }
        PasteboardSync.shared.writeToPasteboard(match)
        return .result(dialog: "已复制匹配记录")
    }
}

/// 清空剪贴板历史
struct ClearClipboardHistoryIntent: AppIntent {
    static var title: LocalizedStringResource = "清空剪贴板历史"
    static var description = IntentDescription("删除全部本地剪贴板历史记录")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        ClipStore.shared.clearAll()
        return .result(dialog: "剪贴板历史已清空")
    }
}

/// 打开 App
struct OpenClipboardAppIntent: AppIntent {
    static var title: LocalizedStringResource = "打开剪贴板历史"
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult { .result() }
}

/// 快捷指令 App 快捷入口集合
struct ClipboardShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CopyLatestClipIntent(),
            phrases: [
                "复制最新剪贴记录 \(.applicationName)",
                "用 \(.applicationName) 回填剪贴板"
            ],
            shortTitle: "复制最新记录",
            systemImageName: "doc.on.clipboard"
        )
    }
}
