//
//  ClipItem.swift
//  ClipKit
//
//  剪贴板历史记录数据模型（v2.0：置顶 / 标签 / 分类 / 来源 App）
//

import Foundation
import UIKit

/// 剪贴内容类型
public enum ClipContentType: String, Codable, Sendable, CaseIterable {
    case text
    case image
    case url
    case color
    case other

    /// 列表/筛选使用的本地化名称
    public var displayName: String {
        switch self {
        case .text: return "文本"
        case .image: return "图片"
        case .url: return "链接"
        case .color: return "颜色"
        case .other: return "其他"
        }
    }

    public var symbolName: String {
        switch self {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .url: return "link"
        case .color: return "paintpalette"
        case .other: return "doc"
        }
    }
}

/// 单条剪贴历史记录
public struct ClipItem: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let type: ClipContentType
    /// 文本内容（type == .text / .url / .color / .other 时有效）
    public let text: String?
    /// 图片数据（type == .image 时有效，压缩后加密存储）
    public let imageData: Data?
    /// 创建时间戳
    public let timestamp: Date
    /// 内容哈希，用于去重
    public let contentHash: String
    /// 是否标记为敏感（敏感记录不参与自动回填）
    public var isSensitive: Bool
    /// v1.2 是否固定置顶
    public var isPinned: Bool
    /// v1.2 分类标签
    public var tags: [String]
    /// v1.2 分类（系统分类，等同 type 的可空用户覆盖；默认取 type.displayName）
    public var category: String?
    /// v2.0 来源 App 的 bundle id（可空，后台监听时记录）
    public var sourceApp: String?
    /// 置顶排序权重（越大越靠前），与 timestamp 共同排序
    public var pinnedAt: Date?

    public init(
        id: UUID = UUID(),
        type: ClipContentType,
        text: String? = nil,
        imageData: Data? = nil,
        timestamp: Date = Date(),
        contentHash: String,
        isSensitive: Bool = false,
        isPinned: Bool = false,
        tags: [String] = [],
        category: String? = nil,
        sourceApp: String? = nil,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.imageData = imageData
        self.timestamp = timestamp
        self.contentHash = contentHash
        self.isSensitive = isSensitive
        self.isPinned = isPinned
        self.tags = tags
        self.category = category
        self.sourceApp = sourceApp
        self.pinnedAt = pinnedAt
    }

    // MARK: - 工厂方法

    /// 从文本创建
    public static func makeText(_ text: String, sourceApp: String? = nil) -> ClipItem {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let type: ClipContentType = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") ? .url : .text
        return ClipItem(
            type: type,
            text: text,
            contentHash: CryptoHelper.sha256(text),
            category: type.displayName,
            sourceApp: sourceApp
        )
    }

    /// 从图片创建（自动压缩）
    public static func makeImage(_ image: UIImage, maxDimension: CGFloat = 1280, sourceApp: String? = nil) -> ClipItem {
        let resized = image.resized(maxDimension: maxDimension)
        let data = resized.jpegData(compressionQuality: 0.8) ?? Data()
        return ClipItem(
            type: .image,
            imageData: data,
            contentHash: CryptoHelper.sha256(data),
            category: ClipContentType.image.displayName,
            sourceApp: sourceApp
        )
    }

    /// 从颜色创建
    public static func makeColor(_ color: UIColor) -> ClipItem {
        let hex = color.hexString
        return ClipItem(
            type: .color,
            text: hex,
            contentHash: CryptoHelper.sha256(hex),
            category: ClipContentType.color.displayName
        )
    }

    // MARK: - 便捷属性

    /// 预览文本（列表展示用）
    public var previewText: String {
        switch type {
        case .text, .url:
            return text ?? ""
        case .image:
            return "[图片]"
        case .color:
            return text ?? "[颜色]"
        case .other:
            return text ?? "[其他内容]"
        }
    }

    /// 还原为 UIImage
    public var image: UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }

    /// 用于搜索的归一化文本（小写、去空白）
    public var searchableText: String {
        var parts: [String] = [previewText.lowercased(), type.displayName.lowercased()]
        parts.append(contentsOf: tags.map { $0.lowercased() })
        if let category = category?.lowercased() { parts.append(category) }
        return parts.joined(separator: " ")
    }

    /// 是否匹配关键字（多关键字 AND）
    public func matches(_ keywords: [String]) -> Bool {
        guard !keywords.isEmpty else { return true }
        let haystack = searchableText
        return keywords.allSatisfy { haystack.contains($0) }
    }

    /// 时间展示文本
    public var timeString: String {
        Self.formatted(timestamp)
    }

    /// 相对时间（“刚刚 / 5 分钟前”），用于 Widget / 预览
    public var relativeTimeString: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f.localizedString(for: timestamp, relativeTo: Date())
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter
    }()

    /// 按当前时刻刷新格式（timeString 内部缓存 formatter，按日期切换格式）
    public static func formatted(_ date: Date) -> String {
        let formatter = timeFormatter
        if Calendar.current.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else if Calendar.current.isDateInYesterday(date) {
            formatter.dateFormat = "'昨天' HH:mm"
        } else {
            formatter.dateFormat = "MM-dd HH:mm"
        }
        return formatter.string(from: date)
    }
}

// MARK: - 排序规则

public extension Array where Element == ClipItem {
    /// 统一排序：置顶优先（pinnedAt 倒序），其余按 timestamp 倒序
    func sortedForDisplay() -> [ClipItem] {
        sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned && !rhs.isPinned }
            if lhs.isPinned && rhs.isPinned {
                let lt = lhs.pinnedAt ?? lhs.timestamp
                let rt = rhs.pinnedAt ?? rhs.timestamp
                return lt > rt
            }
            return lhs.timestamp > rhs.timestamp
        }
    }
}

// MARK: - UIImage 压缩扩展

extension UIImage {
    func resized(maxDimension: CGFloat) -> UIImage {
        let width = size.width
        let height = size.height
        let longest = max(width, height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: width * scale, height: height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - UIColor 扩展（公开，供键盘/App 共用）

public extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        if a < 1.0 {
            return String(format: "#%02X%02X%02X%02X",
                          Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
        }
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexSanitized.hasPrefix("#") { hexSanitized.removeFirst() }
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        let length = hexSanitized.count
        let r, g, b, a: CGFloat
        switch length {
        case 6:
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255
            b = CGFloat(rgb & 0x0000FF) / 255
            a = 1.0
        case 8:
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255
            a = CGFloat(rgb & 0x000000FF) / 255
        default:
            return nil
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }
}
