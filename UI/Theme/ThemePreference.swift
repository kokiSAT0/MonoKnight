import SwiftUI

/// ユーザーが選択可能なテーマモードを一元管理する列挙型
/// - Note: RawValue に文字列を採用し、`GameSettingsStore` からの永続化を簡潔に保つ。
enum ThemePreference: String, CaseIterable, Identifiable {
    /// システム設定に追従するデフォルト設定
    case system
    /// 常にライトモードで表示する
    case light
    /// 常にダークモードで表示する
    case dark

    /// `ForEach` 用の識別子
    var id: String { rawValue }

    /// `.preferredColorScheme(_:)` に渡す値へ変換する
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    /// 設定 UI に表示する名称
    var displayName: String {
        switch self {
        case .system:
            "システムに合わせる"
        case .light:
            "ライト"
        case .dark:
            "ダーク"
        }
    }
}
