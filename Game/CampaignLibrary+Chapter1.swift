import Foundation

extension CampaignLibrary {
    static func buildChapter1() -> CampaignChapter {
        let stage11 = targetStage(
            chapter: 1,
            index: 1,
            title: "目的地の一歩",
            summary: "広い盤面で王将カードだけを使い、目的地を順番に取る基本を学びます。",
            goalCount: 3,
            deckPreset: .kingOnly,
            secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 2),
            scoreTarget: 120,
            unlockRequirement: .always
        )
        let stage12 = targetStage(
            chapter: 1,
            index: 2,
            title: "ナイト接近",
            summary: "キングと桂馬で、遠い目的地へ近づく感覚を掴みます。",
            goalCount: 4,
            deckPreset: .kingPlusKnightOnly,
            secondaryObjective: .finishWithinMoves(maxMoves: 10),
            scoreTarget: 140,
            unlockRequirement: .stageClear(stage11.id)
        )
        let stage13 = targetStage(
            chapter: 1,
            index: 3,
            title: "NEXT確認",
            summary: "先読みを見ながら、次の目的地までの道筋を作ります。",
            goalCount: 4,
            deckPreset: .kingAndKnightBasic,
            secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 2),
            scoreTarget: 145,
            unlockRequirement: .stageClear(stage12.id)
        )
        let stage14 = targetStage(
            chapter: 1,
            index: 4,
            title: "フォーカス練習",
            summary: "必要な時だけフォーカスを使い、手札を目的地へ寄せる練習です。",
            goalCount: 5,
            deckPreset: .kingAndKnightBasic,
            spawnRule: .chooseAnyAfterPreview,
            secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 1),
            scoreTarget: 165,
            unlockRequirement: .stageClear(stage13.id)
        )
        let stage15 = targetStage(
            chapter: 1,
            index: 5,
            title: "標準盤入門",
            summary: "5×5 盤で標準的な距離感を覚え、目的地をテンポ良く集めます。",
            goalCount: 5,
            deckPreset: .standardLight,
            secondaryObjective: .finishWithinMoves(maxMoves: 12),
            scoreTarget: 170,
            unlockRequirement: .stageClear(stage14.id)
        )
        let stage16 = targetStage(
            chapter: 1,
            index: 6,
            title: "開始位置選び",
            summary: "最初の手札と目的地を見て、始める位置を決める演習です。",
            goalCount: 5,
            deckPreset: .standardLight,
            spawnRule: .chooseAnyAfterPreview,
            secondaryObjective: .finishWithFocusAtMost(maxFocusCount: 2),
            scoreTarget: 170,
            unlockRequirement: .stageClear(stage15.id)
        )
        let stage17 = targetStage(
            chapter: 1,
            index: 7,
            title: "連続目的地",
            summary: "目的地獲得後の次の一手を意識し、ルートをつなげます。",
            goalCount: 6,
            deckPreset: .standardLight,
            secondaryObjective: .finishWithinMoves(maxMoves: 15),
            scoreTarget: 200,
            unlockRequirement: .stageClear(stage16.id)
        )
        let stage18 = targetStage(
            chapter: 1,
            index: 8,
            title: "基礎総合",
            summary: "目的地、NEXT、フォーカスをまとめて使う最初の総合演習です。",
            goalCount: 6,
            deckPreset: .standard,
            spawnRule: .chooseAnyAfterPreview,
            secondaryObjective: .finishWithFocusAtMostAndWithinMoves(maxFocusCount: 2, maxMoves: 16),
            scoreTarget: 205,
            unlockRequirement: .stageClear(stage17.id)
        )

        return CampaignChapter(
            id: 1,
            title: "目的地基礎",
            summary: "目的地を取り続ける新しい標準ルールに慣れる章。",
            stages: [stage11, stage12, stage13, stage14, stage15, stage16, stage17, stage18]
        )
    }
}
