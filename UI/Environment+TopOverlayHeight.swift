import SwiftUI

/// 画面上部に挿入するオーバーレイ（トップバーなど）の高さを子ビューへ伝搬するための EnvironmentKey
/// - Note: RootView 側で安全領域を拡張した際、GameView では元の safeAreaInsets.top から減算した値を使いたいため
///         明示的にトップバーの高さを共有できる仕組みを用意する。
struct TopOverlayHeightEnvironmentKey: EnvironmentKey {
    /// デフォルト値は 0。トップバーが存在しない構成でも従来どおり動作させる
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// 画面上部の追加オーバーレイの高さを保持するプロパティ
    /// - Note: RootView から GameView へ伝搬し、safeAreaInsets.top から差し引く用途で参照する
    var topOverlayHeight: CGFloat {
        get { self[TopOverlayHeightEnvironmentKey.self] }
        set { self[TopOverlayHeightEnvironmentKey.self] = newValue }
    }
}

