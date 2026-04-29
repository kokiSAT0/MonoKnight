import Foundation

public extension GameMode {
    /// スタンダードモード（既存仕様）
    static var standard: GameMode {
        GameMode(identifier: .standard5x5, displayName: "スタンダード", regulation: buildStandardRegulation())
    }

    /// クラシカルチャレンジモード
    static var classicalChallenge: GameMode {
        GameMode(identifier: .classicalChallenge, displayName: "クラシカルチャレンジ", regulation: buildClassicalChallengeRegulation())
    }

    /// カード再設計を安全に試すための全部入り実験モード
    static var targetLab: GameMode {
        GameMode(
            identifier: .targetLab,
            displayName: "カード実験場",
            regulation: buildTargetLabRegulation(),
            leaderboardEligible: false
        )
    }

    /// ビルトインで用意しているモードの一覧
    static var builtInModes: [GameMode] { [standard, targetLab, classicalChallenge] }

    /// 識別子から対応するモード定義を取り出すヘルパー
    static func mode(for identifier: Identifier) -> GameMode {
        switch identifier {
        case .standard5x5:
            return standard
        case .classicalChallenge:
            return classicalChallenge
        case .targetLab:
            return targetLab
        case .dailyFixedChallenge, .dailyRandomChallenge, .freeCustom, .campaignStage, .dailyFixed, .dailyRandom:
            return standard
        }
    }
}

private extension GameMode {
    static func buildStandardRegulation() -> Regulation {
        Regulation(
            boardSize: BoardGeometry.standardSize,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standard,
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: BoardGeometry.standardSize)),
            penalties: PenaltySettings(
                deadlockPenaltyCost: 0,
                manualRedrawPenaltyCost: 0,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            ),
            completionRule: .targetCollection(goalCount: 12)
        )
    }

    static func buildClassicalChallengeRegulation() -> Regulation {
        Regulation(
            boardSize: 8,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .classicalChallenge,
            spawnRule: .chooseAnyAfterPreview,
            penalties: PenaltySettings(
                deadlockPenaltyCost: 2,
                manualRedrawPenaltyCost: 2,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 1
            )
        )
    }

    static func buildTargetLabRegulation() -> Regulation {
        let boardSize = BoardGeometry.standardSize
        let fixedWarpTargets = [
            GridPoint(x: 0, y: 0),
            GridPoint(x: 2, y: 0),
            GridPoint(x: 4, y: 0),
            GridPoint(x: 0, y: 2),
            GridPoint(x: 4, y: 2),
            GridPoint(x: 0, y: 4),
            GridPoint(x: 2, y: 4),
            GridPoint(x: 4, y: 4)
        ]
        return Regulation(
            boardSize: boardSize,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .targetLabAllIn,
            spawnRule: .chooseAnyAfterPreview,
            penalties: PenaltySettings(
                deadlockPenaltyCost: 0,
                manualRedrawPenaltyCost: 0,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            ),
            fixedWarpCardTargets: [.fixedWarp: fixedWarpTargets],
            completionRule: .targetCollection(goalCount: 12)
        )
    }
}
