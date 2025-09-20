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
    /// 重み付き抽選用のプール（重み分だけ複製した配列）
    private static let weightedPool: [MoveCard] = {
        var pool: [MoveCard] = []
        pool.reserveCapacity(MoveCard.allCases.count * kingWeight)
        for card in MoveCard.allCases {
            // 王将型カードは高頻度、ナイト型と直線型は標準、斜め 2 マスは低頻度に設定
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
            pool.append(contentsOf: Array(repeating: card, count: weight))
        }
        return pool
    }()

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
            return presetDrawQueue.removeFirst()
        }
        #endif
        guard !Deck.weightedPool.isEmpty else { return nil }
        let index = nextRandomIndex(upperBound: Deck.weightedPool.count)
        return Deck.weightedPool[index]
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
