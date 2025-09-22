import Foundation

/// 手札の並び順を制御するユーザー設定
/// - Note: UI 側の Picker でも利用できるよう `public` に公開し、`CaseIterable` / `Identifiable` を実装する。
public enum HandOrderMode: String, CaseIterable, Identifiable {
    /// 山札から引いた順番をそのまま維持する（従来仕様）
    case drawOrder
    /// 移動方向に基づいて常にソートする新仕様
    case directional

    /// `CaseIterable` の順番を明示し、設定画面の表示順も固定する
    public static let allCases: [HandOrderMode] = [.drawOrder, .directional]

    /// `Identifiable` 準拠のための一意な識別子
    public var id: String { rawValue }

    /// 設定値を永続化する `@AppStorage` のキー名をまとめておく
    public static let storageKey = "hand_order_mode"

    /// UI に表示する説明ラベル
    public var displayName: String {
        switch self {
        case .drawOrder:
            return "引いた順のまま"
        case .directional:
            return "移動方向で自動整列"
        }
    }

    /// 詳細な説明文を提供し、設定画面のフッターなどで再利用する
    public var detailDescription: String {
        switch self {
        case .drawOrder:
            return "手札は山札から引いた順番で左から並び、使用した枠に新しいカードが補充されます。"
        case .directional:
            return "左へ大きく移動できるカードほど手札の左側に並び、左右移動量が同じ場合は上方向へ進めるカードが優先されます。"
        }
    }
}
