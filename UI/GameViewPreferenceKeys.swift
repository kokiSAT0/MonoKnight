import SwiftUI

/// 手札・NEXT に配置されたカードのアンカーを UUID 単位で収集する PreferenceKey
/// - Note: `GameView` と `GameHandSectionView` の両方から参照するため独立ファイルで管理する。
struct CardPositionPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] = [:]

    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// SpriteView（盤面）のアンカーを保持する PreferenceKey
struct BoardAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// 統計バッジ領域の高さを親ビューへ伝搬するための PreferenceKey
struct StatisticsHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // 毎フレームで統計領域の最新高さへ更新し、ジオメトリ変化に即応できるよう最大値ではなく直近の値を採用する
        value = nextValue()
    }
}

/// 手札セクションの高さを親ビューへ伝搬するための PreferenceKey
/// - Note: 手札専用ビューでも利用するため internal 扱いとする。
struct HandSectionHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        // 手札レイアウトのジオメトリ変化へ滑らかに追従するため、最大値の保持ではなく常に最新高さへ更新する
        value = nextValue()
    }
}

/// 任意の PreferenceKey へ高さを伝搬するゼロサイズのオーバーレイ
/// - Note: GeometryReader を直接レイアウトへ配置すると親ビューいっぱいまで広がり、想定外の値になるため
///         あえて Color.clear を 0 サイズへ縮めて高さだけを測定する。
///         `GameHandSectionView` からも再利用するため internal 扱いとする。
struct HeightPreferenceReporter<Key: PreferenceKey>: View where Key.Value == CGFloat {
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .frame(width: 0, height: 0)
                .preference(key: Key.self, value: proxy.size.height)
        }
        .allowsHitTesting(false)  // あくまでレイアウト取得用のダミービューなので操作対象から除外する
    }
}
