import Foundation

extension CampaignLibrary {
    static func buildChapter6() -> CampaignChapter {
    // MARK: - 6 章のステージ群
    // ワープマスを活用した転送戦術を段階導入し、既存ギミックとの複合を通じて応用力を引き上げる。
    let chapter6Penalties = standardPenalties
    
    // 6-1: 最初のワープ導入。対角転送だけに絞り、40 手以内でワープ挙動を安全に学ぶ。
    let stage61WarpPairs: [String: [GridPoint]] = [
        "stage61_pair_main": [
            GridPoint(x: 0, y: 0),
            GridPoint(x: 4, y: 4)
        ]
    ]
    let stage61 = CampaignStage(
        id: CampaignStageID(chapter: 6, index: 1),
        title: "転送導入演習",
        summary: "対角ワープを使い、40 手以内で踏破するワープ基礎訓練です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: fixedSpawn5,
            penalties: chapter6Penalties,
            warpTilePairs: stage61WarpPairs
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 40),
        scoreTarget: 520,
        scoreTargetComparison: .lessThanOrEqual,
        // MARK: 第 6 章以降は「前章スター 12 個以上」で一律解放するため、章全体の達成度を評価する
        //       具体的には第 5 章でスターを 12 個以上獲得すれば挑戦可能とする
        unlockRequirement: .chapterTotalStars(chapter: 5, minimum: 12)
    )
    
    // 6-2: ワープペアを 2 組へ増やし、ペナルティ合計 2 以下を意識させる。
    let stage62WarpPairs: [String: [GridPoint]] = [
        "stage62_pair_cross": [
            GridPoint(x: 0, y: 4),
            GridPoint(x: 4, y: 0)
        ],
        "stage62_pair_center": [
            GridPoint(x: 1, y: 1),
            GridPoint(x: 3, y: 3)
        ]
    ]
    let stage62 = CampaignStage(
        id: CampaignStageID(chapter: 6, index: 2),
        title: "二重転送訓練",
        summary: "2 組のワープを調整し、ペナルティ合計 2 以下で安定させる応用演習です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: fixedSpawn5,
            penalties: chapter6Penalties,
            warpTilePairs: stage62WarpPairs
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
        scoreTarget: 510,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage61.id)
    )
    
    // 6-3: トグルを混在させ、ワープ後の踏破状態管理を体感する。38 手以内でテンポ維持を促す。
    let stage63WarpPairs: [String: [GridPoint]] = [
        "stage63_pair_center": [
            GridPoint(x: 1, y: 1),
            GridPoint(x: 3, y: 3)
        ]
    ]
    let stage63Toggles: Set<GridPoint> = [
        GridPoint(x: 2, y: 2)
    ]
    let stage63 = CampaignStage(
        id: CampaignStageID(chapter: 6, index: 3),
        title: "転送＋反転整備",
        summary: "中央トグルとワープを連携させ、38 手以内で踏破状態を整える訓練です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: fixedSpawn5,
            penalties: chapter6Penalties,
            toggleTilePoints: stage63Toggles,
            warpTilePairs: stage63WarpPairs
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 38),
        scoreTarget: 500,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage62.id)
    )
    
    // 6-4: 二度踏みを併用し、ワープ移動との往復で踏破回数を管理する。ペナルティは 1 以下を要求。
    let stage64WarpPairs: [String: [GridPoint]] = [
        "stage64_pair_cross": [
            GridPoint(x: 0, y: 4),
            GridPoint(x: 4, y: 0)
        ]
    ]
    let stage64DoubleVisit: [GridPoint: Int] = [
        GridPoint(x: 2, y: 2): 2
    ]
    let stage64 = CampaignStage(
        id: CampaignStageID(chapter: 6, index: 4),
        title: "転送＋多重踏破",
        summary: "ワープと二度踏みを両立させ、ペナルティ合計 1 以下でまとめる応用課題です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: fixedSpawn5,
            penalties: chapter6Penalties,
            additionalVisitRequirements: stage64DoubleVisit,
            warpTilePairs: stage64WarpPairs
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 1),
        scoreTarget: 490,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage63.id)
    )
    
    // 6-5: 任意スポーンと複数ワープを組み合わせ、36 手以内のルート最適化を求める。
    let stage65WarpPairs: [String: [GridPoint]] = [
        "stage65_pair_center": [
            GridPoint(x: 0, y: 0),
            GridPoint(x: 2, y: 2)
        ],
        "stage65_pair_oblique": [
            GridPoint(x: 1, y: 4),
            GridPoint(x: 4, y: 1)
        ],
        "stage65_pair_cross": [
            GridPoint(x: 0, y: 4),
            GridPoint(x: 4, y: 0)
        ]
    ]
    let stage65 = CampaignStage(
        id: CampaignStageID(chapter: 6, index: 5),
        title: "任意転送応用",
        summary: "任意スポーンで 3 組のワープを捌き、36 手以内に踏破する計画力を鍛えます。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter6Penalties,
            warpTilePairs: stage65WarpPairs
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 36),
        scoreTarget: 480,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage64.id)
    )
    
    // 6-6: 障害物を導入し、ワープ地点の安全確認とルート修正力を養う。ペナルティ合計 2 以下を維持させる。
    let stage66WarpPairs: [String: [GridPoint]] = [
        "stage66_pair_center": [
            GridPoint(x: 1, y: 1),
            GridPoint(x: 3, y: 3)
        ]
    ]
    let stage66Impassable: Set<GridPoint> = [
        GridPoint(x: 2, y: 2)
    ]
    let stage66 = CampaignStage(
        id: CampaignStageID(chapter: 6, index: 6),
        title: "転送＋障害回避",
        summary: "中央障害物とワープを同時管理し、ペナルティ合計 2 以下で踏破する防衛練習です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter6Penalties,
            impassableTilePoints: stage66Impassable,
            warpTilePairs: stage66WarpPairs
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
        scoreTarget: 470,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage65.id)
    )
    
    // 6-7: ワープ＋トグル＋三重踏みの統合。34 手以内で高密度な処理を求める。
    let stage67WarpPairs: [String: [GridPoint]] = [
        "stage67_pair_diagonal": [
            GridPoint(x: 0, y: 0),
            GridPoint(x: 4, y: 4)
        ]
    ]
    let stage67Toggles: Set<GridPoint> = [
        GridPoint(x: 1, y: 1),
        GridPoint(x: 3, y: 3)
    ]
    let stage67TripleVisit: [GridPoint: Int] = [
        GridPoint(x: 2, y: 2): 3
    ]
    let stage67 = CampaignStage(
        id: CampaignStageID(chapter: 6, index: 7),
        title: "転送統合課題",
        summary: "ワープ・トグル・三重踏みを統合し、34 手以内で仕上げる高密度ステージです。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter6Penalties,
            additionalVisitRequirements: stage67TripleVisit,
            toggleTilePoints: stage67Toggles,
            warpTilePairs: stage67WarpPairs
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 34),
        scoreTarget: 460,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage66.id)
    )
    
    // 6-8: 最終演習。障害物・トグル・複数ワープを固定スポーンで裁き、ペナルティ合計 2 以下かつ 32 手以内で締める。
    let stage68WarpPairs: [String: [GridPoint]] = [
        "stage68_pair_cross": [
            GridPoint(x: 0, y: 4),
            GridPoint(x: 4, y: 0)
        ],
        "stage68_pair_inner": [
            GridPoint(x: 1, y: 3),
            GridPoint(x: 3, y: 1)
        ]
    ]
    let stage68Impassable: Set<GridPoint> = [
        GridPoint(x: 0, y: 0)
    ]
    let stage68Toggles: Set<GridPoint> = [
        GridPoint(x: 2, y: 2)
    ]
    let stage68 = CampaignStage(
        id: CampaignStageID(chapter: 6, index: 8),
        title: "転送最終演習",
        summary: "障害物とワープを固定スポーンで裁き、ペナルティ合計 2 以下＆32 手以内で完成させる最終試験です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: fixedSpawn5,
            penalties: chapter6Penalties,
            toggleTilePoints: stage68Toggles,
            impassableTilePoints: stage68Impassable,
            warpTilePairs: stage68WarpPairs
        ),
        secondaryObjective: .finishWithPenaltyAtMostAndWithinMoves(maxPenaltyCount: 2, maxMoves: 32),
        scoreTarget: 450,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage67.id)
    )
    
    let chapter6 = CampaignChapter(
        id: 6,
        title: "転送戦術",
        summary: "ワープマスを軸に踏破ルートを再設計する章。",
        stages: [stage61, stage62, stage63, stage64, stage65, stage66, stage67, stage68]
    )
        return chapter6
    }
}
