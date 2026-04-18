import Foundation

extension CampaignLibrary {
    static func buildChapter5() -> CampaignChapter {
    // MARK: - 5 章のステージ群
    // 障害物マスと複数ギミックを組み合わせる総合章。
    let chapter5Penalties = standardPenalties
    
    // 5-1: 障害物 2 箇所で 30 手以内を目指す導入。
    let stage51Impassable: Set<GridPoint> = [
        GridPoint(x: 1, y: 1),
        GridPoint(x: 3, y: 3)
    ]
    let stage51 = CampaignStage(
        id: CampaignStageID(chapter: 5, index: 1),
        title: "障害物基礎",
        summary: "対角に置かれた障害物を避け、30 手以内で踏破するルート構築を学びます。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: fixedSpawn5,
            penalties: chapter5Penalties,
            impassableTilePoints: stage51Impassable
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 30),
        scoreTarget: 500,
        scoreTargetComparison: .lessThanOrEqual,
        // MARK: 第 5 章も直前章スター 12 個以上で解放し、以降の章と条件を合わせる
        unlockRequirement: .chapterTotalStars(chapter: 4, minimum: 12)
    )
    
    // 5-2: 障害物を 3 箇所へ増やし、ペナルティ合計 2 以下で安定させる。
    let stage52Impassable: Set<GridPoint> = [
        GridPoint(x: 1, y: 1),
        GridPoint(x: 3, y: 3),
        GridPoint(x: 2, y: 2)
    ]
    let stage52 = CampaignStage(
        id: CampaignStageID(chapter: 5, index: 2),
        title: "障害物応用",
        summary: "中心を含む障害物 3 箇所を管理し、ペナルティ合計 2 以下で踏破する演習です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: .chooseAnyAfterPreview, // 中央を含む障害物 `stage52Impassable` に合わせ、任意スポーンで初期詰みを回避
            penalties: chapter5Penalties,
            impassableTilePoints: stage52Impassable
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
        scoreTarget: 490,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage51.id)
    )
    
    // 5-3: 障害物と二度踏みを組み合わせ、40 手以内を狙う。
    let stage53Impassable: Set<GridPoint> = [
        GridPoint(x: 0, y: 1),
        GridPoint(x: 4, y: 3)
    ]
    let stage53DoubleVisit: [GridPoint: Int] = [
        GridPoint(x: 1, y: 3): 2,
        GridPoint(x: 3, y: 1): 2
    ]
    let stage53 = CampaignStage(
        id: CampaignStageID(chapter: 5, index: 3),
        title: "障害物＋二度踏み",
        summary: "障害物を避けながら二度踏みマスを処理し、40 手以内で踏破する実戦課題です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: fixedSpawn5,
            penalties: chapter5Penalties,
            additionalVisitRequirements: stage53DoubleVisit,
            impassableTilePoints: stage53Impassable
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 40),
        scoreTarget: 480,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage52.id)
    )
    
    // 5-4: 任意スポーンで三重踏み＋障害物を扱い、ペナルティ合計 1 以下を目指す。
    let stage54Impassable: Set<GridPoint> = [
        GridPoint(x: 0, y: 2),
        GridPoint(x: 4, y: 2)
    ]
    let stage54TripleVisit: [GridPoint: Int] = [
        GridPoint(x: 2, y: 2): 3
    ]
    let stage54 = CampaignStage(
        id: CampaignStageID(chapter: 5, index: 4),
        title: "障害物＋三重踏み",
        summary: "任意スポーンで三重踏みと障害物を管理し、ペナルティ合計 1 以下で安定攻略します。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter5Penalties,
            additionalVisitRequirements: stage54TripleVisit,
            impassableTilePoints: stage54Impassable
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 1),
        scoreTarget: 470,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage53.id)
    )
    
    // 5-5: 障害物とトグルを組み合わせ、38 手以内で制御する。
    let stage55Impassable: Set<GridPoint> = [
        GridPoint(x: 1, y: 1),
        GridPoint(x: 3, y: 3)
    ]
    let stage55Toggles: Set<GridPoint> = [
        GridPoint(x: 2, y: 1),
        GridPoint(x: 2, y: 3)
    ]
    let stage55 = CampaignStage(
        id: CampaignStageID(chapter: 5, index: 5),
        title: "障害物＋トグル",
        summary: "中央列のトグルと障害物を同時に捌き、38 手以内のルート最適化を図ります。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: fixedSpawn5,
            penalties: chapter5Penalties,
            toggleTilePoints: stage55Toggles,
            impassableTilePoints: stage55Impassable
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 38),
        scoreTarget: 460,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage54.id)
    )
    
    // 5-6: 任意スポーンで四重踏みとトグルを扱い、36 手以内を狙う。
    let stage56Impassable: Set<GridPoint> = [
        GridPoint(x: 1, y: 1),
        GridPoint(x: 3, y: 3)
    ]
    let stage56QuadVisit: [GridPoint: Int] = [
        GridPoint(x: 2, y: 2): 4
    ]
    let stage56Toggles: Set<GridPoint> = [
        GridPoint(x: 0, y: 4)
    ]
    let stage56 = CampaignStage(
        id: CampaignStageID(chapter: 5, index: 6),
        title: "複合 (四重踏み含む)",
        summary: "任意スポーンで四重踏みとトグルを裁き、36 手以内にまとめる複合課題です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter5Penalties,
            additionalVisitRequirements: stage56QuadVisit,
            toggleTilePoints: stage56Toggles,
            impassableTilePoints: stage56Impassable
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 36),
        scoreTarget: 450,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage55.id)
    )
    
    // 5-7: ペナルティ合計を抑えつつ障害物＋複数踏破＋トグルを管理。
    let stage57Impassable: Set<GridPoint> = [
        GridPoint(x: 1, y: 1),
        GridPoint(x: 3, y: 3),
        GridPoint(x: 2, y: 4)
    ]
    let stage57Additional: [GridPoint: Int] = [
        GridPoint(x: 0, y: 1): 2,
        GridPoint(x: 4, y: 3): 3
    ]
    let stage57Toggles: Set<GridPoint> = [
        GridPoint(x: 2, y: 2)
    ]
    let stage57 = CampaignStage(
        id: CampaignStageID(chapter: 5, index: 7),
        title: "複合 (多要素)",
        summary: "障害物と複数踏破・トグルを同時に管理し、ペナルティ合計 2 以下で攻略する最終調整です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter5Penalties,
            additionalVisitRequirements: stage57Additional,
            toggleTilePoints: stage57Toggles,
            impassableTilePoints: stage57Impassable
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
        scoreTarget: 440,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage56.id)
    )
    
    // 5-8: 34 手以内＆ペナルティ合計 2 以下で締める最終試験。
    let stage58Impassable: Set<GridPoint> = [
        GridPoint(x: 1, y: 1),
        GridPoint(x: 3, y: 3),
        GridPoint(x: 2, y: 2)
    ]
    let stage58Additional: [GridPoint: Int] = [
        GridPoint(x: 1, y: 4): 2,
        GridPoint(x: 3, y: 0): 3,
        GridPoint(x: 2, y: 4): 4
    ]
    let stage58Toggles: Set<GridPoint> = [
        GridPoint(x: 1, y: 3),
        GridPoint(x: 3, y: 1)
    ]
    let stage58 = CampaignStage(
        id: CampaignStageID(chapter: 5, index: 8),
        title: "最終試験",
        summary: "障害物・トグル・複数踏破を総動員し、34 手以内かつペナルティ合計 2 以下で仕上げる最終試験です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: .chooseAnyAfterPreview, // 中央を塞ぐ障害物と多重踏破の同居に合わせ、任意スポーンで整合性を確保
            penalties: chapter5Penalties,
            additionalVisitRequirements: stage58Additional,
            toggleTilePoints: stage58Toggles,
            impassableTilePoints: stage58Impassable
        ),
        secondaryObjective: .finishWithPenaltyAtMostAndWithinMoves(maxPenaltyCount: 2, maxMoves: 34),
        scoreTarget: 430,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage57.id)
    )
    
    let chapter5 = CampaignChapter(
        id: 5,
        title: "障害物攻略",
        summary: "障害物と複合ギミックを乗り越える章。",
        stages: [stage51, stage52, stage53, stage54, stage55, stage56, stage57, stage58]
    )
        return chapter5
    }
}
