import Foundation

public extension MoveCard {
    /// カードが持つ移動パターン
    var movePattern: MovePattern {
        guard let pattern = MoveCard.patternRegistry[self] else {
            assertionFailure("MoveCard に対する MovePattern が登録されていません: \(self)")
            return MoveCard.emptyPattern
        }
        return pattern
    }

    /// カードが持つ移動候補一覧を返す
    /// - Important: 現行カードは 1 要素のみだが、今後複数候補を持つカード追加時に拡張しやすいよう配列で保持する
    var movementVectors: [MoveVector] {
        if let override = MoveCard.testMovementVectorOverrides[self] {
            return override
        }
        return movePattern.fallbackVectors()
    }

    /// 盤面状況を考慮した移動経路を解決する
    func resolvePaths(from origin: GridPoint, context: MovePattern.ResolutionContext) -> [MovePattern.Path] {
        if let override = MoveCard.testMovementVectorOverrides[self] {
            return override.compactMap { vector in
                let destination = origin.offset(dx: vector.dx, dy: vector.dy)
                guard context.contains(destination), context.isTraversable(destination) else { return nil }
                return MovePattern.Path(vector: vector, destination: destination, traversedPoints: [destination])
            }
        }
        return movePattern.resolvePaths(from: origin, context: context)
    }

    /// 既存コードとの互換性を維持するための代表ベクトル
    var primaryVector: MoveVector {
        guard let vector = movementVectors.first else {
            assertionFailure("MoveCard.movementVectors は最低 1 要素を想定している")
            return MoveVector(dx: 0, dy: 0)
        }
        return vector
    }

    /// 指定した座標からこのカードが使用可能か判定する
    func canUse(from: GridPoint, boardSize: Int) -> Bool {
        let context = MovePattern.ResolutionContext(
            boardSize: boardSize,
            contains: { point in point.isInside(boardSize: boardSize) },
            isTraversable: { point in point.isInside(boardSize: boardSize) }
        )
        return !resolvePaths(from: from, context: context).isEmpty
    }

    /// movementVectors を一時的に差し替えるヘルパー
    static func setTestMovementVectors(_ vectors: [MoveVector]?, for card: MoveCard) {
        if let vectors {
            testMovementVectorOverrides[card] = vectors
        } else {
            testMovementVectorOverrides.removeValue(forKey: card)
        }
    }
}

private extension MoveCard {
    /// 既定のパターン集合
    static let patternRegistry: [MoveCard: MovePattern] = {
        var mapping: [MoveCard: MovePattern] = [:]

        mapping[.kingUp] = .relativeSteps([MoveVector(dx: 0, dy: 1)])
        mapping[.kingUpRight] = .relativeSteps([MoveVector(dx: 1, dy: 1)])
        mapping[.kingRight] = .relativeSteps([MoveVector(dx: 1, dy: 0)])
        mapping[.kingDownRight] = .relativeSteps([MoveVector(dx: 1, dy: -1)])
        mapping[.kingDown] = .relativeSteps([MoveVector(dx: 0, dy: -1)])
        mapping[.kingDownLeft] = .relativeSteps([MoveVector(dx: -1, dy: -1)])
        mapping[.kingLeft] = .relativeSteps([MoveVector(dx: -1, dy: 0)])
        mapping[.kingUpLeft] = .relativeSteps([MoveVector(dx: -1, dy: 1)])
        mapping[.kingUpOrDown] = .relativeSteps([
            MoveVector(dx: 0, dy: 1),
            MoveVector(dx: 0, dy: -1)
        ])
        mapping[.kingLeftOrRight] = .relativeSteps([
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0)
        ])
        mapping[.kingUpwardDiagonalChoice] = .relativeSteps([
            MoveVector(dx: 1, dy: 1),
            MoveVector(dx: -1, dy: 1)
        ])
        mapping[.kingRightDiagonalChoice] = .relativeSteps([
            MoveVector(dx: 1, dy: 1),
            MoveVector(dx: 1, dy: -1)
        ])
        mapping[.kingDownwardDiagonalChoice] = .relativeSteps([
            MoveVector(dx: 1, dy: -1),
            MoveVector(dx: -1, dy: -1)
        ])
        mapping[.kingLeftDiagonalChoice] = .relativeSteps([
            MoveVector(dx: -1, dy: 1),
            MoveVector(dx: -1, dy: -1)
        ])

        mapping[.knightUp2Right1] = .relativeSteps([MoveVector(dx: 1, dy: 2)])
        mapping[.knightUp2Left1] = .relativeSteps([MoveVector(dx: -1, dy: 2)])
        mapping[.knightUp1Right2] = .relativeSteps([MoveVector(dx: 2, dy: 1)])
        mapping[.knightUp1Left2] = .relativeSteps([MoveVector(dx: -2, dy: 1)])
        mapping[.knightDown2Right1] = .relativeSteps([MoveVector(dx: 1, dy: -2)])
        mapping[.knightDown2Left1] = .relativeSteps([MoveVector(dx: -1, dy: -2)])
        mapping[.knightDown1Right2] = .relativeSteps([MoveVector(dx: 2, dy: -1)])
        mapping[.knightDown1Left2] = .relativeSteps([MoveVector(dx: -2, dy: -1)])
        mapping[.knightUpwardChoice] = .relativeSteps([
            MoveVector(dx: 1, dy: 2),
            MoveVector(dx: -1, dy: 2)
        ])
        mapping[.knightRightwardChoice] = .relativeSteps([
            MoveVector(dx: 2, dy: 1),
            MoveVector(dx: 2, dy: -1)
        ])
        mapping[.knightDownwardChoice] = .relativeSteps([
            MoveVector(dx: 1, dy: -2),
            MoveVector(dx: -1, dy: -2)
        ])
        mapping[.knightLeftwardChoice] = .relativeSteps([
            MoveVector(dx: -2, dy: 1),
            MoveVector(dx: -2, dy: -1)
        ])

        mapping[.straightUp2] = .relativeSteps([MoveVector(dx: 0, dy: 2)])
        mapping[.straightDown2] = .relativeSteps([MoveVector(dx: 0, dy: -2)])
        mapping[.straightRight2] = .relativeSteps([MoveVector(dx: 2, dy: 0)])
        mapping[.straightLeft2] = .relativeSteps([MoveVector(dx: -2, dy: 0)])
        mapping[.diagonalUpRight2] = .relativeSteps([MoveVector(dx: 2, dy: 2)])
        mapping[.diagonalDownRight2] = .relativeSteps([MoveVector(dx: 2, dy: -2)])
        mapping[.diagonalDownLeft2] = .relativeSteps([MoveVector(dx: -2, dy: -2)])
        mapping[.diagonalUpLeft2] = .relativeSteps([MoveVector(dx: -2, dy: 2)])

        let directionalRayDefinitions: [(MoveCard, MoveVector)] = [
            (.rayUp, MoveVector(dx: 0, dy: 1)),
            (.rayUpRight, MoveVector(dx: 1, dy: 1)),
            (.rayRight, MoveVector(dx: 1, dy: 0)),
            (.rayDownRight, MoveVector(dx: 1, dy: -1)),
            (.rayDown, MoveVector(dx: 0, dy: -1)),
            (.rayDownLeft, MoveVector(dx: -1, dy: -1)),
            (.rayLeft, MoveVector(dx: -1, dy: 0)),
            (.rayUpLeft, MoveVector(dx: -1, dy: 1))
        ]
        directionalRayDefinitions.forEach { card, vector in
            mapping[card] = .directionalRayFinalStep(direction: vector, limit: nil)
        }

        return mapping
    }()

    /// MovePattern が存在しない場合のフォールバック
    static let emptyPattern = MovePattern.relativeSteps([])

    /// テスト向けに movementVectors を差し替えるためのオーバーライド辞書
    static var testMovementVectorOverrides: [MoveCard: [MoveVector]] = [:]
}
