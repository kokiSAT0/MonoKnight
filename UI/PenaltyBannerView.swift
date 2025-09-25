import SwiftUI

/// ペナルティ発動時に画面上部へ表示する通知バナー
/// - Note: 盤面レイアウトロジックと分離し、メッセージ表現の変更を容易にする。
struct PenaltyBannerView: View {
    /// カラーテーマ
    private var theme = AppTheme()
    /// 直近のペナルティ量
    let penaltyAmount: Int

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // MARK: - 警告アイコン
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(theme.penaltyIconForeground)
                .padding(8)
                .background(
                    Circle()
                        // アイコン背景もテーマ側のアクセントに合わせる
                        .fill(theme.penaltyIconBackground)
                )
                .accessibilityHidden(true)  // アイコンは視覚的アクセントのみ

            // MARK: - メッセージ本文
            VStack(alignment: .leading, spacing: 2) {
                Text(primaryMessage)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    // メインテキストはテーマに合わせた明度で表示
                    .foregroundColor(theme.penaltyTextPrimary)
                Text(secondaryMessage)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(theme.penaltyTextSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                // バナーの背景はテーマ設定で透明感を調整
                .fill(theme.penaltyBannerBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.penaltyBannerBorder, lineWidth: 1)
                )
        )
        .shadow(color: theme.penaltyBannerShadow, radius: 18, x: 0, y: 12)
        .accessibilityIdentifier("penalty_banner_content")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }
}

private extension PenaltyBannerView {
    /// ペナルティ内容に応じたメインメッセージ
    var primaryMessage: String {
        if penaltyAmount > 0 {
            return "手詰まり → 手札スロットを引き直し (+\(penaltyAmount))"
        } else {
            return "手札スロットを引き直しました (ペナルティなし)"
        }
    }

    /// ペナルティ内容に応じた補足メッセージ
    var secondaryMessage: String {
        if penaltyAmount > 0 {
            return "使えるカードが無かったため、手数が \(penaltyAmount) 増加しました"
        } else {
            return "使えるカードが無かったため、手数の増加はありません"
        }
    }

    /// アクセシビリティ用の案内文
    var accessibilityText: String {
        "\(primaryMessage)。\(secondaryMessage)"
    }
}
