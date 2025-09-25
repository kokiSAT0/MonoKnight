import Game  // GameMode.Identifier を扱うために追加
import SwiftUI
import UIKit  // ハプティクス用フレームワーク

/// ゲーム終了時の結果を表示するビュー
/// ポイントと内訳、ベスト記録、各種ボタンをまとめて配置する
@MainActor
struct ResultView: View {
    /// 今回のプレイで実際に移動した回数
    let moveCount: Int

    /// ペナルティで加算された手数
    let penaltyCount: Int

    /// クリアまでに要した秒数
    let elapsedSeconds: Int

    /// スコア送信・ランキング表示に利用するゲームモード識別子
    let modeIdentifier: GameMode.Identifier
    /// 表示用のモード名称
    let modeDisplayName: String
    /// ランキングボタンを表示するかどうか
    let showsLeaderboardButton: Bool

    /// キャンペーンステージのクリア記録（通常モードの場合は nil）
    let campaignClearRecord: CampaignStageClearRecord?
    /// 今回のクリアで新しく解放されたキャンペーンステージ一覧
    let newlyUnlockedStages: [CampaignStage]
    /// 解放されたステージへ直接移動するためのクロージャ
    let onSelectCampaignStage: ((CampaignStage) -> Void)?
    /// 再戦処理を外部から受け取るクロージャ
    let onRetry: () -> Void

    /// Game Center 連携を扱うサービス（プロトコル型で受け取る）
    /// `init` 時にのみ代入し、以後は再代入しないがテスト用に差し替えられるよう `var` で定義
    private var gameCenterService: GameCenterServiceProtocol
    /// 広告表示を扱うサービス（プロトコル型で受け取る）
    /// 上記と同じく `init` で注入し、必要に応じてモックに差し替え可能にする
    private var adsService: AdsServiceProtocol

    /// ベストポイントを `UserDefaults` に保存する
    /// - Note: 新スコア方式に合わせてポイント単位で保持する
    @AppStorage("best_points_5x5") private var bestPoints: Int = .max
    /// ハプティクスを有効にするかどうかの設定値
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true
    /// サイズクラスを参照し、iPad でのフォームシート表示時に余白を調整する
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// 新記録を達成したかどうかを管理するステート
    @State private var isNewBest: Bool = false

    /// 新記録達成時に比較用として保持する旧ベスト値（存在しない場合は nil）
    @State private var previousBest: Int?

    /// デフォルト実装のサービスを安全に取得するためのコンビニエンスイニシャライザ
    /// - NOTE: Swift 6 で厳格化されたコンカレンシーモデルに対応するため、`@MainActor` 上でシングルトンへアクセスする
    init(
        moveCount: Int,
        penaltyCount: Int,
        elapsedSeconds: Int,
        modeIdentifier: GameMode.Identifier,
        modeDisplayName: String,
        showsLeaderboardButton: Bool = true,
        campaignClearRecord: CampaignStageClearRecord? = nil,
        newlyUnlockedStages: [CampaignStage] = [],
        onSelectCampaignStage: ((CampaignStage) -> Void)? = nil,
        onRetry: @escaping () -> Void
    ) {
        self.init(
            moveCount: moveCount,
            penaltyCount: penaltyCount,
            elapsedSeconds: elapsedSeconds,
            modeIdentifier: modeIdentifier,
            modeDisplayName: modeDisplayName,
            showsLeaderboardButton: showsLeaderboardButton,
            campaignClearRecord: campaignClearRecord,
            newlyUnlockedStages: newlyUnlockedStages,
            onSelectCampaignStage: onSelectCampaignStage,
            onRetry: onRetry,
            gameCenterService: GameCenterService.shared,
            adsService: AdsService.shared
        )
    }

    init(
        moveCount: Int,
        penaltyCount: Int,
        elapsedSeconds: Int,
        modeIdentifier: GameMode.Identifier,
        modeDisplayName: String,
        showsLeaderboardButton: Bool = true,
        campaignClearRecord: CampaignStageClearRecord? = nil,
        newlyUnlockedStages: [CampaignStage] = [],
        onSelectCampaignStage: ((CampaignStage) -> Void)? = nil,
        onRetry: @escaping () -> Void,

        gameCenterService: GameCenterServiceProtocol,
        adsService: AdsServiceProtocol

    ) {
        // `@MainActor` に隔離されたシングルトンへ安全にアクセスするため、
        // Swift 6 の規約に合わせてここで依存解決を行う。
        // テスト注入時にも同じコード経路を通せるよう、まずローカル定数に束縛してからプロパティへ代入する。
        let resolvedGameCenterService = gameCenterService
        let resolvedAdsService = adsService

        self.moveCount = moveCount
        self.penaltyCount = penaltyCount
        self.elapsedSeconds = elapsedSeconds
        self.modeIdentifier = modeIdentifier
        self.modeDisplayName = modeDisplayName
        self.showsLeaderboardButton = showsLeaderboardButton
        self.campaignClearRecord = campaignClearRecord
        self.newlyUnlockedStages = newlyUnlockedStages
        self.onSelectCampaignStage = onSelectCampaignStage
        self.onRetry = onRetry
        self.gameCenterService = resolvedGameCenterService
        self.adsService = resolvedAdsService
    }

    var body: some View {
        // MARK: - コンテンツ全体をスクロール可能にして、iPad のフォームシートでも情報が欠けないようにする
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - 合計ポイントと新記録バッジ
                VStack(spacing: 12) {
                    Text("総合ポイント: \(points)")
                        .font(.title)
                        // iPad のフォームシートでは上下の余白が圧縮されるため、独自に余白を確保して見栄えを整える
                        .padding(.top, 16)

                    // 新記録時のみアニメーション付きのバッジを表示
                    if isNewBest {
                        TimelineView(.animation) { context in
                            // TimelineView の時刻から簡易的な脈動アニメーションを生成
                            let progress = sin(context.date.timeIntervalSinceReferenceDate * 2.6)
                            let scale = 1.0 + 0.08 * progress

                            Text("新記録！")
                                .font(.headline.weight(.bold))
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(Color.yellow.opacity(0.18))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.yellow.opacity(0.55), lineWidth: 1)
                                        )
                                )
                                .scaleEffect(scale)
                                .accessibilityLabel("新記録を達成")
                        }
                        .transition(.scale.combined(with: .opacity))
                    }

                    // MARK: - ベストポイント表示（未記録の場合は '-'）
                    Text("ベストポイント: \(bestPointsText)")
                        .font(.headline)

                    // 新旧の比較説明を追加し、振り返りの文脈を与える
                    if let description = bestComparisonDescription {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                }

                // MARK: - キャンペーン用のリワード達成表示
                if let record = campaignClearRecord {
                    campaignRewardSummary(for: record)
                }

                // MARK: - リトライボタン
                Button(action: {
                    // 設定が有効なら成功フィードバックを発火
                    if hapticsEnabled {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    onRetry()
                }) {
                    Text("リトライ")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                // MARK: - Game Center ランキングボタン
                if showsLeaderboardButton {
                    Button(action: {
                        if hapticsEnabled {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        }
                        gameCenterService.showLeaderboard(for: modeIdentifier)
                    }) {
                        Text("ランキング")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                // MARK: - リザルト詳細のテーブル
                VStack(alignment: .leading, spacing: 12) {
                    Text("リザルト詳細")
                        .font(.headline)
                        .padding(.top, 8)

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text("合計手数")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(totalMoves) 手")
                                .font(.body)
                                .monospacedDigit()
                        }

                        GridRow {
                            Text("移動回数")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(moveCount) 手")
                                .font(.body)
                                .monospacedDigit()
                        }

                        GridRow {
                            Text("ペナルティ加算")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(penaltyCount) 手")
                                .font(.body)
                                .monospacedDigit()
                        }

                        GridRow {
                            Text("所要時間")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(formattedElapsedTime)
                                .font(.body)
                                .monospacedDigit()
                        }

                        Divider()
                            .gridCellColumns(2)

                        // MARK: - スコア計算過程を段階的に表示して透明性を高める
                        GridRow {
                            Text("手数ポイント")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("10pt × \(totalMoves)手 = \(movePoints) pt")
                                .font(.body)
                                .monospacedDigit()
                        }

                        GridRow {
                            Text("時間ポイント")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("\(elapsedSeconds)秒 = \(timePoints) pt")
                                .font(.body)
                                .monospacedDigit()
                        }

                        Divider()
                            .gridCellColumns(2)

                        GridRow {
                            Text("合計ポイント")
                                .font(.subheadline.weight(.semibold))
                            Text("\(movePoints) + \(timePoints) = \(points) pt")
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }

                // MARK: - ShareLink で結果共有を促す
                ShareLink(item: shareMessage) {
                    Label("結果を共有", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                // MARK: - 広告表示に関する補足
                // インタースティシャル広告は結果画面への遷移直後に全画面で表示されるため、
                // 画面下部に読み込み中の文言を残さず、実際の結果表示に集中できる構成にしている。
            }
            // MARK: - iPad を含むレギュラー幅でのレイアウト調整
            // 最大幅を制限して中央寄せすることで、フォームシートでも読みやすくコンテンツを配置する。
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 32)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(Color(UIColor.systemBackground))
        .onAppear {
            // ビュー表示時に広告表示をトリガー
            adsService.showInterstitial()
            // ベスト記録の更新を判定
            if showsLeaderboardButton {
                updateBest()
            }
        }
    }

    /// キャンペーンリワードの達成状況をまとめたセクションを生成
    /// - Parameter record: 今回のクリア結果を反映した評価レコード
    @ViewBuilder
    private func campaignRewardSummary(for record: CampaignStageClearRecord) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // ステージ名と獲得スター数を明示し、現在地を把握しやすくする
            Text("キャンペーンリワード")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("ステージ \(record.stage.displayCode) \(record.stage.title)")
                    .font(.headline)

                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { index in
                        Image(systemName: index < record.progress.earnedStars ? "star.fill" : "star")
                            .foregroundColor(index < record.progress.earnedStars ? .yellow : .secondary)
                    }
                }
                .accessibilityLabel("累計スター: \(record.progress.earnedStars) / 3")

                Text("今回の獲得: \(record.evaluation.earnedStars) / 3")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(campaignRewardConditions(for: record), id: \.title) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.isAchieved ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(item.isAchieved ? .green : .secondary)
                            .font(.system(size: 20, weight: .semibold))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                            Text(item.description)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if !newlyUnlockedStages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("新しく解放されたステージ")
                        .font(.headline)

                    Text("そのまま次のステージに進みましょう。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    let canNavigate = onSelectCampaignStage != nil
                    ForEach(newlyUnlockedStages, id: \.id) { stage in
                        Button {
                            // ハプティクス設定に応じて軽いフィードバックを返し、ボタン操作の確実性を高める
                            if hapticsEnabled {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            }
                            onSelectCampaignStage?(stage)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("ステージ \(stage.displayCode)")
                                        .font(.subheadline.weight(.semibold))
                                    Text(stage.title)
                                        .font(.footnote)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.footnote.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canNavigate)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    /// ベスト記録を表示用の文字列に変換
    private var bestPointsText: String {
        bestPoints == .max ? "-" : String(bestPoints)
    }

    /// 合計手数を計算するヘルパー
    private var totalMoves: Int {
        moveCount + penaltyCount
    }

    /// キャンペーンリワードを行単位へ分解し、チェックリストとして利用しやすい形に整える
    /// - Parameter record: 今回のクリア記録
    /// - Returns: 表示用のタプル配列
    private func campaignRewardConditions(for record: CampaignStageClearRecord) -> [(title: String, description: String, isAchieved: Bool)] {
        var items: [(title: String, description: String, isAchieved: Bool)] = []

        // ★1: ステージクリアは確定で達成済みのため、説明文を固定で挿入する
        items.append((
            title: "★1",
            description: "ステージをクリア",  // 基本条件を明示してプレイヤーの達成感を補強する
            isAchieved: true
        ))

        if let secondary = record.stage.secondaryObjectiveDescription {
            items.append((
                title: "★2",
                description: secondary,
                isAchieved: record.progress.achievedSecondaryObjective
            ))
        }

        if let scoreTarget = record.stage.scoreTargetDescription {
            items.append((
                title: "★3",
                description: scoreTarget,
                isAchieved: record.progress.achievedScoreGoal
            ))
        }

        return items
    }

    /// 手数に 10 を掛けたポイント換算値
    private var movePoints: Int {
        totalMoves * 10
    }

    /// 所要時間をそのままポイントとみなした値（秒 = pt）
    private var timePoints: Int {
        elapsedSeconds
    }

    /// ポイント（手数×10 + 経過秒数）を算出
    private var points: Int {
        movePoints + timePoints
    }

    /// 所要時間を日本語表記へ整形する
    private var formattedElapsedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        if minutes > 0 {
            return "\(minutes)分\(seconds)秒"
        } else {
            return "\(seconds)秒"
        }
    }

    /// ShareLink へ渡す共有メッセージを生成
    private var shareMessage: String {
        let penaltyText = penaltyCount == 0 ? "ペナルティなし" : "ペナルティ +\(penaltyCount) 手"
        return "MonoKnight \(modeDisplayName) クリア！ポイント \(points)（移動 \(moveCount) 手 / \(penaltyText) / 所要 \(formattedElapsedTime)）"
    }

    /// iPad 表示時の最大コンテンツ幅を制御し、中央寄せの見た目を整える
    private var contentMaxWidth: CGFloat? {
        horizontalSizeClass == .regular ? 520 : nil
    }

    /// 横方向のパディングをサイズクラスごとに最適化する
    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 32 : 20
    }

    /// 新記録達成時の説明文を生成（旧ベストと比較する）
    private var bestComparisonDescription: String? {
        guard isNewBest else { return nil }

        if let previousBest {
            let diff = previousBest - points
            // 旧ベストより何ポイント改善できたのかを明示
            return "これまでのベスト \(previousBest) pt → 今回 \(points) pt（\(diff) pt 更新）"
        } else {
            // 初回登録時は比較対象が無いため、その旨を明示
            return "初めてのベストポイントが登録されました"
        }
    }

    /// ベスト記録を更新する
    private func updateBest() {
        // 更新前のベストを保持して比較テキストに利用
        previousBest = bestPoints == .max ? nil : bestPoints

        // 今回のポイントと既存ベストを比較して更新するか判定
        if points < bestPoints {
            bestPoints = points

            // 視覚的なアニメーションとハプティクスを新記録時に限定して発火
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                isNewBest = true
            }
            if hapticsEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                isNewBest = false
            }
        }
    }
}

struct ResultView_Previews: PreviewProvider {
    static var previews: some View {
        // プレビュー用にキャンペーンステージのダミーデータを構築
        let stage = CampaignLibrary.shared.chapters.first!.stages.first
        var progress = CampaignStageProgress()
        progress.earnedStars = 2
        progress.achievedSecondaryObjective = true
        let record = CampaignStageClearRecord(
            stage: stage,
            evaluation: CampaignStageEvaluation(
                stageID: stage.id,
                earnedStars: 2,
                achievedSecondaryObjective: true,
                achievedScoreGoal: false
            ),
            progress: progress
        )

        ResultView(
            moveCount: 24,
            penaltyCount: 6,
            elapsedSeconds: 132,
            modeIdentifier: .standard5x5,
            modeDisplayName: "スタンダード",
            campaignClearRecord: record,
            newlyUnlockedStages: [stage],
            onRetry: {},
            gameCenterService: GameCenterService.shared,
            adsService: AdsService.shared
        )
    }
}


#Preview {
    let stage = CampaignLibrary.shared.chapters.first!.stages.first
    var progress = CampaignStageProgress()
    progress.earnedStars = 2
    progress.achievedSecondaryObjective = true
    let record = CampaignStageClearRecord(
        stage: stage,
        evaluation: CampaignStageEvaluation(
            stageID: stage.id,
            earnedStars: 2,
            achievedSecondaryObjective: true,
            achievedScoreGoal: false
        ),
        progress: progress
    )

    ResultView(
        moveCount: 24,
        penaltyCount: 6,
        elapsedSeconds: 132,
        modeIdentifier: .standard5x5,
        modeDisplayName: "スタンダード",
        campaignClearRecord: record,
        newlyUnlockedStages: [stage],
        onRetry: {}
    )
}
