import Foundation

extension CampaignLibrary {
    static func buildChapter8() -> CampaignChapter {
    // MARK: - 8 章のステージ群
    // ワープカードとスーパーワープカードを主役に据え、既存ギミックとの複合制御力を確認する終盤章。
    let chapter8Penalties = standardPenalties
    
    // 8-1: 固定ワープを高頻度で配布し、目的地ローテーションと瞬間転移を 38 手以内で学ぶ導入ステージ。
    let stage81 = CampaignStage(
        id: CampaignStageID(chapter: 8, index: 1),
        title: "固定ワープ基礎",
        summary: "固定ワープカードを高頻度で引き込みつつ、基礎移動で微調整しながら 38 手以内に踏破ルートを整える基礎訓練です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .fixedWarpSpecialized,
            spawnRule: fixedSpawn5,
            penalties: chapter8Penalties
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 38),
        scoreTarget: 400,
        scoreTargetComparison: .lessThanOrEqual,
        // MARK: 第 8 章も前章スター 12 個以上で解放し、最終章到達条件を統一する
        unlockRequirement: .chapterTotalStars(chapter: 7, minimum: 12)
    )
    
    // 8-2: 全域ワープを高頻度で引ける構成で盤面全域の瞬間移動を練習し、ペナルティ合計 2 以下の冷静な運用を求める。
    let stage82 = CampaignStage(
        id: CampaignStageID(chapter: 8, index: 2),
        title: "全域ワープ試験",
        summary: "全域ワープカードを高頻度で引き込み、ペナルティ合計 2 以下に抑えて瞬間転移ルートを構築する試験です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .superWarpHighFrequency,
            spawnRule: fixedSpawn5,
            penalties: chapter8Penalties
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
        scoreTarget: 395,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage81.id)
    )
    
    // 8-3: ここからは固定／全域ワープをバランス投入した標準構成へ移行し、中央障害物との併用で 36 手以内の迅速攻略を鍛える。
    let stage83Impassable: Set<GridPoint> = [
        GridPoint(x: 2, y: 2)
    ]
    let stage83 = CampaignStage(
        id: CampaignStageID(chapter: 8, index: 3),
        title: "障害物併用演習",
        summary: "中央障害物を避けつつワープカードを活用し、36 手以内で収める応用演習です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithWarpCards,
            // 中央を障害物で塞ぐため、初期手詰まりを防ぐ目的で任意スポーンへ切り替える
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter8Penalties,
            impassableTilePoints: stage83Impassable
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 36),
        scoreTarget: 390,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage82.id)
    )
    
    // 8-4: トグルマスとバランス型ワープデッキの組み合わせで踏破状況の再編成力を確認し、34 手以内の短期決戦に設定。
    let stage84Toggles: Set<GridPoint> = [
        GridPoint(x: 1, y: 1),
        GridPoint(x: 3, y: 3)
    ]
    let stage84 = CampaignStage(
        id: CampaignStageID(chapter: 8, index: 4),
        title: "反転連動演習",
        summary: "トグルマスとスーパーワープを連動させ、34 手以内で盤面を制御する演習です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithWarpCards,
            spawnRule: fixedSpawn5,
            penalties: chapter8Penalties,
            toggleTilePoints: stage84Toggles
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 34),
        scoreTarget: 385,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage83.id)
    )
    
    // 8-5: 任意スポーンと二度踏みを導入し、バランス型ワープデッキで再配置ルートを描く。ペナルティ合計 2 以下が条件。
    let stage85AdditionalVisits: [GridPoint: Int] = [
        GridPoint(x: 2, y: 2): 2
    ]
    let stage85 = CampaignStage(
        id: CampaignStageID(chapter: 8, index: 5),
        title: "任意転移演習",
        summary: "任意スポーンと二度踏みを組み合わせ、ペナルティ合計 2 以下で仕上げる転移演習です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithWarpCards,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter8Penalties,
            additionalVisitRequirements: stage85AdditionalVisits
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
        scoreTarget: 380,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage84.id)
    )
    
    // 8-6: ワープタイルとワープカードを混成させ、バランス型デッキで 32 手以内の広域転移制御を目指す。
    let stage86WarpPairs: [String: [GridPoint]] = [
        "stage86_pair_cross": [
            GridPoint(x: 0, y: 4),
            GridPoint(x: 4, y: 0)
        ]
    ]
    let stage86 = CampaignStage(
        id: CampaignStageID(chapter: 8, index: 6),
        title: "デッキ混成実戦",
        summary: "ワープタイルとワープカードを併用し、32 手以内で踏破する実戦形式ステージです。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithWarpCards,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter8Penalties,
            warpTilePairs: stage86WarpPairs
        ),
        secondaryObjective: .finishWithinMoves(maxMoves: 32),
        scoreTarget: 375,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage85.id)
    )
    
    // 8-7: トグルと障害物を絡めた終盤演習。バランス型デッキでペナルティ合計 1 以下の冷静さが求められる。
    let stage87Toggles: Set<GridPoint> = [
        GridPoint(x: 2, y: 2)
    ]
    let stage87Impassable: Set<GridPoint> = [
        GridPoint(x: 1, y: 1)
    ]
    let stage87 = CampaignStage(
        id: CampaignStageID(chapter: 8, index: 7),
        title: "空間支配課題",
        summary: "トグルと障害物を制御しながらワープカードを扱い、ペナルティ合計 1 以下で締める課題です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithWarpCards,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter8Penalties,
            toggleTilePoints: stage87Toggles,
            impassableTilePoints: stage87Impassable
        ),
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 1),
        scoreTarget: 370,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage86.id)
    )
    
    // 8-8: 終章最終試験。二度踏み・トグル・障害物を同時管理しつつ、バランス型デッキに含まれるワープカードで局面を打開する。
    let stage88AdditionalVisits: [GridPoint: Int] = [
        GridPoint(x: 3, y: 1): 2
    ]
    let stage88Toggles: Set<GridPoint> = [
        GridPoint(x: 1, y: 3)
    ]
    let stage88Impassable: Set<GridPoint> = [
        GridPoint(x: 0, y: 0)
    ]
    let stage88 = CampaignStage(
        id: CampaignStageID(chapter: 8, index: 8),
        title: "空間支配最終試験",
        summary: "ワープカードを駆使し、30 手以内＆ペナルティ合計 1 以下で空間支配を完成させる最終試験です。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardWithWarpCards,
            spawnRule: .chooseAnyAfterPreview,
            penalties: chapter8Penalties,
            additionalVisitRequirements: stage88AdditionalVisits,
            toggleTilePoints: stage88Toggles,
            impassableTilePoints: stage88Impassable
        ),
        secondaryObjective: .finishWithPenaltyAtMostAndWithinMoves(maxPenaltyCount: 1, maxMoves: 30),
        scoreTarget: 365,
        scoreTargetComparison: .lessThanOrEqual,
        unlockRequirement: .stageClear(stage87.id)
    )
    
    let chapter8 = CampaignChapter(
        id: 8,
        title: "空間支配",
        summary: "固定ワープから全域ワープまで段階的に習熟し、最終的に両者を併用して盤面を掌握する章。",
        stages: [stage81, stage82, stage83, stage84, stage85, stage86, stage87, stage88]
    )
        return chapter8
    }
}
