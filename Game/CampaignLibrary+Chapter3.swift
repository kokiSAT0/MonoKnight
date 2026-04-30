import Foundation

extension CampaignLibrary {
    static func buildChapter3() -> CampaignChapter {
        let stage31 = targetStage(chapter: 3, index: 1, title: "縦横選択", summary: "縦横選択カードで、表示中の目的地へ近づく軸を選びます。", goalCount: 8, deckPreset: .standardWithOrthogonalChoices, secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 3), scoreTarget: 290, unlockRequirement: .stageClear(CampaignStageID(chapter: 2, index: 8)))
        let stage32 = targetStage(chapter: 3, index: 2, title: "斜め選択", summary: "斜め選択カードを使い、角度を変えて目的地へ寄せます。", goalCount: 8, deckPreset: .standardWithDiagonalChoices, spawnRule: .chooseAnyAfterPreview, secondaryObjective: .finishWithinMoves(maxMoves: 19), scoreTarget: 285, unlockRequirement: .stageClear(stage31.id))
        let stage33 = targetStage(chapter: 3, index: 3, title: "桂馬選択", summary: "桂馬の選択カードで大きく位置を変え、別の表示目的地へ切り替えます。", goalCount: 9, deckPreset: .standardWithKnightChoices, secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 3), scoreTarget: 310, unlockRequirement: .stageClear(stage32.id))
        let stage34 = targetStage(chapter: 3, index: 4, title: "選択の温存", summary: "便利な選択カードをどこで使うかを考える演習です。", goalCount: 9, deckPreset: .kingAndKnightWithOrthogonalChoices, spawnRule: .chooseAnyAfterPreview, secondaryObjective: .finishWithinMoves(maxMoves: 21), scoreTarget: 310, unlockRequirement: .stageClear(stage33.id))
        let stage35 = targetStage(chapter: 3, index: 5, title: "斜めの迂回", summary: "斜め選択を使い、目的地へ直行できない局面を崩します。", goalCount: 10, deckPreset: .kingAndKnightWithDiagonalChoices, secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 3), scoreTarget: 330, unlockRequirement: .stageClear(stage34.id))
        let stage36 = targetStage(chapter: 3, index: 6, title: "跳躍選択", summary: "桂馬選択を使って距離を一気に変え、フォーカスに頼りすぎず進めます。", goalCount: 10, deckPreset: .kingAndKnightWithKnightChoices, spawnRule: .chooseAnyAfterPreview, secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 2), scoreTarget: 325, unlockRequirement: .stageClear(stage35.id))
        let stage37 = targetStage(chapter: 3, index: 7, title: "全選択カード", summary: "選択カードを幅広く使い、表示中の目的地まで含めて位置を決めます。", goalCount: 11, deckPreset: .standardWithAllChoices, secondaryObjective: .finishWithinMoves(maxMoves: 24), scoreTarget: 350, unlockRequirement: .stageClear(stage36.id))
        let stage38 = targetStage(chapter: 3, index: 8, title: "カード判断総合", summary: "カードごとの得意な距離を見極める総合ステージです。", goalCount: 11, deckPreset: .standardWithAllChoices, spawnRule: .chooseAnyAfterPreview, secondaryObjective: .finishWithFocusAtMostAndWithinMoves(maxFocusCount: 3, maxMoves: 24), scoreTarget: 345, unlockRequirement: .stageClear(stage37.id))

        return CampaignChapter(id: 3, title: "カード選択", summary: "選択カードで目的地への近づき方を広げる章。", stages: [stage31, stage32, stage33, stage34, stage35, stage36, stage37, stage38])
    }
}
