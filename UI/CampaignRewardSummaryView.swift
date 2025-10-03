import SwiftUI
import Game

/// キャンペーンのスター条件と過去記録を共通レイアウトで表示するビュー
/// - Note: GamePreparationOverlay と PauseMenu 双方で同じ見た目を維持できるよう、表示ロジックを 1 箇所へ集約する
struct CampaignRewardSummaryView: View {
    /// 配置先コンテキスト。カード状のオーバーレイと List 内表示で余白を切り替えるために利用する
    enum Context {
        case overlay
        case list
    }

    /// ステージ定義（キャンペーンでない場合は nil）
    let stage: CampaignStage?
    /// 保存済みの進捗
    let progress: CampaignStageProgress?
    /// テーマカラーを共有し、星やチェックマークの色を統一する
    let theme: AppTheme
    /// どのレイアウトで表示するか
    let context: Context
    /// 記録セクションを表示するかどうか（ポーズメニューでは非表示にしたいケースがある）
    let showsRecordSection: Bool

    /// 呼び出し元が必要な情報のみ指定できるよう、 showsRecordSection に既定値を持たせたイニシャライザを用意する
    init(
        stage: CampaignStage?,
        progress: CampaignStageProgress?,
        theme: AppTheme,
        context: Context,
        showsRecordSection: Bool = true
    ) {
        // 受け取った値をそのままプロパティへ転記する。記録非表示の用途を考慮し、デフォルト true で従来挙動を維持する
        self.stage = stage
        self.progress = progress
        self.theme = theme
        self.context = context
        self.showsRecordSection = showsRecordSection
    }

    /// コンテキストごとの定数をまとめる
    private var metrics: LayoutMetrics { LayoutMetrics(context: context) }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
            section(title: "リワード条件") {
                VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                    ForEach(Array(rewardConditions.enumerated()), id: \.offset) { index, condition in
                        rewardConditionRow(index: index, condition: condition)
                    }
                }
            }

            if showsRecordSection {
                // 記録を隠したい画面（例: ポーズメニュー）向けに、セクション自体を条件付きで表示する
                section(title: "これまでの記録") {
                    VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                        starRow
                        recordBulletRow(text: "ハイスコア: \(bestScoreText)")
                        recordBulletRow(text: "最小ペナルティ: \(bestPenaltyText)")
                        recordBulletRow(text: "最少合計手数: \(bestTotalMoveText)")
                        recordBulletRow(text: "最短クリアタイム: \(bestElapsedTimeText)")
                    }
                }
            }
        }
    }
}

private extension CampaignRewardSummaryView {
    /// セクション共通のタイトル + 本文レイアウト
    /// - Parameters:
    ///   - title: 表示するセクションタイトル
    ///   - content: セクション内部のビュー
    @ViewBuilder
    func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: metrics.sectionContentSpacing) {
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textSecondary)
            content()
        }
    }

    /// 獲得済みスター数に応じてアイコンを切り替える行
    private var starRow: some View {
        HStack(spacing: metrics.starSpacing) {
            ForEach(0..<LayoutMetrics.totalStarCount, id: \.self) { index in
                Image(systemName: index < earnedStars ? "star.fill" : "star")
                    .foregroundColor(theme.accentPrimary)
            }

            Text("スター \(earnedStars)/\(LayoutMetrics.totalStarCount)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textSecondary)
        }
    }

    /// 条件一覧の 1 行を生成する
    /// - Parameters:
    ///   - index: スターのインデックス（0 始まり）
    ///   - condition: 表示する達成状況
    private func rewardConditionRow(index: Int, condition: RewardConditionDisplay) -> some View {
        HStack(alignment: .top, spacing: metrics.rowSpacing) {
            Image(systemName: condition.achieved ? "checkmark.circle.fill" : "circle")
                .foregroundColor(condition.achieved ? theme.accentPrimary : theme.textSecondary)
                .font(.system(size: 18, weight: .bold))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("スター \(index + 1)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textSecondary)

                Text(condition.title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(theme.textPrimary)
            }
        }
    }

    /// 記録欄で利用する箇条書きの行
    /// - Parameter text: 表示したい本文
    private func recordBulletRow(text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: metrics.bulletSpacing) {
            Circle()
                .fill(theme.textSecondary.opacity(0.6))
                .frame(width: metrics.bulletSize, height: metrics.bulletSize)
                .accessibilityHidden(true)

            Text(text)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(theme.textPrimary)
        }
    }

    /// 条件表示用の内部モデル
    struct RewardConditionDisplay {
        let title: String
        let achieved: Bool
    }

    /// 条件一覧を生成する
    private var rewardConditions: [RewardConditionDisplay] {
        var results: [RewardConditionDisplay] = []
        let earnedStars = progress?.earnedStars ?? 0
        // スター 1 個目はクリアそのものを意味する
        results.append(.init(title: "ステージクリア", achieved: earnedStars > 0))

        if let stage = stage, let description = stage.secondaryObjectiveDescription {
            let achieved = progress?.achievedSecondaryObjective ?? false
            results.append(.init(title: description, achieved: achieved))
        }

        if let stage = stage, let scoreText = stage.scoreTargetDescription {
            let achieved = progress?.achievedScoreGoal ?? false
            results.append(.init(title: scoreText, achieved: achieved))
        }

        return results
    }

    /// 獲得済みスター数を返す
    private var earnedStars: Int {
        progress?.earnedStars ?? 0
    }

    /// ベストスコアの表示文
    private var bestScoreText: String {
        if let best = progress?.bestScore {
            return "\(best) pt"
        } else {
            return "未記録"
        }
    }

    /// 最小ペナルティの表示文
    private var bestPenaltyText: String {
        guard let best = progress?.bestPenaltyCount else {
            return "未記録"
        }

        // 0 の場合はノーペナルティを明示し、それ以外は合計値のみ表示する
        return best == 0 ? "ペナルティなし" : "ペナルティ合計 \(best)"
    }

    /// 最少合計手数の表示文
    private var bestTotalMoveText: String {
        if let best = progress?.bestTotalMoveCount {
            return "\(best) 手"
        } else {
            return "未記録"
        }
    }

    /// 最短タイムの表示文
    private var bestElapsedTimeText: String {
        if let best = progress?.bestElapsedSeconds {
            return formattedElapsedTime(best)
        } else {
            return "未記録"
        }
    }

    /// 経過秒を日本語表記へ整形する
    /// - Parameter seconds: 秒単位の値
    /// - Returns: 「1分23秒」形式の文字列
    private func formattedElapsedTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes > 0 {
            return "\(minutes)分\(remainingSeconds)秒"
        } else {
            return "\(remainingSeconds)秒"
        }
    }

    /// コンテキスト依存のレイアウト定数
    struct LayoutMetrics {
        let sectionSpacing: CGFloat
        let sectionContentSpacing: CGFloat
        let rowSpacing: CGFloat
        let starSpacing: CGFloat
        let bulletSpacing: CGFloat
        let bulletSize: CGFloat

        static let totalStarCount: Int = 3

        init(context: CampaignRewardSummaryView.Context) {
            switch context {
            case .overlay:
                self.sectionSpacing = 24
                self.sectionContentSpacing = 12
                self.rowSpacing = 12
                self.starSpacing = 10
                self.bulletSpacing = 8
                self.bulletSize = 6
            case .list:
                // List 内では余白をやや詰め、スクロール距離を抑える
                self.sectionSpacing = 20
                self.sectionContentSpacing = 10
                self.rowSpacing = 10
                self.starSpacing = 8
                self.bulletSpacing = 8
                self.bulletSize = 6
            }
        }
    }
}
