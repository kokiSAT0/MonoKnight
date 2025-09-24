import Foundation

/// 手札の並べ替え方法を管理するユーザー設定用の列挙体
/// - Note: GameCore からも UI からも利用するためここで定義し、ビルドターゲット差異による読込漏れを防ぐ
public enum HandOrderingStrategy: String, CaseIterable {
    /// 山札から引いた順番をそのまま保持する従来方式
    case insertionOrder
    /// 移動方向に基づいて常にソートする方式
    case directionSorted

    /// UserDefaults / @AppStorage で共有するためのキー
    public static let storageKey = "hand_ordering_strategy"

    /// 設定画面などに表示する日本語名称
    public var displayName: String {
        switch self {
        case .insertionOrder:
            return "引いた順に並べる"
        case .directionSorted:
            return "移動方向で並べ替える"
        }
    }

    /// 詳細説明文。フッター表示などで再利用する
    public var detailDescription: String {
        switch self {
        case .insertionOrder:
            return "山札から引いた順番で手札スロットへ補充します。消費した位置へ新しいカードが入ります。"
        case .directionSorted:
            return "左への移動量が大きいカードほど左側に、同じ左右移動量なら上方向へ進むカードを優先して並べます。"
        }
    }
}
