import Foundation

extension CampaignLibrary {
    static func buildChapter7() -> CampaignChapter {
        let crossWarp = ["cross": [GridPoint(x: 0, y: 4), GridPoint(x: 4, y: 0)]]
        let sideWarp = ["side": [GridPoint(x: 0, y: 2), GridPoint(x: 4, y: 2)]]
        let ringWarp = ["ring": [GridPoint(x: 0, y: 0), GridPoint(x: 4, y: 0), GridPoint(x: 4, y: 4), GridPoint(x: 0, y: 4)]]

        let stage71 = targetStage(chapter: 7, index: 1, title: "ワープタイル基礎", summary: "ワープタイルで離れた表示目的地へ近づく基本を学びます。", goalCount: 10, deckPreset: .standard, secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 3), scoreTarget: 350, unlockRequirement: .stageClear(CampaignStageID(chapter: 6, index: 8)), warpTilePairs: crossWarp)
        let stage72 = targetStage(chapter: 7, index: 2, title: "横断ワープ", summary: "横断ワープを使い、端の目的地を素早く回収します。", goalCount: 11, deckPreset: .standardWithOrthogonalChoices, spawnRule: .chooseAnyAfterPreview, secondaryObjective: .finishWithinMoves(maxMoves: 27), scoreTarget: 375, unlockRequirement: .stageClear(stage71.id), warpTilePairs: sideWarp)
        let stage73 = targetStage(chapter: 7, index: 3, title: "角の循環", summary: "角を巡るワープで、遠くの目的地へ向かう選択肢を増やします。", goalCount: 11, deckPreset: .standardWithDiagonalChoices, secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 3), scoreTarget: 370, unlockRequirement: .stageClear(stage72.id), warpTilePairs: ringWarp)
        let stage74 = targetStage(chapter: 7, index: 4, title: "目的地転換", summary: "転換マスで表示中目的地の並びを入れ替え、次に狙う順を整えます。", goalCount: 12, deckPreset: .standardWithAllChoices, spawnRule: .chooseAnyAfterPreview, secondaryObjective: .finishWithinMoves(maxMoves: 30), scoreTarget: 405, unlockRequirement: .stageClear(stage73.id), tileEffectOverrides: [GridPoint(x: 2, y: 2): .targetSwap], warpTilePairs: crossWarp)
        let stage75 = targetStage(chapter: 7, index: 5, title: "入口を選ぶ", summary: "どのワープ入口へ向かうかを、表示中の目的地から判断します。", goalCount: 12, deckPreset: .standardWithAllChoices, secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 2), scoreTarget: 400, unlockRequirement: .stageClear(stage74.id), impassableTilePoints: [GridPoint(x: 1, y: 2), GridPoint(x: 3, y: 2)], warpTilePairs: sideWarp)
        let stage76 = targetStage(chapter: 7, index: 6, title: "循環制御", summary: "ワープで行きすぎた時も、フォーカスや転換で狙い先を整えます。", goalCount: 13, deckPreset: .targetLabAllIn, spawnRule: .chooseAnyAfterPreview, secondaryObjective: .finishWithinMoves(maxMoves: 32), scoreTarget: 430, unlockRequirement: .stageClear(stage75.id), tileEffectOverrides: [GridPoint(x: 2, y: 2): .targetSwap], warpTilePairs: ringWarp)
        let stage77 = targetStage(chapter: 7, index: 7, title: "ワープカード入門", summary: "ワープカードとワープタイルを見比べ、目的地までの手数を縮めます。", goalCount: 13, deckPreset: .standardWithWarpCards, secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 3), scoreTarget: 425, unlockRequirement: .stageClear(stage76.id), impassableTilePoints: [GridPoint(x: 2, y: 1), GridPoint(x: 2, y: 3)], warpTilePairs: crossWarp)
        let stage78 = targetStage(chapter: 7, index: 8, title: "ワープタイル試験", summary: "ワープタイル、転換、通常移動を切り替え、目的地を最後まで取り切ります。", goalCount: 14, deckPreset: .standardWithWarpCards, spawnRule: .chooseAnyAfterPreview, secondaryObjective: .finishWithFocusAtMostAndWithinMoves(maxFocusCount: 3, maxMoves: 34), scoreTarget: 455, unlockRequirement: .stageClear(stage77.id), impassableTilePoints: [GridPoint(x: 1, y: 1), GridPoint(x: 3, y: 3)], tileEffectOverrides: [GridPoint(x: 2, y: 2): .targetSwap], warpTilePairs: ringWarp)

        return CampaignChapter(id: 7, title: "ワープと目的地転換", summary: "ワープタイルと転換マスで、遠い目的地への順番を組み替える章。", stages: [stage71, stage72, stage73, stage74, stage75, stage76, stage77, stage78])
    }
}
