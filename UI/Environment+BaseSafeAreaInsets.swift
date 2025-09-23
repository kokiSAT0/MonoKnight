import SwiftUI

/// ルートビューで取得したシステム由来の上部セーフエリア量を子ビューへ伝搬する EnvironmentKey
/// - Note: safeAreaInset で追加したカスタムバーの高さが GeometryReader に混ざると、
///         GameView 側で純粋なセーフエリア量を把握できなくなるため事前に共有する。
struct BaseTopSafeAreaInsetEnvironmentKey: EnvironmentKey {
    /// 追加情報が無い場合は 0 を返し、従来のロジックと同じ挙動へフォールバックする
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// 画面上部のシステム由来セーフエリア（ステータスバー等）を参照するためのプロパティ
    /// - Note: RootView が GeometryReader から取得した値を渡し、GameView ではこの値との差分を取って
    ///         safeAreaInset によるオーバーレイ高さを推定する。
    var baseTopSafeAreaInset: CGFloat {
        get { self[BaseTopSafeAreaInsetEnvironmentKey.self] }
        set { self[BaseTopSafeAreaInsetEnvironmentKey.self] = newValue }
    }
}

