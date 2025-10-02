import SwiftUI

/// 盤面タップで複数の複数候補カードが競合した際に提示するトーストビュー
/// - Important: モーダルアラートではなく非モーダルな注意喚起として用いるため、
///             背面のタップ操作を阻害しない構造にしている。
struct BoardTapSelectionWarningToastView: View {
    /// ゲーム全体で統一した配色を利用するためのテーマ
    let theme: AppTheme
    /// ユーザーへ表示する本文
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(theme.accentPrimary)
                .accessibilityHidden(true)  // 補助テキストと重複しないよう VoiceOver 対象外にする

            Text(message)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.backgroundElevated.opacity(0.95))
                .shadow(color: Color.black.opacity(0.18), radius: 14, x: 0, y: 8)
        )
        .frame(maxWidth: 440, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(message))
    }
}
