import Foundation
#if canImport(GameplayKit)
import GameplayKit
#endif

/// 山札を重み付き乱数で生成するデッキ構造体
/// - Note: ゲームモードごとに許可カードや重み付けが異なるため、`Configuration` で挙動を切り替えられるようにしている。
struct Deck {
    // MARK: - 重みプロファイル
    /// カードの基礎重みと個別上書きをまとめて扱う構造体
    /// - Note: すべてのカードに同一値を設定しつつ、一部カードのみ将来的に重みを調整したいニーズへ対応するための抽象化。
    struct WeightProfile {
        /// 全カードへ適用するデフォルト重み
        let defaultWeight: Int
        /// カードごとの個別重み（必要に応じて上書きする）
        private let overrides: [MoveCard: Int]

        /// メンバーごとに初期化するためのイニシャライザ
        /// - Parameters:
        ///   - defaultWeight: 全カードに適用する基礎重み
        ///   - overrides: 特定カードのみ重みを上書きしたい場合の辞書
        init(defaultWeight: Int, overrides: [MoveCard: Int] = [:]) {
            self.defaultWeight = defaultWeight
            self.overrides = overrides
        }

        /// 指定カードに対する最終的な重みを返す
        /// - Parameter card: 評価対象のカード
        /// - Returns: 上書き値が存在すればそれを、無ければデフォルト重みを返す
        func weight(for card: MoveCard) -> Int {
            overrides[card] ?? defaultWeight
        }

        /// 特定カードの重みを上書きした新しいプロファイルを生成する
        /// - Parameters:
        ///   - card: 上書き対象のカード
        ///   - weight: 設定したい重み
        /// - Returns: 指定カードに個別重みを設定した `WeightProfile`
        func overridingWeight(for card: MoveCard, weight: Int) -> WeightProfile {
            var updatedOverrides = overrides
            updatedOverrides[card] = weight
            return WeightProfile(defaultWeight: defaultWeight, overrides: updatedOverrides)
        }
    }

    // MARK: - 設定定義
    /// 山札の構成や重み付けルールを表す設定構造体
    struct Configuration {
        /// 抽選対象とするカード一覧（順序を維持する）
        let allowedMoves: [MoveCard]
        /// 抽選対象とする補助カード一覧（順序を維持する）
        let allowedSupportCards: [SupportCard]
        /// 抽選対象カード本体（移動カード + 補助カード）
        let allowedPlayableCards: [PlayableCard]
        /// 抽選対象カードの移動パターン ID（順序を維持する）
        let allowedMoveIdentities: [MoveCard.MovePattern.Identity]
        /// 重み計算ロジックをまとめたプロファイル
        let weightProfile: WeightProfile
        /// UI やモード説明で利用する山札の要約テキスト
        let deckSummaryText: String

        /// メンバーごとに初期化できるよう明示的なイニシャライザを用意
        /// - Parameters:
        ///   - allowedMoves: 抽選対象とするカード配列
        ///   - weightProfile: 重み計算を管理するプロファイル
        ///   - deckSummaryText: UI 表示用の簡易説明
        init(
            allowedMoves: [MoveCard],
            allowedSupportCards: [SupportCard] = [],
            weightProfile: WeightProfile,
            deckSummaryText: String
        ) {
            self.allowedMoves = allowedMoves
            self.allowedSupportCards = allowedSupportCards
            self.allowedPlayableCards = allowedMoves.map(PlayableCard.move) + allowedSupportCards.map(PlayableCard.support)
            self.allowedMoveIdentities = allowedMoves.map { $0.movePattern.identity }
            self.weightProfile = weightProfile
            self.deckSummaryText = deckSummaryText
        }

        /// ラン中の報酬カードを山札構成へ加えた新しい設定を返す
        /// - Note: 既存カードは重みを増やし、未収録カードは抽選対象へ追加する。
        func addingBonusMoveCards(_ cards: [MoveCard]) -> Configuration {
            guard !cards.isEmpty else { return self }

            let cardCounts = Dictionary(grouping: cards, by: { $0 }).mapValues(\.count)
            var updatedMoves = allowedMoves
            var updatedProfile = weightProfile

            for card in cards {
                if !updatedMoves.contains(card) {
                    updatedMoves.append(card)
                }
            }

            for (card, count) in cardCounts {
                let currentWeight = updatedProfile.weight(for: card)
                updatedProfile = updatedProfile.overridingWeight(for: card, weight: currentWeight + count)
            }

            let rewardText = cards.map(\.displayName).joined(separator: "、")
            return Configuration(
                allowedMoves: updatedMoves,
                allowedSupportCards: allowedSupportCards,
                weightProfile: updatedProfile,
                deckSummaryText: deckSummaryText + "＋報酬: " + rewardText
            )
        }

        /// 長距離カードの出現率を下げた標準派生デッキ
        /// - Note: 直線 2 マスと斜め 2 マスのカードだけ重みを下げ、初心者向けに調整する
        static let standardLight: Configuration = {
            let allowedMoves = MoveCard.standardSet
            // 長距離カード（距離 2 系＋レイ型）を個別に上書きし、重み 1 で出現頻度を抑える
            let longRangeCards: [MoveCard] = MoveCard.directionalRayCards + [
                .straightUp2,
                .straightDown2,
                .straightRight2,
                .straightLeft2,
                .diagonalUpRight2,
                .diagonalDownRight2,
                .diagonalDownLeft2,
                .diagonalUpLeft2
            ]
            let overrides = Dictionary(uniqueKeysWithValues: longRangeCards.map { ($0, 1) })
            return Configuration(
                allowedMoves: allowedMoves,
                weightProfile: WeightProfile(defaultWeight: 3, overrides: overrides),
                deckSummaryText: "長距離カード抑制型標準デッキ"
            )
        }()
        /// キングと桂馬 16 種をまとめた基礎デッキ
        /// - Note: 長距離カードを除外し、短距離移動の練習に集中しやすくする
        static let kingAndKnightBasic: Configuration = {
            let allowedMoves = MoveCard.standardSet.filter { $0.isKingType || $0.isKnightType }
            return Configuration(
                allowedMoves: allowedMoves,
                weightProfile: WeightProfile(defaultWeight: 1),
                deckSummaryText: "キングと桂馬の基礎デッキ"
            )
        }()
    }

    // MARK: - プロパティ
    /// 現在採用している設定
    private let configuration: Configuration
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
    private var presetDrawQueue: [PlayableCard]
    /// reset() で戻すための元配列（テスト専用）
    private var presetOriginal: [PlayableCard]
    #endif

    // MARK: - 初期化
    /// デッキを生成する
    /// - Parameters:
    ///   - seed: 乱数シード。省略時はシステム乱数から採番する
    ///   - configuration: 採用する山札設定
    init(
        seed: UInt64? = nil,
        configuration: Configuration = .standardLight
    ) {
        self.configuration = configuration
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

    /// 設定から得られるユニークな移動パターン数を返す
    /// - Returns: 許可された移動パターン ID の種類数（重複は 1 つにまとめる）
    func uniqueMoveIdentityCount() -> Int {
        let unique = Set(configuration.allowedMoveIdentities)
        return unique.count + configuration.allowedSupportCards.count
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
    mutating func draw() -> DealtCard? {
#if DEBUG
        // テストで事前登録されたカードがあれば優先的に返す
        if !presetDrawQueue.isEmpty {
            let playable = presetDrawQueue.removeFirst()
            return makeDealtCard(for: playable)
        }
#endif
        guard let playable = drawWithDynamicWeights() else { return nil }
        return makeDealtCard(for: playable)
    }

    /// 複数枚まとめて引く
    /// - Parameter count: 引く枚数
    /// - Returns: 要求枚数分のカード（不足時は取得できた分のみ返す）
    mutating func draw(count: Int) -> [DealtCard] {
        guard count > 0 else { return [] }
        var result: [DealtCard] = []
        result.reserveCapacity(count)
        for _ in 0..<count {
            if let card = draw() {
                result.append(card)
            }
        }
        return result
    }

    /// 指定されたカード種別に応じて `DealtCard` を生成する
    /// - Parameter move: 山札から取り出した `MoveCard`
    /// - Returns: 山札から配る `DealtCard`
    private mutating func makeDealtCard(for move: MoveCard) -> DealtCard {
        makeDealtCard(for: .move(move))
    }

    /// 指定されたカード種別に応じて `DealtCard` を生成する
    private mutating func makeDealtCard(for playable: PlayableCard) -> DealtCard {
        DealtCard(playable: playable)
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

    /// 現在の設定に基づき動的な重み抽選を実行する
    /// - Note: 連続排出抑制を廃止し、基礎重みのみで抽選するシンプルな構成へ統一している。
    /// - Returns: 抽選で選ばれたカード（総重量が 0 の場合は nil）
    private mutating func drawWithDynamicWeights() -> PlayableCard? {
        var weightedCards: [(card: PlayableCard, weight: Int)] = []
        weightedCards.reserveCapacity(configuration.allowedPlayableCards.count)
        var totalWeight = 0

        for card in configuration.allowedMoves {
            let weight = configuration.weightProfile.weight(for: card)
            // 重みが 0 以下の場合は抽選対象から除外する（安全策）
            guard weight > 0 else { continue }
            weightedCards.append((.move(card), weight))
            totalWeight += weight
        }

        for support in configuration.allowedSupportCards {
            let weight = configuration.weightProfile.defaultWeight
            guard weight > 0 else { continue }
            weightedCards.append((.support(support), weight))
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
}

#if DEBUG
extension Deck {
    /// テストで特定順序のカードを排出させたい場合に使用する
    /// - Parameters:
    ///   - cards: 先頭から順番に返したいカード列
    mutating func preload(
        cards: [MoveCard]
    ) {
        preload(
            playableCards: cards.map(PlayableCard.move)
        )
    }

    mutating func preload(
        playableCards: [PlayableCard]
    ) {
        presetDrawQueue = playableCards
        presetOriginal = playableCards
    }

    /// プリセットしたカード列を優先的に返すテスト用デッキを生成する
    /// - Parameters:
    ///   - seed: 乱数シード。省略時は 1 を使用し、`reset()` で同じ抽選列を再現できるようにする
    ///   - cards: 先頭から消費させたいカード列（手札スロット数ぶんを優先消費し、残りが先読みキューへ入る）
    ///   - configuration: 検証対象の山札設定（省略時はスタンダード）
    /// - Returns: プリセットを持った `Deck`
    static func makeTestDeck(
        seed: UInt64 = 1,
        cards: [MoveCard],
        configuration: Configuration = .standardLight
    ) -> Deck {
        var deck = Deck(seed: seed, configuration: configuration)
        deck.preload(cards: cards)
        return deck
    }

    static func makeTestDeck(
        seed: UInt64 = 1,
        playableCards: [PlayableCard],
        configuration: Configuration = .standardLight
    ) -> Deck {
        var deck = Deck(seed: seed, configuration: configuration)
        deck.preload(playableCards: playableCards)
        return deck
    }
}
#endif

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
            state = seed == 0 ? 0x4d595df4d0f33173 : seed
        }

        mutating func next() -> UInt64 {
            // LCG のパラメータは Numerical Recipes の推奨値
            state = 6364136223846793005 &* state &+ 1442695040888963407
            return state
        }
    }
}
#endif
