//
//  HapticHelper.swift
//  ClipKit
//
//  统一触感反馈（可在设置中关闭）
//

import UIKit

public enum HapticHelper {

    private static var enabled: Bool {
        AppGroupConfig.sharedDefaults?.bool(forKey: AppGroupConfig.DefaultsKey.hapticFeedbackEnabled) ?? true
    }

    public static func tap() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    public static func copy() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    public static func success() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    public static func warning() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    public static func select() {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }
}
