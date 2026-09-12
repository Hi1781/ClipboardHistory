//
//  ClipboardWidget.swift
//  ClipboardWidget
//
//  v1.1：桌面小组件，展示最近一条剪贴记录
//

import WidgetKit
import SwiftUI

// MARK: - 数据

struct ClipSnapshot: TimelineEntry {
    let date: Date
    let preview: String?
    let timestamp: Date?
}

struct ClipProvider: TimelineProvider {
    private let suiteName = "group.com.clipboard.history"
    private let previewKey = "widgetLatestPreview"
    private let timeKey = "widgetLatestTime"

    func placeholder(in context: Context) -> ClipSnapshot {
        ClipSnapshot(date: Date(), preview: "复制的内容会显示在这里", timestamp: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (ClipSnapshot) -> Void) {
        completion(currentSnapshot())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClipSnapshot>) -> Void) {
        let snapshot = currentSnapshot()
        // 每 15 分钟刷新一次（系统会按情况调度）
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [snapshot], policy: .after(next)))
    }

    private func currentSnapshot() -> ClipSnapshot {
        let defaults = UserDefaults(suiteName: suiteName)
        let preview = defaults?.string(forKey: previewKey)
        var time: Date?
        let ts = defaults?.double(forKey: timeKey) ?? 0
        if ts > 0 { time = Date(timeIntervalSince1970: ts) }
        return ClipSnapshot(date: Date(), preview: preview, timestamp: time)
    }
}

// MARK: - 视图

struct ClipboardWidgetEntryView: View {
    var entry: ClipSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "clipboard")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.indigo)
                Text("剪贴板")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let time = entry.timestamp {
                    Text(time, style: .relative)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let preview = entry.preview, !preview.isEmpty {
                Text(preview)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            } else {
                Text("暂无记录\n打开 App 或唤起键盘同步")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .widgetBackground()
    }
}

/// 小组件背景（iOS16 兼容；containerBackground 为 iOS17 API，在 iOS16.4 SDK 下不可用）
private extension View {
    func widgetBackground() -> some View {
        self.background(Color(.systemBackground))
    }
}

// MARK: - 配置

struct ClipboardWidget: Widget {
    let kind = "ClipboardWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClipProvider()) { entry in
            ClipboardWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("剪贴板历史")
        .description("快速查看最近复制的内容，点击打开 App")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryRectangular, .accessoryInline
        ])
    }
}

@main
struct ClipboardWidgetBundle: WidgetBundle {
    var body: some Widget { ClipboardWidget() }
}
