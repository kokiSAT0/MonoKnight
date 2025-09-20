import Foundation
#if canImport(GameplayKit)
import GameplayKit
#endif

/// 山札を重み付き乱数で生成するデッキ構造体
/// - Note: 王将型カードは標準カードの 1.5 倍（3:2 の整数比）、斜め 2 マスカードは桂馬カードの半分の重みで抽選する。
struct Deck {
    // MARK: - 重み定義
    /// 標準カードに割り当てる重み（比率の基準）
    private static let standardWeight = 2
    /// 斜め 2 マス（マンハッタン距離 4）カード用の重み（ナイト型の半分）
    private static let diagonalDistanceFourWeight = 1
    /// 王将型カードに割り当てる重み（標準の 1.5 倍 = 3）
    private static let kingWeight = 3
    /// 各カードの基礎重みをまとめた辞書（動的な確率計算の基準）
    private static let baseWeights: [MoveCard: Int] = {
        var weights: [MoveCard: Int] = [:]
        weights.reserveCapacity(MoveCard.allCases.count)
        for card in MoveCard.allCases {
            // 王将型は高頻度、ナイト型と直線型は標準、斜め 2 マスは低頻度に設定
            let weight: Int
            if card.isKingType {
                // キング型は 1.5 倍（移動の基礎となるため）
                weight = kingWeight
            } else if card.isDiagonalDistanceFour {
                // 斜め 2 マスは桂馬カードの半分の確率で排出させる
                weight = diagonalDistanceFourWeight
            } else {
                // ナイト型や直線 2 マスは標準の重み
                weight = standardWeight
            }
            weights[card] = weight
        }
        return weights
    }()
    /// ペナルティが無い場合に掛ける係数（4 倍することで 3/4 調整に整数を利用）
    private static let normalMultiplier = 4
    /// ペナルティ中に掛ける係数（基礎重みの 3/4 を実現）
    private static let reducedMultiplier = 3
    /// 同一カードの排出確率を抑制するターン数（ドロー後 5 ターン）
    private static let reductionDuration = 5

    // MARK: - 乱数管理
    /// 初期シード値。reset() 時に同じ乱数列へ戻すため保持する
    private let initialSeed: UInt64
    #if canImport(GameplayKit)
    /// GameplayKit 利用時の乱数生成器（メルセンヌツイスタ）
    private var random: GKMersenneTwisterRandomSource
    #else
    /// GameplayKit が利用できない環境向けの簡易乱数生成器
    private var random: SeededGenerator
    #endif

    /// 直近に排出されたカードの抑制残りターン数（値が 0 になると解除）
    private var reducedProbabilityTurns: [MoveCard: Int]
    #if DEBUG
    /// テスト時に優先して返すカード列（先頭から順に消費）
    private var presetDrawQueue: [MoveCard]
    /// reset() で戻すための元配列（テスト専用）
    private var presetOriginal: [MoveCard]
    #endif

    // MARK: - 初期化
    /// デッキを生成する
    /// - Parameter seed: 乱数シード。省略時はシステム乱数から採番する
    init(seed: UInt64? = nil) {
        var systemGenerator = SystemRandomNumberGenerator()
        let resolvedSeed = seed ?? UInt64.random(in: UInt64.min...UInt64.max, using: &systemGenerator)
        initialSeed = resolvedSeed
        #if canImport(GameplayKit)
        random = GKMersenneTwisterRandomSource(seed: resolvedSeed)
        #else
        random = SeededGenerator(seed: resolvedSeed)
        #endif
        reducedProbabilityTurns = [:]
        #if DEBUG
        presetDrawQueue = []
        presetOriginal = []
        #endif
        reset() // 乱数源とテスト用配列を初期状態へ戻す
    }

    // MARK: - リセット
    /// 乱数源を初期シードへ戻し、テスト用キューを再適用する
    mutating func reset() {
        #if canImport(GameplayKit)
        random = GKMersenneTwisterRandomSource(seed: initialSeed)
        #else
        random = SeededGenerator(seed: initialSeed)
        #endif
        reducedProbabilityTurns.removeAll()
        #if DEBUG
        presetDrawQueue = presetOriginal
        #endif
    }

    // MARK: - ドロー処理
    /// 1 枚カードを引く
    /// - Returns: 重み付き抽選によって得られたカード（必ず値を返す想定）
    mutating func draw() -> MoveCard? {
        #if DEBUG
        // テストで事前登録されたカードがあれば優先的に返す
        if !presetDrawQueue.isEmpty {
            let card = presetDrawQueue.removeFirst()
            applyProbabilityReduction(afterDrawing: card)
            return card
        }
        #endif
        guard let card = drawWithDynamicWeights() else { return nil }
        applyProbabilityReduction(afterDrawing: card)
        return card
    }

    /// 複数枚まとめて引く
    /// - Parameter count: 引く枚数
    /// - Returns: 要求枚数分のカード（不足時は取得できた分のみ返す）
    mutating func draw(count: Int) -> [MoveCard] {
        guard count > 0 else { return [] }
        var result: [MoveCard] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            if let card = draw() {
                result.append(card)
            }
        }
        return result
    }

    /// 重み付きプールからインデックスを 1 つ取得する
    /// - Parameter upperBound: 生成したい上限値
    private mutating func nextRandomIndex(upperBound: Int) -> Int {
        #if canImport(GameplayKit)
        return random.nextInt(upperBound: upperBound)
        #else
        let value = random.next()
        return Int(value % UInt64(upperBound))
        #endif
    }

    /// 現在のペナルティ状況を踏まえて動的な重み抽選を実行する
    /// - Returns: 抽選で選ばれたカード（総重量が 0 の場合は nil）
    private mutating func drawWithDynamicWeights() -> MoveCard? {
        var weightedCards: [(card: MoveCard, weight: Int)] = []
        weightedCards.reserveCapacity(MoveCard.allCases.count)
        var totalWeight = 0

        for card in MoveCard.allCases {
            guard let baseWeight = Deck.baseWeights[card] else { continue }
            // ペナルティが残っているカードは 3/4 の重みで抽選する
            let multiplier = (reducedProbabilityTurns[card, default: 0] > 0)
            ? Deck.reducedMultiplier
            : Deck.normalMultiplier
            let weight = baseWeight * multiplier
            weightedCards.append((card, weight))
            totalWeight += weight
        }

        guard totalWeight > 0 else { return nil }

        let randomValue = nextRandomIndex(upperBound: totalWeight)
        var cumulative = 0
        for entry in weightedCards {
            cumulative += entry.weight
            if randomValue < cumulative {
                return entry.card
            }
        }
        // 理論上ここには到達しないが、安全のため最後のカードを返す
        return weightedCards.last?.card
    }

    /// ドロー結果に応じてペナルティ残りターン数を更新する
    /// - Parameter card: 今回排出されたカード
    private mutating func applyProbabilityReduction(afterDrawing card: MoveCard) {
        // 既存のペナルティを 1 ターン進め、0 以下になったら辞書から削除する
        var updated: [MoveCard: Int] = [:]
        updated.reserveCapacity(reducedProbabilityTurns.count)
        for (target, turns) in reducedProbabilityTurns {
            let nextValue = turns - 1
            if nextValue > 0 {
                updated[target] = nextValue
            }
        }
        reducedProbabilityTurns = updated
        // 今回引いたカードに 5 ターン分の抑制を付与する
        reducedProbabilityTurns[card] = Deck.reductionDuration
    }
}

#if !canImport(GameplayKit)
extension Deck {
    /// GameplayKit が無い環境向けの線形合同法ベース乱数生成器
    /// - Note: 非ゼロシードを確保し、`reset()` で再現性を担保する。
    struct SeededGenerator: RandomNumberGenerator {
        /// 内部状態（64bit）
        private var state: UInt64

        /// 初期化子
        /// - Parameter seed: 任意のシード。0 の場合は固定値に置き換える
        init(seed: UInt64) {
            state = seed == 0 ? 0x0123_4567_89AB_CDEF : seed
        }

        /// 次の乱数を生成する
        mutating func next() -> UInt64 {
            // 線形合同法（Numerical Recipes 由来の係数）を採用
            state &*= 6364136223846793005
            state &+= 1
            return state
        }
    }
}
#endif

#if DEBUG
/// テストコードから利用するための拡張
/// - Note: 重み付き抽選を迂回し、指定順のカードを確実に返すための仕組み。
extension Deck {
    /// 任意のカード配列を優先的に返すテスト用デッキを生成する
    /// - Parameter cards: テストで取得したいカード列（先頭が最初のドロー）
    /// - Returns: 指定した配列を消費した後は通常の重み付き抽選に戻るデッキ
    static func makeTestDeck(cards: [MoveCard]) -> Deck {
        var deck = Deck(seed: 0) // 乱数シードを固定し、残りの抽選も再現性を担保
        deck.presetOriginal = cards
        deck.presetDrawQueue = cards
        return deck
    }
}
#endif
