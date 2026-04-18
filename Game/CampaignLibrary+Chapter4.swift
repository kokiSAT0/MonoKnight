import Foundation

extension CampaignLibrary {
    static func buildChapter4() -> CampaignChapter {
    // MARK: - 4 章のステージ群
    // トグルマスと複数踏破を組み合わせ、反転挙動への理解を深める。
    let chapter4Penalties = standardPenalties
    let fixedSpawn5 = GameMode.SpawnRule.fixed(BoardGeometry.defaultSpawnPoint(for: 5))
    
    // 4-1: 基本のトグル 2 箇所を 30 手以内で制御。
    let stage41Toggles: Set<GridPoint> = [
        GridPoint(x: 1, y: 1),
        GridPoint(x: 3, y: 3)
    ]
    let stage41 = CampaignStage(
        id: CampaignStageID(chapter: 4, index: 1),
        title: "トグル基礎",
        summary: "2 箇所のトグルマスを操作し、30 手以内で反転ギミックに慣れる導入ステージです。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardLight,
            spawnRule: fixedSpawn5,
            penalties: chapter4Penalties,
            toggleTilePoints: stage41Toggles
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 30),
        scoreTarget: 520,
        scoreTargetComparison: .lessThanOrEqual,
        // MARK: 第 4 章も前章スター 12 個以上で解放し、章を跨ぐ進行条件を統一する
        unlockRequirement: .chapterTotalStars(chapter: 3, minimum: 12)
    )
    
    // 4-2: トグル 3 箇所でペナルティ合計 2 以下に抑える。
    let stage42Toggles: Set<GridPoint> = [
        GridPoint(x: 2, y: 2),
        GridPoint(x: 1, y: 3),
        GridPoint(x: 3, y: 1)
    ]
    let stage42 = CampaignStage(
        id: CampaignStageID(chapter: 4, index: 2),
        title: "トグル応用",
        summary: "3 箇所のトグルを捌き、ペナルティ合計 2 以下で制御する応用演習です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardLight,
            spawnRule: fixedSpawn5,
            penalties: chapter4Penalties,
            toggleTilePoints: stage42Toggles
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
        scoreTarget: 510,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage41.id)
    )
    
    // 4-3: トグルと二度踏みを組み合わせ、40 手以内でまとめる。
    let stage43DoubleVisit: [GridPoint: Int] = [
        GridPoint(x: 0, y: 2): 2,
        GridPoint(x: 4, y: 2): 2
    ]
    let stage43 = CampaignStage(
        id: CampaignStageID(chapter: 4, index: 3),
        title: "トグル＋二度踏み",
        summary: "左右に伸びる二度踏みマスとトグル制御を両立し、40 手以内を目指す課題です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardLight,
            spawnRule: fixedSpawn5,
            penalties: chapter4Penalties,
            additionalVisitRequirements: stage43DoubleVisit,
            toggleTilePoints: stage41Toggles
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 40),
        scoreTarget: 500,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage42.id)
    )
    
    // 4-4: 全選択カードへ切り替え、三重踏みをペナルティ合計 1 以下で管理。
    let stage44TripleVisit: [GridPoint: Int] = [
        GridPoint(x: 2, y: 2): 3
    ]
    let stage44 = CampaignStage(
        id: CampaignStageID(chapter: 4, index: 4),
        title: "トグル＋三重踏み",
        summary: "中央の三重踏みとトグルを同時に管理し、ペナルティ合計 1 以下でクリアする応用です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: fixedSpawn5,
            penalties: chapter4Penalties,
            additionalVisitRequirements: stage44TripleVisit,
            toggleTilePoints: stage41Toggles
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 1),
        scoreTarget: 490,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage43.id)
    )
    
    // 4-5: 任意スポーンで四隅のトグルを 38 手以内に制御。
    let stage45Toggles: Set<GridPoint> = [
        GridPoint(x: 0, y: 0),
        GridPoint(x: 4, y: 0),
        GridPoint(x: 0, y: 4),
        GridPoint(x: 4, y: 4)
    ]
    let stage45 = CampaignStage(
        id: CampaignStageID(chapter: 4, index: 5),
        title: "トグル集中制御",
        summary: "任意スポーンで四隅トグルの順番を調整し、38 手以内に踏破する訓練です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter4Penalties,
            toggleTilePoints: stage45Toggles
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 38),
        scoreTarget: 480,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage44.id)
    )
    
    // 4-6: 四重踏みを追加し、36 手以内で速度感を鍛える。
    let stage46QuadVisit: [GridPoint: Int] = [
        GridPoint(x: 2, y: 2): 4
    ]
    let stage46 = CampaignStage(
        id: CampaignStageID(chapter: 4, index: 6),
        title: "トグル＋四重踏み",
        summary: "中央の四重踏みとトグルを組み合わせ、36 手以内でまとめる高速課題です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter4Penalties,
            additionalVisitRequirements: stage46QuadVisit,
            toggleTilePoints: stage41Toggles
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 36),
        scoreTarget: 470,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage45.id)
    )
    
    // 4-7: ペナルティ合計を厳しく抑えた状態で複合ギミックを扱う。
    let stage47Additional: [GridPoint: Int] = [
        GridPoint(x: 0, y: 2): 2,
        GridPoint(x: 4, y: 2): 2,
        GridPoint(x: 2, y: 2): 3
    ]
    let stage47 = CampaignStage(
        id: CampaignStageID(chapter: 4, index: 7),
        title: "トグル＋複合踏破",
        summary: "二度踏みと三重踏みをトグルと併用し、ペナルティ合計 2 以下で攻略する高難度課題です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter4Penalties,
            additionalVisitRequirements: stage47Additional,
            toggleTilePoints: stage41Toggles
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
        scoreTarget: 460,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage46.id)
    )
    
    // 4-8: 34 手以内＆ペナルティ合計 2 以下で締める総合試験。
    let stage48Additional: [GridPoint: Int] = [
        GridPoint(x: 1, y: 0): 2,
        GridPoint(x: 3, y: 0): 3,
        GridPoint(x: 2, y: 2): 4
    ]
    let stage48Toggles: Set<GridPoint> = [
        GridPoint(x: 1, y: 1),
        GridPoint(x: 3, y: 3),
        GridPoint(x: 2, y: 4)
    ]
    let stage48 = CampaignStage(
        id: CampaignStageID(chapter: 4, index: 8),
        title: "総合演習",
        summary: "トグルと複数踏破を総動員し、34 手以内かつペナルティ合計 2 以下で踏破する最終試験です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: fixedSpawn5,
            penalties: chapter4Penalties,
            additionalVisitRequirements: stage48Additional,
            toggleTilePoints: stage48Toggles
        ),
        secondaryObjective: .finishWithPenaltyAtMostAndWithinMoves(maxPenaltyCount: 2, maxMoves: 34),
        scoreTarget: 450,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage47.id)
    )
    
    let chapter4 = CampaignChapter(
        id: 4,
        title: "反転応用",
        summary: "トグルと複数踏破を組み合わせる章。",
        stages: [stage41, stage42, stage43, stage44, stage45, stage46, stage47, stage48]
    )
        return chapter4
    }
}
