import Foundation
#if canImport(Combine)
import Combine
#endif
import SharedSupport // ログユーティリティを利用するため追加

/// 手札スロットと先読みカードの管理を担当するクラス
/// - Note: GameCore から委譲される形でカード補充や並び替えを一元的に扱う
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
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

    /// 移動パターン ID ごとのデフォルト順序をキャッシュし、安定ソートに利用する
    private static let movePatternOrderingIndex: [MoveCard.MovePattern.Identity: Int] = {
        var mapping: [MoveCard.MovePattern.Identity: Int] = [:]
        mapping.reserveCapacity(MoveCard.allCases.count)
        for (index, card) in MoveCard.allCases.enumerated() {
            let identity = card.movePattern.identity
            if mapping[identity] == nil {
                mapping[identity] = index
            }
        }
        return mapping
    }()

    /// 初期化
    /// - Parameters:
    ///   - handSize: 手札スロット数
    ///   - nextPreviewCount: NEXT 表示の枚数
    ///   - allowsCardStacking: 同種カードのスタックを許可するかどうか
    ///   - initialOrderingStrategy: 並び替え設定の初期値
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
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
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    public func updateHandOrderingStrategy(_ newStrategy: HandOrderingStrategy) {
        guard handOrderingStrategy != newStrategy else { return }
        handOrderingStrategy = newStrategy
        reorderHandIfNeeded()
    }

    /// スタック上の先頭カードを消費し、空になった場合はスロットごと取り除く
    /// - Parameter index: 消費したいスタック位置
    /// - Returns: 空スロットが発生した場合はそのインデックスを返す
    @discardableResult
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
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
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
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
        // 山札設定から取得できるユニークな移動パターン数を把握し、過剰なスロット作成を防ぐ
        let uniqueIdentityCount = deck.uniqueMoveIdentityCount()
        let maxStackCount = max(0, min(handSize, uniqueIdentityCount))
        guard handStacks.count < maxStackCount || !preferredInsertionIndices.isEmpty else { return }

        var pendingInsertionIndices = preferredInsertionIndices.sorted()
        var drawAttempts = 0

        while handStacks.count < maxStackCount || !pendingInsertionIndices.isEmpty {
            // すでにユニーク上限へ到達しており、これ以上スロットを増やせない場合は早期に抜ける
            if handStacks.count >= maxStackCount {
                pendingInsertionIndices.removeAll()
                break
            }

            drawAttempts += 1
            if drawAttempts > 512 {
                debugLog("HandManager.refillHandStacks が安全カウンタに到達: handStacks=\(handStacks.count), next残=\(nextCards.count)")
                break
            }

            let nextCard: DealtCard?
            if !nextCards.isEmpty {
                nextCard = nextCards.removeFirst()
            } else {
                nextCard = deck.draw()
            }
            guard let card = nextCard else { break }

            if allowsCardStacking {
                let identity = card.move.movePattern.identity
                if let index = handStacks.firstIndex(where: { stack in
                    guard let stackIdentity = stack.representativePatternIdentity else { return false }
                    return stackIdentity == identity
                }) {
                    var existing = handStacks[index]
                    existing.append(card)
                    handStacks[index] = existing
                    continue
                }
            }

            guard handStacks.count < maxStackCount else {
                pendingInsertionIndices.removeAll()
                break
            }

            let newStack = HandStack(cards: [card])
            if let preferredIndex = pendingInsertionIndices.first {
                let insertionIndex = min(preferredIndex, handStacks.count)
                handStacks.insert(newStack, at: insertionIndex)
                pendingInsertionIndices.removeFirst()
                for candidate in 0..<pendingInsertionIndices.count {
                    if pendingInsertionIndices[candidate] >= insertionIndex {
                        pendingInsertionIndices[candidate] += 1
                    }
                }
            } else {
                handStacks.append(newStack)
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
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    public func reorderHandIfNeeded() {
        guard handOrderingStrategy == .directionSorted else { return }
        handStacks.sort { lhs, rhs in
            guard let leftCard = lhs.topCard, let rightCard = rhs.topCard else {
                return lhs.topCard != nil
            }
            // 代表ベクトルを経由することで、将来的に複数候補を持つカードでも共通ロジックを流用できる
            let leftVector = leftCard.move.primaryVector
            let rightVector = rightCard.move.primaryVector
            let leftDX = leftVector.dx
            let rightDX = rightVector.dx
            if leftDX != rightDX {
                return leftDX < rightDX
            }
            let leftDY = leftVector.dy
            let rightDY = rightVector.dy
            if leftDY != rightDY {
                return leftDY > rightDY
            }
            let leftIdentity = leftCard.move.movePattern.identity
            let rightIdentity = rightCard.move.movePattern.identity
            let leftIndex = HandManager.movePatternOrderingIndex[leftIdentity] ?? 0
            let rightIndex = HandManager.movePatternOrderingIndex[rightIdentity] ?? 0
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
