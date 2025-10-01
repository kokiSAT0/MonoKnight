import Foundation
#if canImport(GameplayKit)
import GameplayKit
#endif

/// 山札を重み付き乱数で生成するデッキ構造体
/// - Note: ゲームモードごとに許可カードや重み付けが異なるため、`Configuration` で挙動を切り替えられるようにしている。
struct Deck {
    /// 移動ベクトル配列を集合化する際に利用する内部シグネチャ構造体
    /// - Note: `MoveVector` 自体は `Hashable` だが、配列として扱う際に毎回ハッシュ計算を記述するのは煩雑なため、ラッパーを用意する
    private struct MoveSignature: Hashable {
        /// 比較対象となる移動ベクトル列
        let vectors: [MoveVector]

        /// 明示的なイニシャライザを設けておき、意図した配列のみを扱う
        /// - Parameter vectors: 比較したい移動ベクトル配列
        init(vectors: [MoveVector]) {
            self.vectors = vectors
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(vectors.count)
            for vector in vectors {
                hasher.combine(vector)
            }
        }

        static func == (lhs: MoveSignature, rhs: MoveSignature) -> Bool {
            lhs.vectors == rhs.vectors
        }
    }
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
    }

    // MARK: - 設定定義
    /// 山札の構成や重み付けルールを表す設定構造体
    struct Configuration {
        /// 抽選対象とするカード一覧（順序を維持する）
        let allowedMoves: [MoveCard]
        /// 抽選対象カードの移動ベクトル配列（順序を維持する）
        let allowedMoveSignatures: [[MoveVector]]
        /// 重み計算ロジックをまとめたプロファイル
        let weightProfile: WeightProfile
        /// 連続排出抑制を行うかどうか
        let shouldApplyProbabilityReduction: Bool
        /// 通常時に掛ける重み倍率（整数比で扱う）
        let normalWeightMultiplier: Int
        /// 抑制中に掛ける重み倍率
        let reducedWeightMultiplier: Int
        /// 抑制状態を維持するターン数
        let reductionDuration: Int
        /// UI やモード説明で利用する山札の要約テキスト
        let deckSummaryText: String

        /// メンバーごとに初期化できるよう明示的なイニシャライザを用意
        /// - Parameters:
        ///   - allowedMoves: 抽選対象とするカード配列
        ///   - weightProfile: 重み計算を管理するプロファイル
        ///   - shouldApplyProbabilityReduction: 連続排出抑制の有無
        ///   - normalWeightMultiplier: 通常時に掛ける重み倍率
        ///   - reducedWeightMultiplier: 抑制時に掛ける重み倍率
        ///   - reductionDuration: 抑制効果を持続させるターン数
        ///   - deckSummaryText: UI 表示用の簡易説明
        init(
            allowedMoves: [MoveCard],
            weightProfile: WeightProfile,
            shouldApplyProbabilityReduction: Bool,
            normalWeightMultiplier: Int,
            reducedWeightMultiplier: Int,
            reductionDuration: Int,
            deckSummaryText: String
        ) {
            self.allowedMoves = allowedMoves
            self.allowedMoveSignatures = allowedMoves.map { $0.movementVectors }
            self.weightProfile = weightProfile
            self.shouldApplyProbabilityReduction = shouldApplyProbabilityReduction
            self.normalWeightMultiplier = normalWeightMultiplier
            self.reducedWeightMultiplier = reducedWeightMultiplier
            self.reductionDuration = reductionDuration
            self.deckSummaryText = deckSummaryText
        }

        /// スタンダードモード向け設定
        static let standard: Configuration = {
            // 現時点ではすべてのカードを均一重みで扱う
            let overrides: [MoveCard: Int] = [:] // 将来的な調整時にここへ個別設定を追加する
            return Configuration(
                allowedMoves: MoveCard.standardSet,
                weightProfile: WeightProfile(defaultWeight: 1, overrides: overrides),
                shouldApplyProbabilityReduction: true,
                normalWeightMultiplier: 4,
                reducedWeightMultiplier: 3,
                reductionDuration: 5,
                deckSummaryText: "標準デッキ"
            )
        }()

        /// クラシカルチャレンジ向け設定（桂馬のみ・均等抽選）
        static let classicalChallenge: Configuration = {
            let knightMoves = MoveCard.standardSet.filter { $0.isKnightType }
            return Configuration(
                allowedMoves: knightMoves,
                weightProfile: WeightProfile(defaultWeight: 1),
                shouldApplyProbabilityReduction: false,
                normalWeightMultiplier: 1,
                reducedWeightMultiplier: 1,
                reductionDuration: 0,
                deckSummaryText: "桂馬カードのみ"
            )
        }()

        /// 王将型カードのみを排出する短距離構成
        static let kingOnly: Configuration = {
            let kingMoves = MoveCard.standardSet.filter { $0.isKingType }
            return Configuration(
                allowedMoves: kingMoves,
                weightProfile: WeightProfile(defaultWeight: 1),
                shouldApplyProbabilityReduction: false,
                normalWeightMultiplier: 1,
                reducedWeightMultiplier: 1,
                reductionDuration: 0,
                deckSummaryText: "王将カードのみ"
            )
        }()

        /// 上下左右を選択できる複数方向カードを含む 5×5 盤向け構成
        static let directionChoice: Configuration = {
            let choiceCards: [MoveCard] = [.kingUpOrDown, .kingLeftOrRight]
            let allowedMoves = MoveCard.standardSet + choiceCards
            let overrides: [MoveCard: Int] = [:] // 将来的に選択カードへ個別重みを設定したい場合に備える
            return Configuration(
                allowedMoves: allowedMoves,
                weightProfile: WeightProfile(defaultWeight: 1, overrides: overrides),
                shouldApplyProbabilityReduction: true,
                normalWeightMultiplier: 4,
                reducedWeightMultiplier: 3,
                reductionDuration: 5,
                deckSummaryText: "選択式キングカード入り"
            )
        }()

        /// キング型の上下左右選択カードのみで構成した訓練用デッキ
        static let kingOrthogonalChoiceOnly: Configuration = {
            let moves: [MoveCard] = [.kingUpOrDown, .kingLeftOrRight]
            return Configuration(
                allowedMoves: moves,
                weightProfile: WeightProfile(defaultWeight: 1),
                shouldApplyProbabilityReduction: false,
                normalWeightMultiplier: 1,
                reducedWeightMultiplier: 1,
                reductionDuration: 0,
                deckSummaryText: "上下左右の選択キング限定"
            )
        }()

        /// 斜め方向のキング選択カード 4 種のみを収録した上級者向けデッキ
        static let kingDiagonalChoiceOnly: Configuration = {
            let moves: [MoveCard] = [
                .kingUpwardDiagonalChoice,
                .kingRightDiagonalChoice,
                .kingDownwardDiagonalChoice,
                .kingLeftDiagonalChoice
            ]
            return Configuration(
                allowedMoves: moves,
                weightProfile: WeightProfile(defaultWeight: 1),
                shouldApplyProbabilityReduction: false,
                normalWeightMultiplier: 1,
                reducedWeightMultiplier: 1,
                reductionDuration: 0,
                deckSummaryText: "斜め選択キング限定"
            )
        }()

        /// 桂馬の向きごとに選択肢を持つカードだけを集めた練習デッキ
        static let knightChoiceOnly: Configuration = {
            let moves: [MoveCard] = [
                .knightUpwardChoice,
                .knightRightwardChoice,
                .knightDownwardChoice,
                .knightLeftwardChoice
            ]
            return Configuration(
                allowedMoves: moves,
                weightProfile: WeightProfile(defaultWeight: 1),
                shouldApplyProbabilityReduction: false,
                normalWeightMultiplier: 1,
                reducedWeightMultiplier: 1,
                reductionDuration: 0,
                deckSummaryText: "桂馬選択カード限定"
            )
        }()

        /// すべての選択式カードを均等配分で混在させた総合練習デッキ
        static let allChoiceMixed: Configuration = {
            let moves: [MoveCard] = [
                .kingUpOrDown,
                .kingLeftOrRight,
                .kingUpwardDiagonalChoice,
                .kingRightDiagonalChoice,
                .kingDownwardDiagonalChoice,
                .kingLeftDiagonalChoice,
                .knightUpwardChoice,
                .knightRightwardChoice,
                .knightDownwardChoice,
                .knightLeftwardChoice
            ]
            return Configuration(
                allowedMoves: moves,
                weightProfile: WeightProfile(defaultWeight: 1),
                shouldApplyProbabilityReduction: false,
                normalWeightMultiplier: 1,
                reducedWeightMultiplier: 1,
                reductionDuration: 0,
                deckSummaryText: "選択カード総合ミックス"
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
    /// - Parameters:
    ///   - seed: 乱数シード。省略時はシステム乱数から採番する
    ///   - configuration: 採用する山札設定
    init(seed: UInt64? = nil, configuration: Configuration = .standard) {
        self.configuration = configuration
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

    /// 設定から得られるユニークな移動シグネチャ数を返す
    /// - Returns: 許可された移動ベクトル配列の種類数（重複は 1 つにまとめる）
    func uniqueMoveSignatureCount() -> Int {
        let signatures = configuration.allowedMoveSignatures.map { MoveSignature(vectors: $0) }
        let unique = Set(signatures)
        return unique.count
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
    mutating func draw() -> DealtCard? {
#if DEBUG
        // テストで事前登録されたカードがあれば優先的に返す
        if !presetDrawQueue.isEmpty {
            let move = presetDrawQueue.removeFirst()
            applyProbabilityReduction(afterDrawing: move)
            return DealtCard(move: move)
        }
#endif
        guard let move = drawWithDynamicWeights() else { return nil }
        applyProbabilityReduction(afterDrawing: move)
        return DealtCard(move: move)
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
    /// - Returns: 抽選で選ばれたカード（総重量が 0 の場合は nil）
    private mutating func drawWithDynamicWeights() -> MoveCard? {
        var weightedCards: [(card: MoveCard, weight: Int)] = []
        weightedCards.reserveCapacity(configuration.allowedMoves.count)
        var totalWeight = 0

        for card in configuration.allowedMoves {
            let baseWeight = configuration.weightProfile.weight(for: card)
            // 重みが 0 以下の場合は抽選対象から除外する（安全策）
            guard baseWeight > 0 else { continue }
            let isReduced = configuration.shouldApplyProbabilityReduction && (reducedProbabilityTurns[card, default: 0] > 0)
            let multiplier = isReduced ? configuration.reducedWeightMultiplier : configuration.normalWeightMultiplier
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
        guard configuration.shouldApplyProbabilityReduction, configuration.reductionDuration > 0 else {
            return
        }
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
        // 今回引いたカードに抑制を付与する
        reducedProbabilityTurns[card] = configuration.reductionDuration
    }
}

#if DEBUG
extension Deck {
    /// テストで特定順序のカードを排出させたい場合に使用する
    /// - Parameter cards: 先頭から順番に返したいカード列
    mutating func preload(cards: [MoveCard]) {
        presetDrawQueue = cards
        presetOriginal = cards
    }

    /// プリセットしたカード列を優先的に返すテスト用デッキを生成する
    /// - Parameters:
    ///   - cards: 先頭から消費させたいカード列（手札スロット数ぶんを優先消費し、残りが先読みキューへ入る）
    ///   - configuration: 検証対象の山札設定（省略時はスタンダード）
    /// - Returns: プリセットを持った `Deck`
    static func makeTestDeck(cards: [MoveCard], configuration: Configuration = .standard) -> Deck {
        var deck = Deck(seed: 1, configuration: configuration)
        deck.preload(cards: cards)
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
