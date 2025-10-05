import SwiftUI

/// カード選択フェーズを案内するトーストビュー
/// - Important: ハイライト対象の説明を視覚的に補助し、誤操作を防ぐための軽量通知として利用する
struct CardSelectionPhaseToastView: View {
    /// アプリ全体で共通化されたテーマ
    let theme: AppTheme
    /// 利用者へ提示するメッセージ
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "hand.tap")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(theme.accentPrimary)
                .accessibilityHidden(true)  // テキストと重複しないよう非表示にする

            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.backgroundElevated.opacity(0.94))
                .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 6)
        )
        .frame(maxWidth: 440, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message))
    }
}
