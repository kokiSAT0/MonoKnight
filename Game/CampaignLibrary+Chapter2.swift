import Foundation

extension CampaignLibrary {
    static func buildChapter2() -> CampaignChapter {
        let stage21 = targetStage(
            chapter: 2,
            index: 1,
            title: "戻り道の判断",
            summary: "近い目的地と戻る目的地を見比べ、短い手順で取り切ります。",
            goalCount: 6,
            deckPreset: .kingAndKnightBasic,
            secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 3),
            scoreTarget: 215,
            unlockRequirement: .stageClear(CampaignStageID(chapter: 1, index: 8))
        )
        let stage22 = targetStage(
            chapter: 2,
            index: 2,
            title: "近距離連鎖",
            summary: "小さく寄せるカードを活かし、目的地を途切れず回収します。",
            goalCount: 6,
            deckPreset: .kingAndKnightBasic,
            spawnRule: .chooseAnyAfterPreview,
            secondaryObjective: .finishWithinMoves(maxMoves: 17),
            scoreTarget: 210,
            unlockRequirement: .stageClear(stage21.id)
        )
        let stage23 = targetStage(
            chapter: 2,
            index: 3,
            title: "中央経由",
            summary: "中央付近を経由し、次の目的地へ行きやすい位置を保ちます。",
            goalCount: 7,
            deckPreset: .standardLight,
            secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 3),
            scoreTarget: 240,
            unlockRequirement: .stageClear(stage22.id)
        )
        let stage24 = targetStage(
            chapter: 2,
            index: 4,
            title: "端から端へ",
            summary: "端の目的地に寄せた後、次の目的地へ戻る判断を練習します。",
            goalCount: 7,
            deckPreset: .standardLight,
            spawnRule: .chooseAnyAfterPreview,
            secondaryObjective: .finishWithinMoves(maxMoves: 19),
            scoreTarget: 240,
            unlockRequirement: .stageClear(stage23.id)
        )
        let stage25 = targetStage(
            chapter: 2,
            index: 5,
            title: "縦横の切り返し",
            summary: "上下左右の選択カードで、近い目的地へ寄せる軸を選びます。",
            goalCount: 8,
            deckPreset: .standardWithOrthogonalChoices,
            secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 3),
            scoreTarget: 270,
            unlockRequirement: .stageClear(stage24.id)
        )
        let stage26 = targetStage(
            chapter: 2,
            index: 6,
            title: "斜めの戻り",
            summary: "斜め選択を混ぜ、回り道に見える近道を探します。",
            goalCount: 8,
            deckPreset: .standardWithDiagonalChoices,
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
