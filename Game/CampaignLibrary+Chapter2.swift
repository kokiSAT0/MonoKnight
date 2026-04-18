import Foundation

extension CampaignLibrary {
    static func buildChapter2() -> CampaignChapter {
    // MARK: - 2 章のステージ群
    // (1,2) と (3,4) の指定は 1 始まりの座標と解釈し、内部表現の 0 始まりへ変換する。
    // MARK: - 2 章のステージ群
    // 多重踏破マスの回数管理を段階的に学ぶ章。すべて `kingAndKnightBasic` デッキで統一する。
    // MARK: 章 2 以降で共通利用する標準ペナルティ設定（deadlock +3 / redraw +2 / discard +1 / revisit 0）
    // 序盤とは別軸で難度を構築したいため、数値をまとめて管理してバランス調整時の視認性を確保する。
    let unifiedMidCampaignPenalties = GameMode.PenaltySettings(
        deadlockPenaltyCost: 3,
        manualRedrawPenaltyCost: 2,
        manualDiscardPenaltyCost: 1,
        revisitPenaltyCost: 0
    )
    let chapter2Penalties = unifiedMidCampaignPenalties
    
    // 2-1: 4×4 盤で二度踏みマスの基礎を学ぶ導入。中央固定スポーンで落ち着いて操作する。
    let stage21DoubleVisit: [GridPoint: Int] = [
        GridPoint(x: 0, y: 1): 2,
        GridPoint(x: 2, y: 3): 2
    ]
    let stage21 = CampaignStage(
        id: CampaignStageID(chapter: 2, index: 1),
        title: "重踏チュートリアル",
        summary: "左列と右上を 2 回踏む練習です。ペナルティ合計 5 以下でリズムを掴みましょう。",
        regulation: GameMode.Regulation(
            boardSize: 4,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingAndKnightBasic,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 4)),
            penalties: chapter2Penalties,
            additionalVisitRequirements: stage21DoubleVisit
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 5),
        scoreTarget: 450,
        scoreTargetComparison: .lessThanOrEqual,
        // MARK: 第 2 章開始条件は第 1 章でスターを 12 個以上確保しているかを基準にする
        //       章内 8 ステージで満点未満でも挑戦できるよう、閾値を 12 個へ緩和している
        unlockRequirement: .chapterTotalStars(chapter: 1, minimum: 12)
    )
    
    // 2-2: 5×5 盤で対角二度踏みを巡回し、任意スポーンでも 45 手以内へ収める判断力を育てる。
    let stage22DoubleVisit: [GridPoint: Int] = [
        GridPoint(x: 1, y: 1): 2,
        GridPoint(x: 3, y: 3): 2
    ]
    let stage22 = CampaignStage(
        id: CampaignStageID(chapter: 2, index: 2),
        title: "基礎演習",
        summary: "広い 5×5 で二度踏みマスを巡り、45 手以内のルート構築を練習します。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingAndKnightBasic,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter2Penalties,
            additionalVisitRequirements: stage22DoubleVisit
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 45),
        scoreTarget: 450,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage21.id)
    )
    
    // 2-3: 中央三重踏みのテンポを身体で覚えるステージ。40 手以内が目標。
    let stage23TripleVisit: [GridPoint: Int] = [
        GridPoint(x: 2, y: 2): 3
    ]
    let stage23 = CampaignStage(
        id: CampaignStageID(chapter: 2, index: 3),
        title: "三重踏み入門",
        summary: "中央マスを 3 回踏む課題です。ペナルティを抑えつつ 40 手以内を目指しましょう。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingAndKnightBasic,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter2Penalties,
            additionalVisitRequirements: stage23TripleVisit
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 40),
        scoreTarget: 450,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage22.id)
    )
    
    // 2-4: 三重踏みマスを左右へ分散し、ペナルティ合計 3 以下でバランスよく踏破する。
    let stage24TripleVisit: [GridPoint: Int] = [
        GridPoint(x: 1, y: 1): 3,
        GridPoint(x: 3, y: 3): 3
    ]
    let stage24 = CampaignStage(
        id: CampaignStageID(chapter: 2, index: 4),
        title: "複数三重踏み",
        summary: "左右対称の三重踏みマス 2 箇所を巡り、ペナルティ合計 3 以下でまとめる演習です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingAndKnightBasic,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter2Penalties,
            additionalVisitRequirements: stage24TripleVisit
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 3),
        scoreTarget: 580,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage23.id)
    )
    
    // 2-5: 中央四重踏みを 40 手以内で攻略し、手順管理の精度を高める。
    let stage25QuadVisit: [GridPoint: Int] = [
        GridPoint(x: 2, y: 2): 4
    ]
    let stage25 = CampaignStage(
        id: CampaignStageID(chapter: 2, index: 5),
        title: "中央集中",
        summary: "中心マスを 4 回踏む必要があるため、40 手以内で効率良く往復しましょう。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingAndKnightBasic,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter2Penalties,
            additionalVisitRequirements: stage25QuadVisit
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 40),
        scoreTarget: 570,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage24.id)
    )
    
    // 2-6: 左右対称の四重踏みを 130 秒以内で処理し、時間管理を意識させる。
    let stage26QuadVisit: [GridPoint: Int] = [
        GridPoint(x: 1, y: 1): 4,
        GridPoint(x: 3, y: 3): 4
    ]
    let stage26 = CampaignStage(
        id: CampaignStageID(chapter: 2, index: 6),
        title: "四重踏み分散",
        summary: "左右に配置した四重踏みマスを巡回し、130 秒以内でテンポ良く踏破する課題です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingAndKnightBasic,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter2Penalties,
            additionalVisitRequirements: stage26QuadVisit
        ),
        secondaryObjective: .finishWithinSeconds(maxSeconds: 130),
        scoreTarget: 560,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage25.id)
    )
    
    // 2-7: 2・3・4 回踏みを混在させ、38 手以内に収める応用課題。
    let stage27MixedVisit: [GridPoint: Int] = [
        GridPoint(x: 1, y: 1): 2,
        GridPoint(x: 2, y: 2): 3,
        GridPoint(x: 3, y: 3): 4
    ]
    let stage27 = CampaignStage(
        id: CampaignStageID(chapter: 2, index: 7),
        title: "複合課題",
        summary: "踏破回数の異なるマスを組み合わせ、38 手以内で全域を巡る応用ステージです。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingAndKnightBasic,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter2Penalties,
            additionalVisitRequirements: stage27MixedVisit
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 38),
        scoreTarget: 550,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage26.id)
    )
    
    // 2-8: 盤面中央寄りの三重踏みをすべて達成する総合演習。任意スポーンでも 40 手以内を目指す。
    let stage28QuadCorners: [GridPoint: Int] = [
        GridPoint(x: 1, y: 1): 3,
        GridPoint(x: 3, y: 1): 3,
        GridPoint(x: 1, y: 3): 3,
        GridPoint(x: 3, y: 3): 3
    ]
    let stage28 = CampaignStage(
        id: CampaignStageID(chapter: 2, index: 8),
        title: "総合演習",
        summary: "盤面中央寄りの三重踏みを順序良く処理し、40 手以内で締める総仕上げです。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingAndKnightBasic,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter2Penalties,
            additionalVisitRequirements: stage28QuadCorners
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 40),
        scoreTarget: 540,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage27.id)
    )
    
    let chapter2 = CampaignChapter(
        id: 2,
        title: "応用特訓（重踏）",
        summary: "多重踏破マスの扱いを習得する章。",
        stages: [stage21, stage22, stage23, stage24, stage25, stage26, stage27, stage28]
    )
        return chapter2
    }
}
