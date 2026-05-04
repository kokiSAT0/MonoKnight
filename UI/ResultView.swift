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
    /// フォーカスを使った回数
    let focusCount: Int
    /// 目的地制のリザルトかどうか
    let usesTargetCollection: Bool
    /// 出口到達型ダンジョンのリザルトかどうか
    let usesDungeonExit: Bool
    /// 失敗リザルトかどうか
    let isFailed: Bool
    /// 失敗理由
    let failureReason: String?
    /// ダンジョン残 HP
    let dungeonHP: Int?
    /// ダンジョン残り手数
    let remainingDungeonTurns: Int?
    /// ダンジョンランの階層表示
    let dungeonRunFloorText: String?
    /// ダンジョンランの累計移動手数
    let dungeonRunTotalMoveCount: Int?
    /// 次のダンジョンフロア名
    let nextDungeonFloorTitle: String?
    /// 次階へ進む前に選べる報酬カード
    let dungeonRewardMoveCards: [MoveCard]
    /// リザルト時点で残っている塔所持カード
    let dungeonInventoryEntries: [DungeonInventoryEntry]
    /// 報酬カードとして持ち越せる未使用の床カード
    let dungeonPickupCarryoverEntries: [DungeonInventoryEntry]
    /// 新しく報酬カード化したときの使用回数
    let dungeonRewardAddUses: Int
    /// 塔クリアで得た永続成長ポイント
    let dungeonGrowthAward: DungeonGrowthAward?

    /// クリアまでに要した秒数
    let elapsedSeconds: Int

    /// スコア送信・ランキング表示に利用するゲームモード識別子
    let modeIdentifier: GameMode.Identifier
    /// 表示用のモード名称
    let modeDisplayName: String
    /// ランキングボタンを表示するかどうか
    let showsLeaderboardButton: Bool
    /// Game Center にサインイン済みかどうか
    let isGameCenterAuthenticated: Bool
    /// ルートビューへ Game Center 再サインインを依頼するためのクロージャ
    let onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?

    /// キャンペーンステージのクリア記録（通常モードの場合は nil）
    let campaignClearRecord: CampaignStageClearRecord?
    /// キャンペーン定義順で次に進むステージ
    let nextCampaignStage: CampaignStage?
    /// 次のステージへ直接移動するためのクロージャ
    let onSelectCampaignStage: ((CampaignStage) -> Void)?
    /// 次のダンジョンフロアへ直接移動するためのクロージャ
    let onSelectNextDungeonFloor: (() -> Void)?
    /// ダンジョン報酬カードを選んで次階へ進むためのクロージャ
    let onSelectDungeonRewardMoveCard: ((MoveCard) -> Void)?
    /// ダンジョン報酬を追加/強化などから選んで次階へ進むためのクロージャ
    let onSelectDungeonReward: ((DungeonRewardSelection) -> Void)?
    /// 持ち越しカードを報酬消費なしで整理するためのクロージャ
    let onRemoveDungeonRewardCard: ((MoveCard) -> Void)?
    /// 再戦処理を外部から受け取るクロージャ
    let onRetry: () -> Void
    /// ホームへ戻る操作を外部へ依頼するクロージャ（未指定の場合はボタンを表示しない）
    let onReturnToTitle: (() -> Void)?

    /// Game Center 連携を扱うサービス（プロトコル型で受け取る）
    /// `init` 時にのみ代入し、以後は再代入しないがテスト用に差し替えられるよう `var` で定義
    private var gameCenterService: GameCenterServiceProtocol
    /// 広告表示を扱うサービス（プロトコル型で受け取る）
    /// 上記と同じく `init` で注入し、必要に応じてモックに差し替え可能にする
    private var adsService: AdsServiceProtocol

    /// サイズクラスを参照し、iPad でのフォームシート表示時に余白を調整する
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// 共通設定ストア
    @EnvironmentObject private var gameSettingsStore: GameSettingsStore

    /// リザルト表示に関する一時状態
    @State private var viewState = ResultViewState()

    /// デフォルト実装のサービスを安全に取得するためのコンビニエンスイニシャライザ
    /// - NOTE: Swift 6 で厳格化されたコンカレンシーモデルに対応するため、`@MainActor` 上でシングルトンへアクセスする
    init(
        moveCount: Int,
        penaltyCount: Int,
        focusCount: Int = 0,
        usesTargetCollection: Bool = false,
        usesDungeonExit: Bool = false,
        isFailed: Bool = false,
        failureReason: String? = nil,
        dungeonHP: Int? = nil,
        remainingDungeonTurns: Int? = nil,
        dungeonRunFloorText: String? = nil,
        dungeonRunTotalMoveCount: Int? = nil,
        nextDungeonFloorTitle: String? = nil,
        dungeonRewardMoveCards: [MoveCard] = [],
        dungeonInventoryEntries: [DungeonInventoryEntry] = [],
        dungeonPickupCarryoverEntries: [DungeonInventoryEntry] = [],
        dungeonRewardAddUses: Int = 3,
        dungeonGrowthAward: DungeonGrowthAward? = nil,
        elapsedSeconds: Int,
        modeIdentifier: GameMode.Identifier,
        modeDisplayName: String,
        showsLeaderboardButton: Bool = true,
        isGameCenterAuthenticated: Bool? = nil,
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)? = nil,
        campaignClearRecord: CampaignStageClearRecord? = nil,
        nextCampaignStage: CampaignStage? = nil,
        onSelectCampaignStage: ((CampaignStage) -> Void)? = nil,
        onSelectNextDungeonFloor: (() -> Void)? = nil,
        onSelectDungeonRewardMoveCard: ((MoveCard) -> Void)? = nil,
        onSelectDungeonReward: ((DungeonRewardSelection) -> Void)? = nil,
        onRemoveDungeonRewardCard: ((MoveCard) -> Void)? = nil,
        onRetry: @escaping () -> Void,
        onReturnToTitle: (() -> Void)? = nil
    ) {
        // 既定値はメインアクター上で解決し、Game Center サービスの状態を同期させる
        let resolvedIsAuthenticated = isGameCenterAuthenticated ?? GameCenterService.shared.isAuthenticated
        self.init(
            moveCount: moveCount,
            penaltyCount: penaltyCount,
            focusCount: focusCount,
            usesTargetCollection: usesTargetCollection,
            usesDungeonExit: usesDungeonExit,
            isFailed: isFailed,
            failureReason: failureReason,
            dungeonHP: dungeonHP,
            remainingDungeonTurns: remainingDungeonTurns,
            dungeonRunFloorText: dungeonRunFloorText,
            dungeonRunTotalMoveCount: dungeonRunTotalMoveCount,
            nextDungeonFloorTitle: nextDungeonFloorTitle,
            dungeonRewardMoveCards: dungeonRewardMoveCards,
            dungeonInventoryEntries: dungeonInventoryEntries,
            dungeonPickupCarryoverEntries: dungeonPickupCarryoverEntries,
            dungeonRewardAddUses: dungeonRewardAddUses,
            dungeonGrowthAward: dungeonGrowthAward,
            elapsedSeconds: elapsedSeconds,
            modeIdentifier: modeIdentifier,
            modeDisplayName: modeDisplayName,
            showsLeaderboardButton: showsLeaderboardButton,
            isGameCenterAuthenticated: resolvedIsAuthenticated,
            onRequestGameCenterSignIn: onRequestGameCenterSignIn,
            campaignClearRecord: campaignClearRecord,
            nextCampaignStage: nextCampaignStage,
            onSelectCampaignStage: onSelectCampaignStage,
            onSelectNextDungeonFloor: onSelectNextDungeonFloor,
            onSelectDungeonRewardMoveCard: onSelectDungeonRewardMoveCard,
            onSelectDungeonReward: onSelectDungeonReward,
            onRemoveDungeonRewardCard: onRemoveDungeonRewardCard,
            onRetry: onRetry,
            onReturnToTitle: onReturnToTitle,
            gameCenterService: GameCenterService.shared,
            adsService: AdsService.shared
        )
    }

    init(
        moveCount: Int,
        penaltyCount: Int,
        focusCount: Int = 0,
        usesTargetCollection: Bool = false,
        usesDungeonExit: Bool = false,
        isFailed: Bool = false,
        failureReason: String? = nil,
        dungeonHP: Int? = nil,
        remainingDungeonTurns: Int? = nil,
        dungeonRunFloorText: String? = nil,
        dungeonRunTotalMoveCount: Int? = nil,
        nextDungeonFloorTitle: String? = nil,
        dungeonRewardMoveCards: [MoveCard] = [],
        dungeonInventoryEntries: [DungeonInventoryEntry] = [],
        dungeonPickupCarryoverEntries: [DungeonInventoryEntry] = [],
        dungeonRewardAddUses: Int = 3,
        dungeonGrowthAward: DungeonGrowthAward? = nil,
        elapsedSeconds: Int,
        modeIdentifier: GameMode.Identifier,
        modeDisplayName: String,
        showsLeaderboardButton: Bool = true,
        isGameCenterAuthenticated: Bool? = nil,
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)? = nil,
        campaignClearRecord: CampaignStageClearRecord? = nil,
        nextCampaignStage: CampaignStage? = nil,
        onSelectCampaignStage: ((CampaignStage) -> Void)? = nil,
        onSelectNextDungeonFloor: (() -> Void)? = nil,
        onSelectDungeonRewardMoveCard: ((MoveCard) -> Void)? = nil,
        onSelectDungeonReward: ((DungeonRewardSelection) -> Void)? = nil,
        onRemoveDungeonRewardCard: ((MoveCard) -> Void)? = nil,
        onRetry: @escaping () -> Void,
        onReturnToTitle: (() -> Void)? = nil,

        gameCenterService: GameCenterServiceProtocol,
        adsService: AdsServiceProtocol

    ) {
        // `@MainActor` に隔離されたシングルトンへ安全にアクセスするため、
        // Swift 6 の規約に合わせてここで依存解決を行う。
        // テスト注入時にも同じコード経路を通せるよう、まずローカル定数に束縛してからプロパティへ代入する。
        let resolvedGameCenterService = gameCenterService
        let resolvedAdsService = adsService
        // 認証状態を一度ローカル定数にまとめ、ビュー内部で利用する値を統一する
        let resolvedIsAuthenticated = isGameCenterAuthenticated ?? resolvedGameCenterService.isAuthenticated

        self.moveCount = moveCount
        self.penaltyCount = penaltyCount
        self.focusCount = focusCount
        self.usesTargetCollection = usesTargetCollection
        self.usesDungeonExit = usesDungeonExit
        self.isFailed = isFailed
        self.failureReason = failureReason
        self.dungeonHP = dungeonHP
        self.remainingDungeonTurns = remainingDungeonTurns
        self.dungeonRunFloorText = dungeonRunFloorText
        self.dungeonRunTotalMoveCount = dungeonRunTotalMoveCount
        self.nextDungeonFloorTitle = nextDungeonFloorTitle
        self.dungeonRewardMoveCards = dungeonRewardMoveCards
        self.dungeonInventoryEntries = dungeonInventoryEntries
        self.dungeonPickupCarryoverEntries = dungeonPickupCarryoverEntries
        self.dungeonRewardAddUses = max(dungeonRewardAddUses, 1)
        self.dungeonGrowthAward = dungeonGrowthAward
        self.elapsedSeconds = elapsedSeconds
        self.modeIdentifier = modeIdentifier
        self.modeDisplayName = modeDisplayName
        self.showsLeaderboardButton = showsLeaderboardButton
        self.isGameCenterAuthenticated = resolvedIsAuthenticated
        self.onRequestGameCenterSignIn = onRequestGameCenterSignIn
        self.campaignClearRecord = campaignClearRecord
        self.nextCampaignStage = nextCampaignStage
        self.onSelectCampaignStage = onSelectCampaignStage
        self.onSelectNextDungeonFloor = onSelectNextDungeonFloor
        self.onSelectDungeonRewardMoveCard = onSelectDungeonRewardMoveCard
        self.onSelectDungeonReward = onSelectDungeonReward
        self.onRemoveDungeonRewardCard = onRemoveDungeonRewardCard
        self.onRetry = onRetry
        self.onReturnToTitle = onReturnToTitle
        self.gameCenterService = resolvedGameCenterService
        self.adsService = resolvedAdsService
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ResultSummarySection(presentation: summaryPresentation)

                if let dungeonGrowthAward {
                    DungeonGrowthAwardSection(award: dungeonGrowthAward)
                }

                if let record = campaignClearRecord {
                    CampaignRewardSummarySection(
                        record: record,
                        nextCampaignStage: nextCampaignStage,
                        onSelectCampaignStage: onSelectCampaignStage,
                        hapticsEnabled: gameSettingsStore.hapticsEnabled
                    )
                }

                ResultActionSection(
                    presentation: summaryPresentation,
                    modeIdentifier: modeIdentifier,
                    modeDisplayName: modeDisplayName,
                    nextDungeonFloorTitle: nextDungeonFloorTitle,
                    dungeonRewardMoveCards: dungeonRewardMoveCards,
                    dungeonRewardInventoryEntries: dungeonInventoryEntries,
                    dungeonPickupCarryoverEntries: dungeonPickupCarryoverEntries,
                    dungeonRewardAddUses: dungeonRewardAddUses,
                    showsLeaderboardButton: showsLeaderboardButton,
                    isGameCenterAuthenticated: isGameCenterAuthenticated,
                    onRequestGameCenterSignIn: onRequestGameCenterSignIn,
                    onSelectNextDungeonFloor: onSelectNextDungeonFloor,
                    onSelectDungeonRewardMoveCard: onSelectDungeonRewardMoveCard,
                    onSelectDungeonReward: onSelectDungeonReward,
                    onRemoveDungeonRewardCard: onRemoveDungeonRewardCard,
                    onRetry: onRetry,
                    onReturnToTitle: onReturnToTitle,
                    gameCenterService: gameCenterService,
                    hapticsEnabled: gameSettingsStore.hapticsEnabled
                )
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 32)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
        }
        .onAppear {
            adsService.showInterstitialAfterGameClearIfNeeded()
            if showsLeaderboardButton {
                updateBest()
            }
        }
    }

    /// iPad 表示時の最大コンテンツ幅を制御し、中央寄せの見た目を整える
    private var contentMaxWidth: CGFloat? {
        horizontalSizeClass == .regular ? 520 : nil
    }

    /// 横方向のパディングをサイズクラスごとに最適化する
    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 32 : 20
    }

    private var summaryPresentation: ResultSummaryPresentation {
        ResultSummaryPresentation(
            moveCount: moveCount,
            penaltyCount: penaltyCount,
            focusCount: focusCount,
            usesTargetCollection: usesTargetCollection,
            usesDungeonExit: usesDungeonExit,
            isFailed: isFailed,
            failureReason: failureReason,
            dungeonHP: dungeonHP,
            remainingDungeonTurns: remainingDungeonTurns,
            dungeonRunFloorText: dungeonRunFloorText,
            dungeonRunTotalMoveCount: dungeonRunTotalMoveCount,
            dungeonRewardMoveCards: dungeonRewardMoveCards,
            dungeonInventoryEntries: dungeonInventoryEntries,
            dungeonGrowthAward: dungeonGrowthAward,
            hasNextDungeonFloor: nextDungeonFloorTitle != nil,
            elapsedSeconds: elapsedSeconds,
            bestPoints: gameSettingsStore.bestPoints,
            isNewBest: viewState.isNewBest,
            previousBest: viewState.previousBest
        )
    }

    /// ベスト記録を更新する
    private func updateBest() {
        let didImprove = viewState.updateBest(
            points: summaryPresentation.points,
            settingsStore: gameSettingsStore
        )

        if didImprove {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                viewState.isNewBest = true
            }
            if gameSettingsStore.hapticsEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                viewState.isNewBest = false
            }
        }
    }
}

struct ResultView_Previews: PreviewProvider {
    static var previews: some View {
        // プレビュー共通のサンプルデータを取得
        let sample = ResultView.makePreviewSample()

        return ResultView(
            moveCount: 24,
            penaltyCount: 6,
            elapsedSeconds: 132,
            modeIdentifier: .standard5x5,
            modeDisplayName: "スタンダード",
            campaignClearRecord: sample.record,
            nextCampaignStage: sample.stage,
            onRetry: {},
            gameCenterService: GameCenterService.shared,
            adsService: AdsService.shared
        )
    }
}


#Preview {
    // プレビュー共通処理を使い回して #Preview でも同じデータを利用
    let sample = ResultView.makePreviewSample()

    return ResultView(
        moveCount: 24,
        penaltyCount: 6,
        elapsedSeconds: 132,
        modeIdentifier: .standard5x5,
        modeDisplayName: "スタンダード",
        campaignClearRecord: sample.record,
        nextCampaignStage: sample.stage,
        onRetry: {}
    )
}

private extension ResultView {
    /// プレビュー用のサンプルステージとクリア記録をまとめて生成する
    /// - Returns: ステージと評価レコードを含むタプル
    /// - Note: 取得に失敗した場合はアプリの状態に問題があるため即座に開発者へ気付きを与える
    static func makePreviewSample() -> (stage: CampaignStage, record: CampaignStageClearRecord) {
        // guard を ViewBuilder 直下に置くと Swift 6 でエラーになるため、
        // 補助メソッド内で安全に取り扱い、データ欠如時は前提崩壊として明示的に停止する。
        guard let stage = CampaignLibrary.shared.chapters.first?.stages.first else {
            preconditionFailure("プレビュー用のキャンペーンステージが取得できません")
        }

        // ダミーの進行状況を構築し、UI の検証に必要な最小限の値を詰める
        var previousProgress = CampaignStageProgress()
        previousProgress.earnedStars = 1
        previousProgress.achievedSecondaryObjective = true

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
            previousProgress: previousProgress,
            progress: progress
        )

        return (stage, record)
    }
}
