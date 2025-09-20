import SwiftUI

/// ユーザーが選択可能なテーマモードを一元管理する列挙型
/// - NOTE: RawValue に文字列を採用し、`@AppStorage` と組み合わせることで永続化を容易にしている
enum ThemePreference: String, CaseIterable, Identifiable {
    /// システム設定に追従する（デフォルト）。環境から提供されるカラースキームをそのまま適用する。
    case system
    /// 常にライトモードで表示する。暗所でも視認しやすい配色を維持したいユーザー向け。
    case light
    /// 常にダークモードで表示する。OLED 端末での省電力や夜間プレイ重視のユーザー向け。
    case dark

    /// `Identifiable` 準拠用の一意識別子。`ForEach` などのリスト表示で活用する。
    var id: String { rawValue }

    /// `.preferredColorScheme(\_)` に渡すための SwiftUI 標準 `ColorScheme?`
    /// - Returns: システム追従時は `nil` を返し、SwiftUI に環境依存の挙動を委ねる。
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    /// 設定画面などで表示するローカライズ済みの名称
    /// - Important: 日本語 UI を前提にしているため、明示的に和訳した文言を保持する。
    var displayName: String {
        switch self {
        case .system:
            return "システムに合わせる"
        case .light:
            return "ライト"
        case .dark:
            return "ダーク"
        }
    }
}
