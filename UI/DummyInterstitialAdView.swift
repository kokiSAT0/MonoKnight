import SwiftUI

/// インタースティシャル広告のダミービュー
/// 実際の広告 SDK を導入するまでのプレースホルダーとして使用する
struct DummyInterstitialAdView: View {
    var body: some View {
        // シンプルな灰色の矩形を広告枠として表示
        Text("広告")
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(Color.gray.opacity(0.3))
            .accessibilityIdentifier("dummy_interstitial_ad")
    }
}

#Preview {
    DummyInterstitialAdView()
}
