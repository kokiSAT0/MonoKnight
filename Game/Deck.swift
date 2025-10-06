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
            weightProfile: WeightProfile,
            deckSummaryText: String
        ) {
            self.allowedMoves = allowedMoves
            self.allowedMoveIdentities = allowedMoves.map { $0.movePattern.identity }
            self.weightProfile = weightProfile
            self.deckSummaryText = deckSummaryText
        }

        /// 固定座標ワープカードを抽選対象へ追加した新しい設定を返す
        /// - Parameters:
        ///   - weight: 追加する固定ワープカードへ割り当てたい重み（既定値は 1）
        ///   - summarySuffix: 山札概要へ追記するサフィックス（nil の場合は変更しない）
        /// - Returns: 固定ワープカードを含む新しい `Configuration`
        func addingFixedWarpCard(weight: Int = 1, summarySuffix: String? = "＋固定ワープ") -> Configuration {
            let alreadyIncluded = allowedMoves.contains(.fixedWarp)
            var updatedMoves = allowedMoves
            if !alreadyIncluded {
                updatedMoves.append(.fixedWarp)
            }

            let originalWeight = weightProfile.weight(for: .fixedWarp)
            let updatedProfile: WeightProfile
            if alreadyIncluded && originalWeight == weight {
                updatedProfile = weightProfile
            } else {
                updatedProfile = weightProfile.overridingWeight(for: .fixedWarp, weight: weight)
            }

            let updatedSummary: String
            if !alreadyIncluded, let suffix = summarySuffix, !suffix.isEmpty {
                updatedSummary = deckSummaryText + suffix
            } else {
                updatedSummary = deckSummaryText
            }

            if alreadyIncluded && originalWeight == weight && updatedSummary == deckSummaryText {
                return self
            }

            return Configuration(
                allowedMoves: updatedMoves,
                weightProfile: updatedProfile,
                deckSummaryText: updatedSummary
            )
        }

        /// スタンダードモード向け設定
        static let standard: Configuration = {
            // 現時点ではすべてのカードを均一重みで扱う
            let overrides: [MoveCard: Int] = [:] // 将来的な調整時にここへ個別設定を追加する
            return Configuration(
                allowedMoves: MoveCard.standardSet,
                weightProfile: WeightProfile(defaultWeight: 1, overrides: overrides),
                deckSummaryText: "標準デッキ"
            )
        }()

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

        /// 連続レイ型カードの練習に特化した構成
        /// - Note: レイ型カードは重み 3、サポート用に上下左右キングを重み 1 で混在させ、盤面調整しやすくする
        static let directionalRayFocus: Configuration = {
            let rayCards = MoveCard.directionalRayCards
            let supportKings: [MoveCard] = [.kingUp, .kingRight, .kingDown, .kingLeft]
            let allowedMoves = rayCards + supportKings
            let overrides = Dictionary(uniqueKeysWithValues: rayCards.map { ($0, 3) })
            return Configuration(
                allowedMoves: allowedMoves,
                weightProfile: WeightProfile(defaultWeight: 1, overrides: overrides),
                deckSummaryText: "連続移動カード集中デッキ"
            )
        }()

        /// 標準デッキへ上下左右の選択キングカードを加えた構成
        /// - Note: 標準セットの操作感を維持しながら、選択式カードの導入に慣れてもらうためのプリセット。
        static let standardWithOrthogonalChoices: Configuration = {
            let choiceCards: [MoveCard] = [.kingUpOrDown, .kingLeftOrRight]
            let allowedMoves = MoveCard.standardSet + choiceCards
            // 選択式カードの初動習得を早めるため、該当カードだけ重みを 2 に引き上げてドロー頻度を上げる
            let overrides = Dictionary(uniqueKeysWithValues: choiceCards.map { ($0, 2) })
            return Configuration(
                allowedMoves: allowedMoves,
                weightProfile: WeightProfile(defaultWeight: 1, overrides: overrides),
                deckSummaryText: "標準＋上下左右選択キング"
            )
        }()

        /// 標準デッキへ斜め方向の選択キングカードを追加した構成
        /// - Note: 角方向の補完を狙う練習向けに、既存カードへ斜め選択を足した形で提供する。
        static let standardWithDiagonalChoices: Configuration = {
            let choiceCards: [MoveCard] = [
                .kingUpwardDiagonalChoice,
                .kingRightDiagonalChoice,
                .kingDownwardDiagonalChoice,
                .kingLeftDiagonalChoice
            ]
            let allowedMoves = MoveCard.standardSet + choiceCards
            // 斜め選択カードの練習段階では、プレイヤーが積極的に引けるよう重み 2 の上書きを適用する
            let overrides = Dictionary(uniqueKeysWithValues: choiceCards.map { ($0, 2) })
            return Configuration(
                allowedMoves: allowedMoves,
                weightProfile: WeightProfile(defaultWeight: 1, overrides: overrides),
                deckSummaryText: "標準＋斜め選択キング"
            )
        }()

        /// 標準デッキへ桂馬の選択カードを加えた構成
        /// - Note: 長距離ジャンプを補強しつつ、通常カードのドロー頻度も維持するための折衷案。
        static let standardWithKnightChoices: Configuration = {
            let choiceCards: [MoveCard] = [
                .knightUpwardChoice,
                .knightRightwardChoice,
                .knightDownwardChoice,
                .knightLeftwardChoice
            ]
            let allowedMoves = MoveCard.standardSet + choiceCards
            // 桂馬の複方向ジャンプを習得しやすくするため、選択式桂馬カードだけ重み 2 で抽選されるようにする
            let overrides = Dictionary(uniqueKeysWithValues: choiceCards.map { ($0, 2) })
            return Configuration(
                allowedMoves: allowedMoves,
                weightProfile: WeightProfile(defaultWeight: 1, overrides: overrides),
                deckSummaryText: "標準＋桂馬選択カード"
            )
        }()

        /// 標準デッキへ全選択カードを網羅的に追加した構成
        /// - Note: 最終的な多方向対応力を測るため、標準セットに全選択カード 10 種をミックスする。
        static let standardWithAllChoices: Configuration = {
            let selectionCards: [MoveCard] = [
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
            let specialAdditions: [MoveCard] = selectionCards + [.superWarp]
            let allowedMoves = MoveCard.standardSet + specialAdditions
            // 選択式カードは重み 2、全域ワープは希少性を保つため重み 1 を適用する
            var overrides = Dictionary(uniqueKeysWithValues: selectionCards.map { ($0, 2) })
            overrides[.superWarp] = 1
            return Configuration(
                allowedMoves: allowedMoves,
                weightProfile: WeightProfile(defaultWeight: 1, overrides: overrides),
                deckSummaryText: "標準＋全選択カード＋ワープ"
            )
        }()

        /// 標準デッキへワープカードを段階的に組み込んだ構成
        /// - Note: 固定ワープは 3、スーパーワープは 2 の重みで供給し、訓練目的で出現頻度を引き上げる
        static let standardWithWarpCards: Configuration = {
            let warpCards: [MoveCard] = [.fixedWarp, .superWarp]
            let allowedMoves = MoveCard.standardSet + warpCards
            let overrides: [MoveCard: Int] = [
                .fixedWarp: 3,
                .superWarp: 2
            ]
            return Configuration(
                allowedMoves: allowedMoves,
                weightProfile: WeightProfile(defaultWeight: 1, overrides: overrides),
                deckSummaryText: "標準＋ワープ／スーパーワープ"
            )
        }()

        /// クラシカルチャレンジ向け設定（桂馬のみ・均等抽選）
        static let classicalChallenge: Configuration = {
            let knightMoves = MoveCard.standardSet.filter { $0.isKnightType }
            return Configuration(
                allowedMoves: knightMoves,
                weightProfile: WeightProfile(defaultWeight: 1),
                deckSummaryText: "桂馬カードのみ"
            )
        }()

        /// 王将型カードのみを排出する短距離構成
        static let kingOnly: Configuration = {
            let kingMoves = MoveCard.standardSet.filter { $0.isKingType }
            return Configuration(
                allowedMoves: kingMoves,
                weightProfile: WeightProfile(defaultWeight: 1),
                deckSummaryText: "王将カードのみ"
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

        /// 上下左右を選択できる複数方向カードを含む 5×5 盤向け構成
        static let directionChoice: Configuration = {
            let choiceCards: [MoveCard] = [.kingUpOrDown, .kingLeftOrRight]
            let allowedMoves = MoveCard.standardSet + choiceCards
            let overrides: [MoveCard: Int] = [:] // 将来的に選択カードへ個別重みを設定したい場合に備える
            return Configuration(
                allowedMoves: allowedMoves,
                weightProfile: WeightProfile(defaultWeight: 1, overrides: overrides),
                deckSummaryText: "選択式キングカード入り"
            )
        }()

        /// キング型の上下左右選択カードのみで構成した訓練用デッキ
        static let kingOrthogonalChoiceOnly: Configuration = {
            let moves: [MoveCard] = [.kingUpOrDown, .kingLeftOrRight]
            return Configuration(
                allowedMoves: moves,
                weightProfile: WeightProfile(defaultWeight: 1),
                deckSummaryText: "上下左右の選択キング限定"
            )
        }()

        /// キング 4 種と桂馬 4 種のみを収録した限定デッキ
        /// - Note: 直感的な上下左右移動と跳躍行動だけで構成し、操作習熟を狙う
        static let kingPlusKnightOnly: Configuration = {
            let kingMoves: [MoveCard] = [.kingUp, .kingRight, .kingDown, .kingLeft]
            let knightMoves: [MoveCard] = [
                .knightUp2Right1,
                .knightUp2Left1,
                .knightDown2Right1,
                .knightDown2Left1
            ]
            let moves = kingMoves + knightMoves
            return Configuration(
                allowedMoves: moves,
                weightProfile: WeightProfile(defaultWeight: 1),
                deckSummaryText: "キングと桂馬の限定デッキ"
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
                deckSummaryText: "選択カード総合ミックス"
            )
        }()

        /// 複数マス移動カードとサポート用キングカードを組み合わせた拡張デッキ
        /// - Note: レイ型カードを重み 3 に設定し、連続移動の出現率を高めつつ基本 4 方向キングで調整力を確保する
        static let extendedWithMultiStepMoves: Configuration = {
            let multiStepCards = MoveCard.directionalRayCards
            let supportKings: [MoveCard] = [.kingUp, .kingRight, .kingDown, .kingLeft]
            let allowedMoves = multiStepCards + supportKings
            let overrides = Dictionary(uniqueKeysWithValues: multiStepCards.map { ($0, 3) })
            return Configuration(
                allowedMoves: allowedMoves,
                weightProfile: WeightProfile(defaultWeight: 1, overrides: overrides),
                deckSummaryText: "複数マス移動カード拡張デッキ"
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
            return DealtCard(move: move)
        }
#endif
        guard let move = drawWithDynamicWeights() else { return nil }
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
    /// - Note: 連続排出抑制を廃止し、基礎重みのみで抽選するシンプルな構成へ統一している。
    /// - Returns: 抽選で選ばれたカード（総重量が 0 の場合は nil）
    private mutating func drawWithDynamicWeights() -> MoveCard? {
        var weightedCards: [(card: MoveCard, weight: Int)] = []
        weightedCards.reserveCapacity(configuration.allowedMoves.count)
        var totalWeight = 0

        for card in configuration.allowedMoves {
            let weight = configuration.weightProfile.weight(for: card)
            // 重みが 0 以下の場合は抽選対象から除外する（安全策）
            guard weight > 0 else { continue }
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
