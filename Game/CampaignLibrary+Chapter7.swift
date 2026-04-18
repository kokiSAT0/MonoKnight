import Foundation

extension CampaignLibrary {
    static func buildChapter7() -> CampaignChapter {
    // MARK: - 7 章のステージ群
    // 複数マス移動カードを常設し、後半でシャッフルマスを追加して手札の変動管理を練習させる章。
    let chapter7Penalties = standardPenalties
    
    // 7-1: 新カード導入。複数マス移動カードで 38 手以内クリアを目指し、基本挙動を把握する。
    let stage71 = CampaignStage(
        id: CampaignStageID(chapter: 7, index: 1),
        title: "拡張移動導入",
        summary: "複数マス移動カードを試し、38 手以内で踏破する導入ステージです。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .extendedWithMultiStepMoves,
            spawnRule: fixedSpawn5,
            penalties: chapter7Penalties
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 38),
        scoreTarget: 440,
        scoreTargetComparison: .lessThanOrEqual,
        // MARK: 第 7 章も前章スター 12 個以上で解放し、ステージ 7-1 の挑戦条件を明確化する
        unlockRequirement: .chapterTotalStars(chapter: 6, minimum: 12)
    )
    
    // 7-2: 桂馬強化カードの重み増しを想定した応用編。ペナルティ合計 2 以下で安定させる。
    let stage72 = CampaignStage(
        id: CampaignStageID(chapter: 7, index: 2),
        title: "拡張移動応用",
        summary: "複数マス移動と桂馬サポートを組み合わせ、ペナルティ合計 2 以下を狙う応用課題です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .extendedWithMultiStepMoves,
            spawnRule: fixedSpawn5,
            penalties: chapter7Penalties
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
        scoreTarget: 435,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage71.id)
    )
    
    // 7-3: 中央障害物を配置し、複数マス移動カードでの経路修正力を高める。中央が封鎖されるため任意スポーンへ切り替え、36 手以内を要求。
    let stage73Impassable: Set<GridPoint> = [
        GridPoint(x: 2, y: 2)
    ]
    let stage73 = CampaignStage(
        id: CampaignStageID(chapter: 7, index: 3),
        title: "障害回避演習",
        summary: "中央障害物を避けながら 36 手以内で踏破する複数マス移動の応用演習です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .extendedWithMultiStepMoves,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter7Penalties,
            impassableTilePoints: stage73Impassable
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 36),
        scoreTarget: 430,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage72.id)
    )
    
    // 7-4: 二度踏みマスを配置し、直線 3 マス移動の活用でリズム良く処理する。ペナルティ合計 1 以下を条件にする。
    let stage74AdditionalVisits: [GridPoint: Int] = [
        GridPoint(x: 1, y: 1): 2,
        GridPoint(x: 3, y: 3): 2
    ]
    let stage74 = CampaignStage(
        id: CampaignStageID(chapter: 7, index: 4),
        title: "直線連携訓練",
        summary: "二度踏みマスを直線移動で裁き、ペナルティ合計 1 以下を目指す連携トレーニングです。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .extendedWithMultiStepMoves,
            spawnRule: fixedSpawn5,
            penalties: chapter7Penalties,
            additionalVisitRequirements: stage74AdditionalVisits
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 1),
        scoreTarget: 425,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage73.id)
    )
    
    // 7-5: シャッフルマス初登場。任意スポーン化で事故を抑えつつ、36 手以内にまとめる。
    let stage75Shuffle: [GridPoint: TileEffect] = [
        GridPoint(x: 2, y: 2): .shuffleHand
    ]
    let stage75 = CampaignStage(
        id: CampaignStageID(chapter: 7, index: 5),
        title: "シャッフル導入",
        summary: "中央シャッフルマスを踏みつつ、36 手以内で安定攻略する導入ステージです。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .extendedWithMultiStepMoves,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter7Penalties,
            tileEffectOverrides: stage75Shuffle
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 36),
        scoreTarget: 420,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage74.id)
    )
    
    // 7-6: シャッフルと障害物を組み合わせ、ペナルティ合計 2 以下を保ちながら手札再構成に対応する。
    let stage76Shuffle: [GridPoint: TileEffect] = [
        GridPoint(x: 2, y: 2): .shuffleHand
    ]
    let stage76Impassable: Set<GridPoint> = [
        GridPoint(x: 1, y: 3)
    ]
    let stage76 = CampaignStage(
        id: CampaignStageID(chapter: 7, index: 6),
        title: "シャッフル応用",
        summary: "シャッフルと障害物の両立を図り、ペナルティ合計 2 以下で収める応用課題です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .extendedWithMultiStepMoves,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter7Penalties,
            impassableTilePoints: stage76Impassable,
            tileEffectOverrides: stage76Shuffle
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
        scoreTarget: 415,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage75.id)
    )
    
    // 7-7: シャッフルとトグルを同時制御し、34 手以内で複合ギミックを捌く。任意スポーンで初手詰みを回避する。
    let stage77Shuffle: [GridPoint: TileEffect] = [
        GridPoint(x: 2, y: 2): .shuffleHand
    ]
    let stage77Toggles: Set<GridPoint> = [
        GridPoint(x: 1, y: 1),
        GridPoint(x: 3, y: 3)
    ]
    let stage77 = CampaignStage(
        id: CampaignStageID(chapter: 7, index: 7),
        title: "複合行動課題",
        summary: "シャッフルとトグルを併用し、34 手以内でルートをまとめる複合行動ステージです。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .extendedWithMultiStepMoves,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter7Penalties,
            toggleTilePoints: stage77Toggles,
            tileEffectOverrides: stage77Shuffle
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 34),
        scoreTarget: 410,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage76.id)
    )
    
    // 7-8: シャッフル・二度踏み・障害物を集約した総決算。32 手以内かつペナルティ合計 2 以下を条件とする。
    let stage78Shuffle: [GridPoint: TileEffect] = [
        GridPoint(x: 0, y: 0): .shuffleHand,
        GridPoint(x: 4, y: 4): .shuffleHand
    ]
    let stage78AdditionalVisits: [GridPoint: Int] = [
        GridPoint(x: 2, y: 2): 2
    ]
    let stage78Impassable: Set<GridPoint> = [
        GridPoint(x: 1, y: 1)
    ]
    let stage78 = CampaignStage(
        id: CampaignStageID(chapter: 7, index: 8),
        title: "拡張行動総決算",
        summary: "シャッフル・二度踏み・障害物を乗り越え、32 手以内＆ペナルティ合計 2 以下で締める総仕上げです。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .extendedWithMultiStepMoves,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter7Penalties,
            additionalVisitRequirements: stage78AdditionalVisits,
            impassableTilePoints: stage78Impassable,
            tileEffectOverrides: stage78Shuffle
        ),
        secondaryObjective: .finishWithPenaltyAtMostAndWithinMoves(maxPenaltyCount: 2, maxMoves: 32),
        scoreTarget: 405,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage77.id)
    )
    
    let chapter7 = CampaignChapter(
        id: 7,
        title: "拡張行動",
        summary: "複数マス移動カードとシャッフルマスで行動拡張力を養う章。",
        stages: [stage71, stage72, stage73, stage74, stage75, stage76, stage77, stage78]
    )
        return chapter7
    }
}
