import SwiftUI

/// インタースティシャル広告のダミービュー
/// 実際の広告 SDK を導入するまでのプレースホルダーとして使用する
struct DummyInterstitialAdView: View {
    /// 実広告導入までの暫定枠でもライト/ダーク対応させるためのテーマ
    private var theme = AppTheme()

    var body: some View {
        // シンプルな灰色の矩形を広告枠として表示
        Text("広告")
            .foregroundColor(theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 60)
            // 背景色はテーマから取得し、システム設定による明暗に追従させる
            .background(theme.adPlaceholderBackground)
            .accessibilityIdentifier("dummy_interstitial_ad")
    }
}

#Preview {
    DummyInterstitialAdView()
}
