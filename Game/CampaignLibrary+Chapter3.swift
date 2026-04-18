import Foundation

extension CampaignLibrary {
    static func buildChapter3() -> CampaignChapter {
    // MARK: - 3 章のステージ群
    // 選択カードを段階導入し、終盤は複数踏破ギミックと組み合わせる。
    let standardPenalties = unifiedMidCampaignPenalties
    
    // 3-1: 4×4 盤でキング＋ナイト基礎デッキに縦横選択カードを加え、短距離での判断力を鍛える。
    let stage31 = CampaignStage(
        id: CampaignStageID(chapter: 3, index: 1),
        title: "縦横選択チュートリアル",
        summary: "4×4 盤でキング＋ナイト基礎デッキに上下左右選択キングを加え、ペナルティ合計 2 以下を意識しつつ短距離操作を磨きましょう。",
        regulation: GameMode.Regulation(
            boardSize: 4,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingAndKnightWithOrthogonalChoices,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 4)),
            penalties: standardPenalties
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
        scoreTarget: 600,
        scoreTargetComparison: .lessThanOrEqual,
        // MARK: 第 3 章も前章スター総数 12 個以上で解放し、到達ハードルを統一する
        //       章ごとに「1-1 は常時解放、以降は前章スター 12 個以上」を徹底するための設定
        unlockRequirement: .chapterTotalStars(chapter: 2, minimum: 12)
    )
    
    // 3-2: 5×5 盤へ拡張し、キング＋ナイト基礎デッキに縦横選択カードを加えた構成で 40 手以内を目指す。
    let stage32 = CampaignStage(
        id: CampaignStageID(chapter: 3, index: 2),
        title: "縦横基礎",
        summary: "5×5 盤でキング＋ナイト基礎デッキに上下左右選択キングを組み合わせ、40 手以内で踏破する計画力を養います。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingAndKnightWithOrthogonalChoices,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
            penalties: standardPenalties
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 40),
        scoreTarget: 590,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage31.id)
    )
    
    // 3-3: 斜め選択キングを導入し、キング＋ナイト基礎デッキのまま角マス攻略を学ぶ。
    let stage33 = CampaignStage(
        id: CampaignStageID(chapter: 3, index: 3),
        title: "斜め選択入門",
        summary: "キング＋ナイト基礎デッキに斜め選択キングを足し、ペナルティ合計 2 以下で角マスを制圧します。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingAndKnightWithDiagonalChoices,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
            penalties: standardPenalties
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
        scoreTarget: 580,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage32.id)
    )
    
    // 3-4: 桂馬選択カードを導入し、キング＋ナイト基礎デッキの跳躍力を拡張して 38 手以内を狙う。
    let stage34 = CampaignStage(
        id: CampaignStageID(chapter: 3, index: 4),
        title: "桂馬選択入門",
        summary: "キング＋ナイト基礎デッキに桂馬選択カードを加え、38 手以内で巡回する応用演習です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingAndKnightWithKnightChoices,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
            penalties: standardPenalties
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 38),
        scoreTarget: 570,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage33.id)
    )
    
    // 3-5: 任意スポーン＋二度踏みで 36 手以内の調整力を試す。
    let stage35DoubleVisit: [GridPoint: Int] = [
        GridPoint(x: 1, y: 1): 2,
        GridPoint(x: 3, y: 3): 2
    ]
    let stage35 = CampaignStage(
        id: CampaignStageID(chapter: 3, index: 5),
        title: "選択＋二度踏み",
        summary: "任意スポーンで二度踏みマスを制御し、36 手以内でまとめる応用ステージです。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithOrthogonalChoices,
            spawnRule: .chooseAnyAfterPreview,
            penalties: standardPenalties,
            additionalVisitRequirements: stage35DoubleVisit
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 36),
        scoreTarget: 560,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage34.id)
    )
    
    // 3-6: 全選択カードで三重踏みを処理し、ペナルティ合計 1 以下で安定攻略する。
    let stage36TripleVisit: [GridPoint: Int] = [
        GridPoint(x: 2, y: 2): 3,
        GridPoint(x: 3, y: 1): 3
    ]
    let stage36 = CampaignStage(
        id: CampaignStageID(chapter: 3, index: 6),
        title: "全選択＋三重踏み",
        summary: "全方向の選択カードを駆使し、三重踏みマスをペナルティ合計 1 以下で処理します。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
            penalties: standardPenalties,
            additionalVisitRequirements: stage36TripleVisit
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 1),
        scoreTarget: 550,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage35.id)
    )
    
    // 3-7: 任意スポーン＋四重踏みで 36 手以内の高速巡回を狙う。
    let stage37QuadVisit: [GridPoint: Int] = [
        GridPoint(x: 1, y: 1): 4,
        GridPoint(x: 3, y: 3): 4
    ]
    let stage37 = CampaignStage(
        id: CampaignStageID(chapter: 3, index: 7),
        title: "全選択＋四重踏み",
        summary: "内側に配置された四重踏みを全選択カードで制御し、36 手以内を目指す高難度ステージです。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: .chooseAnyAfterPreview,
            penalties: standardPenalties,
            additionalVisitRequirements: stage37QuadVisit
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 36),
        scoreTarget: 540,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage36.id)
    )
    
    // 3-8: ペナルティ合計 2 以下かつ 36 手以内を同時達成する総合演習。
    let stage38MixedVisit: [GridPoint: Int] = [
        GridPoint(x: 1, y: 1): 2,
        GridPoint(x: 2, y: 2): 3,
        GridPoint(x: 3, y: 3): 4
    ]
    let stage38 = CampaignStage(
        id: CampaignStageID(chapter: 3, index: 8),
        title: "総合演習",
        summary: "2/3/4 回踏みを組み合わせ、ペナルティ合計 2 以下かつ 36 手以内を達成する総仕上げです。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithAllChoices,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
            penalties: standardPenalties,
            additionalVisitRequirements: stage38MixedVisit
        ),
        secondaryObjective: .finishWithPenaltyAtMostAndWithinMoves(maxPenaltyCount: 2, maxMoves: 36),
        scoreTarget: 530,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage37.id)
    )
    
    let chapter3 = CampaignChapter(
        id: 3,
        title: "多方向訓練",
        summary: "選択カードと複数踏破を段階導入する章。",
        stages: [stage31, stage32, stage33, stage34, stage35, stage36, stage37, stage38]
    )
        return chapter3
    }
}
