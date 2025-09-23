import Foundation

/// 同一種類の移動カードを束ね、手札スロット単位で管理するための構造体
/// - Note: 1 つのスタックには必ず 1 種類のカードだけが含まれ、トップカードの差し替え時には新しい `DealtCard` を採番して UI のアニメーション整合性を保つ。
public struct HandStack: Identifiable, Equatable {
    /// スタック自体を識別するための UUID。スロット位置が入れ替わっても安定してトラッキングできるようにする。
    public let id: UUID
    /// スタックに含まれるカード一覧。常に同じ種類の `MoveCard` だけが格納される。
    public private(set) var cards: [DealtCard]
    /// スタック内で代表となる移動カード。`cards` 配列が空にならない限り常に同一の値が維持される。
    private let representativeMove: MoveCard

    /// スタックの先頭（= UI に表示される）カード。常に `cards` の末尾要素を参照する。
    public var topCard: DealtCard {
        guard let last = cards.last else {
            // スタックが空になる状況は GameCore 側でスタック自体を除去するため想定外。早期に気付けるよう致命的エラーにする。
            fatalError("HandStack.topCard が空スタックで参照されました")
        }
        return last
    }

    /// スタックに含まれるカード枚数。UI のバッジ表示やテスト検証で利用する。
    public var count: Int { cards.count }

    /// スタックが保持する移動カードの種類。`topCard.move` と常に一致する。
    public var move: MoveCard { representativeMove }

    /// 内部的にスタックが空かどうかを判定するヘルパー。GameCore 側の安全確認に利用する。
    public var isEmpty: Bool { cards.isEmpty }

    /// 初期化時にカード配列を受け取り、同一種類のみで構成されているか検証する。
    /// - Parameter cards: スタックへ格納したい `DealtCard` 配列（少なくとも 1 枚必要）
    public init(cards: [DealtCard]) {
        precondition(!cards.isEmpty, "HandStack には最低 1 枚のカードが必要です")
        guard let firstMove = cards.first?.move else {
            fatalError("HandStack 初期化時にカード種別を取得できませんでした")
        }
        precondition(cards.allSatisfy { $0.move == firstMove }, "HandStack には同一種類のカードのみ格納できます")
        self.id = UUID()
        self.cards = cards
        self.representativeMove = firstMove
    }

    /// 既存スタックへ同種類のカードを追加する。
    /// - Parameter card: 追加したい `DealtCard`。`representativeMove` と一致している必要がある。
    public mutating func append(_ card: DealtCard) {
        precondition(card.move == representativeMove, "HandStack へ異なる種類のカードは追加できません")
        cards.append(card)
    }

    /// スタック先頭のカードを 1 枚取り除き、残りがある場合はトップ用に新しい `DealtCard` を採番する。
    /// - Returns: 取り除いた `DealtCard`
    @discardableResult
    public mutating func removeTopCard() -> DealtCard {
        let removed = cards.removeLast()
        regenerateTopCardIdentityIfNeeded()
        return removed
    }

    /// トップカードを新しい ID で再生成し、SwiftUI のアニメーション整合性を確保する。
    private mutating func regenerateTopCardIdentityIfNeeded() {
        guard !cards.isEmpty else { return }
        cards[cards.count - 1] = DealtCard(move: representativeMove)
    }
}
