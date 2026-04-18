import Foundation

extension CampaignLibrary {
    static func buildChapter1() -> CampaignChapter {
    // MARK: - 1 章のステージ群
    // MARK: 章 1 のステージレギュレーション共通設定
    // 章内で複数のステージが同一ルールを参照する場合に備え、先に共通変数へ切り出しておく。
    // 1-1 は 3×3 盤かつ王将型カードのみで構成された超短距離訓練ステージ。
    // ペナルティは +2 系で揃え、序盤のリトライに優しい難度へ調整する。
    let stage11 = CampaignStage(
        id: CampaignStageID(chapter: 1, index: 1),
        title: "王将訓練",
        summary: "3×3 の盤で王将カードだけを使い、基本の詰めを体験しましょう。",
        regulation: GameMode.Regulation(
            boardSize: 3,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingOnly,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 3)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 2,
                manualRedrawPenaltyCost: 2,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 1
            )
        ),
        // MARK: 2 個目のスター条件: 60 秒以内クリアで序盤からテンポを意識させる
        secondaryObjective: .finishWithinSeconds(maxSeconds: 60),
        scoreTarget: 300,
        scoreTargetComparison: .lessThan,
        // MARK: スタート地点となるため常時解放として整理する
        unlockRequirement: .always
    )
    
    // 1-2 はキングと桂馬の最小構成で、ペナルティ合計 5 以下を目指す導入ステージ。
    let stage12 = CampaignStage(
        id: CampaignStageID(chapter: 1, index: 2),
        title: "ナイト初見",
        summary: "キングと桂馬だけの 3×3 で、跳躍移動の感覚を掴みましょう。",
        regulation: GameMode.Regulation(
            boardSize: 3,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingPlusKnightOnly,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 3)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 2,
                manualRedrawPenaltyCost: 2,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            )
        ),
        // MARK: 2 個目のスター条件: ペナルティ合計 3 以下で締め、リトライ負荷を抑える
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 3),
        scoreTarget: 300,
        scoreTargetComparison: .lessThan,
        unlockRequirement: .stageClear(stage11.id)
    )
    
    // 1-3 は 4×4 盤への移行。キング＆桂馬基礎デッキで持ち時間 60 秒以内を狙う。
    let stage13 = CampaignStage(
        id: CampaignStageID(chapter: 1, index: 3),
        title: "4×4基礎",
        summary: "4×4 盤でキングと桂馬の動きを整理し、視野を一段広げましょう。",
        regulation: GameMode.Regulation(
            boardSize: 4,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingAndKnightBasic,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 4)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 3,
                manualRedrawPenaltyCost: 1,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            )
        ),
        // MARK: 2 個目のスター条件: 60 秒以内に踏破してテンポ良く盤面を巡回する
        secondaryObjective: .finishWithinSeconds(maxSeconds: 60),
        scoreTarget: 400,
        scoreTargetComparison: .lessThan,
        unlockRequirement: .stageClear(stage12.id)
    )
    
    // 1-4 は同じデッキで任意スポーンを導入し、ルート計画力を育てる。
    let stage14 = CampaignStage(
        id: CampaignStageID(chapter: 1, index: 4),
        title: "4×4応用",
        summary: "好きな開始マスを選び、4×4 で最適な踏破順を描きましょう。",
        regulation: GameMode.Regulation(
            boardSize: 4,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingAndKnightBasic,
            spawnRule: .chooseAnyAfterPreview,
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 3,
                manualRedrawPenaltyCost: 1,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            )
        ),
        // MARK: 2 個目のスター条件: ペナルティ合計 5 以下へ抑え、冷静な判断を促す
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 5),
        scoreTarget: 400,
        scoreTargetComparison: .lessThan,
        unlockRequirement: .stageClear(stage13.id)
    )
    
    // 1-5 はスタンダード軽量デッキで持久戦。手数 30 以内を目指す。
    let stage15 = CampaignStage(
        id: CampaignStageID(chapter: 1, index: 5),
        title: "4×4持久",
        summary: "長距離カードを抑えた 4×4 で、丁寧にルートを構築しましょう。",
        regulation: GameMode.Regulation(
            boardSize: 4,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardLight,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 4)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 3,
                manualRedrawPenaltyCost: 2,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            )
        ),
        // MARK: 2 個目のスター条件: 手数 30 以内を要求し、正確な踏破計画を促す
        secondaryObjective: .finishWithinMoves(maxMoves: 30),
        scoreTarget: 400,
        scoreTargetComparison: .lessThan,
        unlockRequirement: .stageClear(stage14.id)
    )
    
    // 1-6 は再び任意スポーンを採用し、ペナルティ合計 3 以下を狙う実戦訓練。
    let stage16 = CampaignStage(
        id: CampaignStageID(chapter: 1, index: 6),
        title: "4×4戦略",
        summary: "開始位置を自由に選び、ペナルティ合計 3 以下で踏破する戦略を組みましょう。",
        regulation: GameMode.Regulation(
            boardSize: 4,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .kingAndKnightBasic,
            spawnRule: .chooseAnyAfterPreview,
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 3,
                manualRedrawPenaltyCost: 2,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            )
        ),
        // MARK: 2 個目のスター条件: ペナルティ合計 3 以下で終える集中力を養う
        secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 3),
        scoreTarget: 400,
        scoreTargetComparison: .lessThan,
        unlockRequirement: .stageClear(stage15.id)
    )
    
    // 1-7 は 5×5 盤を初めて扱う導入ステージ。スタンダード軽量構成で手数 40 以内を狙う。
    let stage17 = CampaignStage(
        id: CampaignStageID(chapter: 1, index: 7),
        title: "5×5導入",
        summary: "5×5 盤に挑み、長丁場でも安定して踏破する力を養いましょう。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardLight,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 3,
                manualRedrawPenaltyCost: 2,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            )
        ),
        // MARK: 2 個目のスター条件: 40 手以内にまとめ、5×5 の巡回感覚を掴んでもらう
        secondaryObjective: .finishWithinMoves(maxMoves: 40),
        scoreTarget: 460,
        scoreTargetComparison: .lessThan,
        unlockRequirement: .stageClear(stage16.id)
    )
    
    // 1-8 は 5×5 での総合演習。任意スポーンを活かし、35 手以内を狙う。
    let stage18 = CampaignStage(
        id: CampaignStageID(chapter: 1, index: 8),
        title: "総合演習",
        summary: "任意の開始位置から 5×5 全域を巡り、総仕上げとして踏破しましょう。",
        regulation: GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standardLight,
            spawnRule: .chooseAnyAfterPreview,
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 3,
                manualRedrawPenaltyCost: 2,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            )
        ),
        // MARK: 2 個目のスター条件: 35 手以内に踏破し、戦略・リスク管理の両立を狙う
        secondaryObjective: .finishWithinMoves(maxMoves: 35),
        scoreTarget: 440,
        scoreTargetComparison: .lessThan,
        unlockRequirement: .stageClear(stage17.id)
    )
    
    let chapter1 = CampaignChapter(
        id: 1,
        title: "基礎訓練",
        summary: "小盤面から 5×5 まで段階的に学ぶ章。",
        stages: [stage11, stage12, stage13, stage14, stage15, stage16, stage17, stage18]
    )
        return chapter1
    }
}
