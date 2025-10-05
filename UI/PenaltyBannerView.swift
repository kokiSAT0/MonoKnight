import SwiftUI
import Game  // `PenaltyEvent` などゲームロジック側の公開型を利用するため、Game パッケージを明示的に読み込む。

// MARK: - Game モジュール参照に関する補足
// SwiftUI の View 層ではゲームロジックへ直接依存しない設計を心掛けているが、
// ペナルティ表示では `PenaltyEvent` や `PenaltyTrigger` などの型情報が必要になる。
// そのため、Game モジュールを import してルール側の更新内容と整合性を取りやすくしている。

/// ペナルティ発動時に画面上部へ表示する通知バナー
/// - Note: `PenaltyEvent` の内容を参照し、金額やトリガー種別に応じた文言へ自動で切り替える。
struct PenaltyBannerView: View {
    /// カラーテーマ
    private var theme = AppTheme()
    /// 表示対象となるペナルティイベント
    let event: PenaltyEvent

    /// 外部から利用するためのカスタムイニシャライザ
    /// - Parameters:
    ///   - event: 表示すべき最新のペナルティイベント
    ///   - theme: テーマ差し替え用（通常は既定値を利用）
    init(event: PenaltyEvent, theme: AppTheme = AppTheme()) {
        // MARK: - 依存関係の代入
        // View 外部で生成したテーマを受け取り、必要に応じてデザインを切り替えられるようにする。
        self.theme = theme
        // イベントを保持し、金額やトリガー種別に応じたメッセージ生成へ活用する。
        self.event = event
    }

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
        switch event.trigger {
        case .automaticDeadlock:
            if event.penaltyAmount > 0 {
                return "手詰まり → 手札スロットを引き直し (+\(event.penaltyAmount))"
            } else {
                return "手詰まり → ペナルティなしで引き直し"
            }
        case .manualRedraw:
            if event.penaltyAmount > 0 {
                return "手動ペナルティ → 手札を再抽選 (+\(event.penaltyAmount))"
            } else {
                return "手動ペナルティ → 手札を再抽選 (ペナルティなし)"
            }
        case .automaticFreeRedraw:
            return "連続手詰まり → 無料で手札を再抽選"
        }
    }

    /// ペナルティ内容に応じた補足メッセージ
    var secondaryMessage: String {
        switch event.trigger {
        case .automaticDeadlock:
            if event.penaltyAmount > 0 {
                return "使えるカードが無かったため、手数が \(event.penaltyAmount) 増加しました"
            } else {
                return "使えるカードが無かったため、今回はペナルティが発生しません"
            }
        case .manualRedraw:
            if event.penaltyAmount > 0 {
                return "プレイヤー操作により手札を入れ替え、手数が \(event.penaltyAmount) 増加しました"
            } else {
                return "プレイヤー操作により手札を入れ替えましたが、手数の増加はありません"
            }
        case .automaticFreeRedraw:
            return "手詰まりが連続したため、追加手数なしで自動的に手札を入れ替えました"
        }
    }

    /// アクセシビリティ用の案内文
    var accessibilityText: String {
        "\(primaryMessage)。\(secondaryMessage)"
    }
}
