import Foundation
#if canImport(Combine)
import Combine
#endif

/// 手札スロットと先読みカードの管理を担当するクラス
/// - Note: GameCore から委譲される形でカード補充や並び替えを一元的に扱う
public final class HandManager: ObservableObject {
    /// 手札スロットの配列（最大 handSize 種類まで保持）
    @Published public private(set) var handStacks: [HandStack]
    /// 先読み表示に利用するカード配列（NEXT 表示 3 枚など）
    @Published public private(set) var nextCards: [DealtCard]

    /// 手札スロット上限
    private let handSize: Int
    /// NEXT 表示の枚数
    private let nextPreviewCount: Int
    /// 同種カードをまとめて保持できるかどうか
    private let allowsCardStacking: Bool
    /// 並び替え設定
    private var handOrderingStrategy: HandOrderingStrategy

    /// MoveCard ごとのデフォルト順序をキャッシュし、安定ソートに利用する
    private static let moveCardOrderingIndex: [MoveCard: Int] = {
        var mapping: [MoveCard: Int] = [:]
        mapping.reserveCapacity(MoveCard.allCases.count)
        for (index, card) in MoveCard.allCases.enumerated() {
            mapping[card] = index
        }
        return mapping
    }()

    /// 初期化
    /// - Parameters:
    ///   - handSize: 手札スロット数
    ///   - nextPreviewCount: NEXT 表示の枚数
    ///   - allowsCardStacking: 同種カードのスタックを許可するかどうか
    ///   - initialOrderingStrategy: 並び替え設定の初期値
    public init(
        handSize: Int,
        nextPreviewCount: Int,
        allowsCardStacking: Bool,
        initialOrderingStrategy: HandOrderingStrategy = .insertionOrder
    ) {
        self.handSize = handSize
        self.nextPreviewCount = nextPreviewCount
        self.allowsCardStacking = allowsCardStacking
        handStacks = []
        nextCards = []
        handOrderingStrategy = initialOrderingStrategy
    }

    /// 並び替え設定を更新する
    /// - Parameter newStrategy: ユーザーが選択した並び順
    public func updateHandOrderingStrategy(_ newStrategy: HandOrderingStrategy) {
        guard handOrderingStrategy != newStrategy else { return }
        handOrderingStrategy = newStrategy
        reorderHandIfNeeded()
    }

    /// スタック上の先頭カードを消費し、空になった場合はスロットごと取り除く
    /// - Parameter index: 消費したいスタック位置
    /// - Returns: 空スロットが発生した場合はそのインデックスを返す
    @discardableResult
    public func consumeTopCard(at index: Int) -> Int? {
        guard handStacks.indices.contains(index) else { return nil }
        var stack = handStacks[index]
        guard stack.removeTopCard() != nil else { return nil }
        if stack.isEmpty {
            handStacks.remove(at: index)
            return index
        } else {
            handStacks[index] = stack
            return nil
        }
    }

    /// 指定したスタックを取り除き、その内容を返す
    /// - Parameter index: 削除したいスタックの位置
    /// - Returns: 取り除いた `HandStack`
    @discardableResult
    public func removeStack(at index: Int) -> HandStack {
        handStacks.remove(at: index)
    }

    /// 手札スロットと先読みカードをすべて破棄する
    func clearAll() {
        handStacks.removeAll(keepingCapacity: true)
        nextCards.removeAll(keepingCapacity: true)
    }

    /// 手札と先読みを一括で初期化する
    /// - Parameter deck: ドローに使用する山札
    func resetAll(using deck: inout Deck) {
        clearAll()
        rebuildHandAndPreview(using: &deck)
    }

    /// NEXT キューを優先的に使いながら空きスロットへカードを補充する
    /// - Parameters:
    ///   - deck: ドロー元となる山札
    ///   - preferredInsertionIndices: 補充したいスロット位置（使用後の空きを維持するために指定）
    func refillHandStacks(using deck: inout Deck, preferredInsertionIndices: [Int] = []) {
        guard handStacks.count < handSize || !preferredInsertionIndices.isEmpty else { return }
        var pendingInsertionIndices = preferredInsertionIndices.sorted()
        var drawAttempts = 0
        while handStacks.count < handSize || !pendingInsertionIndices.isEmpty {
            let nextCard: DealtCard?
            if !nextCards.isEmpty {
                nextCard = nextCards.removeFirst()
            } else {
                nextCard = deck.draw()
            }
            guard let card = nextCard else { break }
            if allowsCardStacking,
               let index = handStacks.firstIndex(where: { $0.representativeMove == card.move }) {
                var existing = handStacks[index]
                existing.append(card)
                handStacks[index] = existing
            } else {
                if let preferredIndex = pendingInsertionIndices.first {
                    let insertionIndex = min(preferredIndex, handStacks.count)
                    handStacks.insert(HandStack(cards: [card]), at: insertionIndex)
                    pendingInsertionIndices.removeFirst()
                    for candidate in 0..<pendingInsertionIndices.count {
                        if pendingInsertionIndices[candidate] >= insertionIndex {
                            pendingInsertionIndices[candidate] += 1
                        }
                    }
                } else {
                    handStacks.append(HandStack(cards: [card]))
                }
            }
            drawAttempts += 1
            if drawAttempts > 512 {
                debugLog("HandManager.refillHandStacks が安全カウンタに到達: handStacks=\(handStacks.count), next残=\(nextCards.count)")
                break
            }
        }
    }

    /// NEXT 表示用カードが不足している場合に山札から補充する
    /// - Parameter deck: ドロー元となる山札
    func replenishNextPreview(using deck: inout Deck) {
        while nextCards.count < nextPreviewCount {
            guard let drawn = deck.draw() else { break }
            nextCards.append(drawn)
        }
    }

    /// 並び替え設定に応じて手札全体を再構成する
    public func reorderHandIfNeeded() {
        guard handOrderingStrategy == .directionSorted else { return }
        handStacks.sort { lhs, rhs in
            guard let leftCard = lhs.topCard, let rightCard = rhs.topCard else {
                return lhs.topCard != nil
            }
            let leftDX = leftCard.move.dx
            let rightDX = rightCard.move.dx
            if leftDX != rightDX {
                return leftDX < rightDX
            }
            let leftDY = leftCard.move.dy
            let rightDY = rightCard.move.dy
            if leftDY != rightDY {
                return leftDY > rightDY
            }
            let leftIndex = HandManager.moveCardOrderingIndex[leftCard.move] ?? 0
            let rightIndex = HandManager.moveCardOrderingIndex[rightCard.move] ?? 0
            return leftIndex < rightIndex
        }
    }

    /// 手札補充・並び替え・先読み補充を一括で実施する
    /// - Parameters:
    ///   - deck: ドロー元となる山札
    ///   - preferredInsertionIndices: 使用済みスロットへ戻したい位置
    func rebuildHandAndPreview(using deck: inout Deck, preferredInsertionIndices: [Int] = []) {
        refillHandStacks(using: &deck, preferredInsertionIndices: preferredInsertionIndices)
        reorderHandIfNeeded()
        replenishNextPreview(using: &deck)
    }
}
