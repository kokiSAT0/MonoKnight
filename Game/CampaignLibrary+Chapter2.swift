import Foundation

extension CampaignLibrary {
    static func buildChapter2() -> CampaignChapter {
        let stage21 = targetStage(
            chapter: 2,
            index: 1,
            title: "縦横選択の一歩",
            summary: "上下左右の選択カードで、目的地へ寄せる軸を自分で選びます。",
            goalCount: 6,
            deckPreset: .standardWithOrthogonalChoices,
            secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 3),
            scoreTarget: 215,
            unlockRequirement: .stageClear(CampaignStageID(chapter: 1, index: 8))
        )
        let stage22 = targetStage(
            chapter: 2,
            index: 2,
            title: "無料フォーカス",
            summary: "無料フォーカスマスで手札を整え、目的地の流れをつなげます。",
            goalCount: 6,
            deckPreset: .standardWithOrthogonalChoices,
            spawnRule: .chooseAnyAfterPreview,
            secondaryObjective: .finishWithinMoves(maxMoves: 17),
            scoreTarget: 210,
            unlockRequirement: .stageClear(stage21.id),
            tileEffectOverrides: [GridPoint(x: 3, y: 1): .freeFocus]
        )
        let stage23 = targetStage(
            chapter: 2,
            index: 3,
            title: "斜め選択",
            summary: "斜め選択カードで、角度を変えて取りやすい目的地へ寄せます。",
            goalCount: 7,
            deckPreset: .standardWithDiagonalChoices,
            secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 3),
            scoreTarget: 240,
            unlockRequirement: .stageClear(stage22.id)
        )
        let stage24 = targetStage(
            chapter: 2,
            index: 4,
            title: "桂馬選択",
            summary: "桂馬の選択カードで、大きく位置を変える入口を覚えます。",
            goalCount: 7,
            deckPreset: .standardWithKnightChoices,
            spawnRule: .chooseAnyAfterPreview,
            secondaryObjective: .finishWithinMoves(maxMoves: 19),
            scoreTarget: 240,
            unlockRequirement: .stageClear(stage23.id)
        )
        let stage25 = targetStage(
            chapter: 2,
            index: 5,
            title: "全選択カード",
            summary: "縦横、斜め、桂馬を混ぜ、手札から取りやすい目的地を選びます。",
            goalCount: 8,
            deckPreset: .standardWithAllChoices,
            secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 3),
            scoreTarget: 270,
            unlockRequirement: .stageClear(stage24.id)
        )
        let stage26 = targetStage(
            chapter: 2,
            index: 6,
            title: "端から端へ",
            summary: "選択カードで端の目的地へ寄せた後、次の目的地へ戻ります。",
            goalCount: 8,
            deckPreset: .standardWithAllChoices,
            spawnRule: .chooseAnyAfterPreview,
            secondaryObjective: .finishWithinMoves(maxMoves: 21),
            scoreTarget: 270,
            unlockRequirement: .stageClear(stage25.id)
        )
        let stage27 = targetStage(
            chapter: 2,
            index: 7,
            title: "寄せの選択",
            summary: "複数の候補カードから、次の目的地にも残る位置を選びます。",
            goalCount: 8,
            deckPreset: .standardWithAllChoices,
            secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 2),
            scoreTarget: 265,
            unlockRequirement: .stageClear(stage26.id)
        )
        let stage28 = targetStage(
            chapter: 2,
            index: 8,
            title: "往復総合",
            summary: "目的地の連なりを見て、戻りと寄せをバランス良く扱います。",
            goalCount: 9,
            deckPreset: .standardWithAllChoices,
            spawnRule: .chooseAnyAfterPreview,
            secondaryObjective: .finishWithFocusAtMostAndWithinMoves(maxFocusCount: 3, maxMoves: 22),
            scoreTarget: 300,
            unlockRequirement: .stageClear(stage27.id)
        )

        return CampaignChapter(
            id: 2,
            title: "近距離と戻り",
            summary: "同じ周辺へ戻る判断と、短い寄せを鍛える章。",
            stages: [stage21, stage22, stage23, stage24, stage25, stage26, stage27, stage28]
        )
    }
}
