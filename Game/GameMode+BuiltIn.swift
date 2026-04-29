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
        targetLab(settings: .default)
    }

    /// カード・特殊マス実験場を指定設定で生成する
    static func targetLab(settings: TargetLabExperimentSettings) -> GameMode {
        GameMode(
            identifier: .targetLab,
            displayName: "カード・特殊マス実験場",
            regulation: buildTargetLabRegulation(settings: settings),
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

    static func buildTargetLabRegulation(settings: TargetLabExperimentSettings) -> Regulation {
        let boardSize = 8
        let warpA = GridPoint(x: 0, y: 0)
        let warpB = GridPoint(x: 7, y: 7)
        let fixedWarpTargets = [
            warpA,
            GridPoint(x: 3, y: 0),
            GridPoint(x: 7, y: 0),
            GridPoint(x: 0, y: 3),
            GridPoint(x: 7, y: 3),
            GridPoint(x: 0, y: 7),
            GridPoint(x: 3, y: 7),
            warpB
        ]
        let allTileEffects: [(TargetLabTileKind, GridPoint, TileEffect)] = [
            (.shuffleHand, GridPoint(x: 2, y: 5), .shuffleHand),
            (.boost, GridPoint(x: 5, y: 2), .boost),
            (.slow, GridPoint(x: 2, y: 2), .slow),
            (.nextRefresh, GridPoint(x: 0, y: 7), .nextRefresh),
            (.freeFocus, GridPoint(x: 7, y: 0), .freeFocus),
            (.preserveCard, GridPoint(x: 3, y: 0), .preserveCard)
        ]
        let tileEffects = Dictionary(
            uniqueKeysWithValues: allTileEffects.compactMap { kind, point, effect in
                settings.enabledTileKinds.contains(kind) ? (point, effect) : nil
            }
        )
        let warpTilePairs = settings.enabledTileKinds.contains(.warp) ? ["lab_warp": [warpA, warpB]] : [:]
        let fixedWarpCardTargets: [MoveCard: [GridPoint]] = settings.enabledCardGroups.contains(.warp) ? [.fixedWarp: fixedWarpTargets] : [:]
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
            tileEffectOverrides: tileEffects,
            warpTilePairs: warpTilePairs,
            fixedWarpCardTargets: fixedWarpCardTargets,
            completionRule: .targetCollection(goalCount: 20),
            targetLabExperimentSettings: settings
        )
    }
}
