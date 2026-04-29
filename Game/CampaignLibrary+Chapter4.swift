import Foundation

extension CampaignLibrary {
    static func buildChapter4() -> CampaignChapter {
        let stage41 = targetStage(chapter: 4, index: 1, title: "始点の読み", summary: "最初の目的地と手札を見て、開始位置から有利を作ります。", goalCount: 8, deckPreset: .standardLight, spawnRule: .chooseAnyAfterPreview, secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 3), scoreTarget: 290, unlockRequirement: .chapterTotalStars(chapter: 3, minimum: 12))
        let stage42 = targetStage(chapter: 4, index: 2, title: "固定始点の対応", summary: "中央開始から目的地の並びに合わせて柔軟に寄せます。", goalCount: 9, deckPreset: .standard, secondaryObjective: .finishWithinMoves(maxMoves: 21), scoreTarget: 315, unlockRequirement: .stageClear(stage41.id))
        let stage43 = targetStage(chapter: 4, index: 3, title: "端始点計画", summary: "端に近い開始位置から、盤面中央へ戻る判断を磨きます。", goalCount: 9, deckPreset: .standardWithOrthogonalChoices, spawnRule: .fixed(GridPoint(x: 0, y: 0)), secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 3), scoreTarget: 315, unlockRequirement: .stageClear(stage42.id))
        let stage44 = targetStage(chapter: 4, index: 4, title: "逆端への道", summary: "遠い目的地へ向かう途中で、次の候補も拾いやすい位置を狙います。", goalCount: 10, deckPreset: .standardWithDiagonalChoices, spawnRule: .fixed(GridPoint(x: 4, y: 4)), secondaryObjective: .finishWithinMoves(maxMoves: 23), scoreTarget: 335, unlockRequirement: .stageClear(stage43.id))
        let stage45 = targetStage(chapter: 4, index: 5, title: "選んで始める", summary: "任意スポーンと選択カードを組み合わせ、序盤から目的地へ近づきます。", goalCount: 10, deckPreset: .standardWithAllChoices, spawnRule: .chooseAnyAfterPreview, secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 2), scoreTarget: 330, unlockRequirement: .stageClear(stage44.id))
        let stage46 = targetStage(chapter: 4, index: 6, title: "中盤の立て直し", summary: "遠回りになった時に、フォーカスと選択カードで流れを戻します。", goalCount: 10, deckPreset: .standardWithAllChoices, secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 3), scoreTarget: 330, unlockRequirement: .stageClear(stage45.id))
        let stage47 = targetStage(chapter: 4, index: 7, title: "始点総合", summary: "開始位置と手札の両方から、最初の三つの目的地を組み立てます。", goalCount: 11, deckPreset: .standardWithAllChoices, spawnRule: .chooseAnyAfterPreview, secondaryObjective: .finishWithinMoves(maxMoves: 25), scoreTarget: 355, unlockRequirement: .stageClear(stage46.id))
        let stage48 = targetStage(chapter: 4, index: 8, title: "ルート構築試験", summary: "始点、NEXT、フォーカスを使い、目的地の流れを最後まで保ちます。", goalCount: 11, deckPreset: .standardWithAllChoices, spawnRule: .chooseAnyAfterPreview, secondaryObjective: .finishWithFocusAtMostAndWithinMoves(maxFocusCount: 3, maxMoves: 25), scoreTarget: 350, unlockRequirement: .stageClear(stage47.id))

        return CampaignChapter(id: 4, title: "ルート構築", summary: "開始位置と中盤の立て直しを学ぶ章。", stages: [stage41, stage42, stage43, stage44, stage45, stage46, stage47, stage48])
    }
}
