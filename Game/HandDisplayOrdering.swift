import Foundation

/// 手札表示で共有する並び替え判定。
/// - Note: 通常手札と塔インベントリの表示順を同じ規則へそろえる。
enum HandDisplayOrdering {
    private static let playableOrderingIndex: [PlayableCard: Int] = {
        var mapping: [PlayableCard: Int] = [:]
        mapping.reserveCapacity(MoveCard.allCases.count + SupportCard.allCases.count)
        for (index, card) in MoveCard.allCases.enumerated() {
            let playable = PlayableCard.move(card)
            if mapping[playable] == nil {
                mapping[playable] = index
            }
        }
        for (offset, support) in SupportCard.allCases.enumerated() {
            mapping[.support(support)] = MoveCard.allCases.count + offset
        }
        return mapping
    }()

    static func orderedHandStacks(
        _ handStacks: [HandStack],
        strategy: HandOrderingStrategy
    ) -> [HandStack] {
        guard strategy == .directionSorted else { return handStacks }
        return handStacks.sorted { lhs, rhs in
            guard let leftCard = lhs.topCard, let rightCard = rhs.topCard else {
                return lhs.topCard != nil
            }
            return isOrderedBefore(leftCard.playable, rightCard.playable)
        }
    }

    static func orderedDungeonInventoryEntries(
        _ entries: [DungeonInventoryEntry],
        strategy: HandOrderingStrategy
    ) -> [DungeonInventoryEntry] {
        guard strategy == .directionSorted else { return entries }
        return entries.sorted { lhs, rhs in
            isOrderedBefore(lhs.playable, rhs.playable)
        }
    }

    private static func isOrderedBefore(_ lhs: PlayableCard, _ rhs: PlayableCard) -> Bool {
        let leftCategory = orderingCategory(for: lhs)
        let rightCategory = orderingCategory(for: rhs)
        if leftCategory != rightCategory {
            return leftCategory < rightCategory
        }

        if let leftMove = lhs.move, let rightMove = rhs.move {
            let leftVector = orderingVector(for: leftMove)
            let rightVector = orderingVector(for: rightMove)
            if leftVector.dx != rightVector.dx {
                return leftVector.dx < rightVector.dx
            }
            if leftVector.dy != rightVector.dy {
                return leftVector.dy > rightVector.dy
            }
        }

        let leftIndex = playableOrderingIndex[lhs] ?? Int.max
        let rightIndex = playableOrderingIndex[rhs] ?? Int.max
        if leftIndex != rightIndex {
            return leftIndex < rightIndex
        }
        return lhs.identityText < rhs.identityText
    }

    /// 並び替えカテゴリを判定する（0: 通常移動、1: 補助）
    private static func orderingCategory(for card: PlayableCard) -> Int {
        card.move == nil ? 1 : 0
    }

    /// 並び替えに利用する代表ベクトルを取得する（左方向優先で安定ソートを実現）
    private static func orderingVector(for move: MoveCard) -> MoveVector {
        let vectors = move.movementVectors
        let filtered = vectors.filter { $0.dx != 0 || $0.dy != 0 }
        let candidates = filtered.isEmpty ? vectors : filtered
        guard !candidates.isEmpty else {
            return MoveVector(dx: 0, dy: 0)
        }
        let sorted = candidates.sorted { lhs, rhs in
            if lhs.dx != rhs.dx {
                return lhs.dx < rhs.dx
            }
            return lhs.dy > rhs.dy
        }
        return sorted.first ?? MoveVector(dx: 0, dy: 0)
    }
}
