import Foundation

/// ゲームルール一式をまとめたモード設定
/// - Note: 盤サイズや山札構成、ペナルティ量などをまとめて扱うことで、新モード追加時の分岐を最小限に抑える。
/// 山札プリセットを識別し、UI からも扱いやすいように公開する列挙体
/// - Note: それぞれのケースは `Deck.Configuration` へ変換可能で、表示名や概要テキストも併せて提供する
public enum GameDeckPreset: String, CaseIterable, Codable, Identifiable {
    /// スタンダードモードと同じ山札構成
    case standard
    /// 長距離カードの出現頻度を抑えた標準構成
    case standardLight
    /// クラシカルチャレンジと同じ桂馬のみの構成
    case classicalChallenge
    /// 王将型カードのみの構成（序盤向け超短距離デッキ）
    case kingOnly
    /// キングと桂馬の基本 16 種を収録した構成
    case kingAndKnightBasic
    /// キング 4 種と桂馬 4 種のみで構成した訓練向けデッキ
    case kingPlusKnightOnly
    /// キング型カードに上下左右の選択肢を加えた構成
    case directionChoice
    /// レイ型カードを主体とした連続移動構成
    case directionalRayFocus
    /// 標準デッキに上下左右の選択キングを加えた構成
    case standardWithOrthogonalChoices
    /// 標準デッキに斜め選択キングを加えた構成
    case standardWithDiagonalChoices
    /// 標準デッキに桂馬の選択カードを加えた構成
    case standardWithKnightChoices
    /// 標準デッキにすべての選択カードを加えた構成
    case standardWithAllChoices
    /// 標準デッキにワープカードを加えた構成
    case standardWithWarpCards
    /// 複数マス移動カードを重視した拡張構成
    case extendedWithMultiStepMoves
    /// 上下左右の選択キングカードのみで構成した訓練デッキ
    case kingOrthogonalChoiceOnly
    /// 斜め方向の選択キングカードのみで構成した訓練デッキ
    case kingDiagonalChoiceOnly
    /// 桂馬の選択カードのみで構成した訓練デッキ
    case knightChoiceOnly
    /// すべての選択カードを混合した総合デッキ
    case allChoiceMixed

    /// `Identifiable` 準拠用の ID
    public var id: String { rawValue }

    /// UI で表示する名称
    public var displayName: String {
        switch self {
        case .standard:
            return "スタンダード構成"
        case .standardLight:
            return "スタンダード軽量構成"
        case .classicalChallenge:
            return "クラシカル構成"
        case .kingOnly:
            return "王将構成"
        case .kingAndKnightBasic:
            return "キング＋ナイト基礎構成"
        case .kingPlusKnightOnly:
            return "キング＋ナイト限定構成"
        case .directionChoice:
            return "選択式キング構成"
        case .directionalRayFocus:
            return "連続移動カード構成"
        case .standardWithOrthogonalChoices:
            return "標準＋縦横選択キング構成"
        case .standardWithDiagonalChoices:
            return "標準＋斜め選択キング構成"
        case .standardWithKnightChoices:
            return "標準＋桂馬選択構成"
        case .standardWithAllChoices:
            return "標準＋全選択カード構成"
        case .standardWithWarpCards:
            return "標準＋ワープカード構成"
        case .extendedWithMultiStepMoves:
            return "複数マス移動拡張構成"
        case .kingOrthogonalChoiceOnly:
            return "上下左右選択キング構成"
        case .kingDiagonalChoiceOnly:
            return "斜め選択キング構成"
        case .knightChoiceOnly:
            return "桂馬選択構成"
        case .allChoiceMixed:
            return "選択カード総合構成"
        }
    }

    /// 山札構成の概要テキスト
    public var summaryText: String {
        configuration.deckSummaryText
    }

    /// 実際に利用する `Deck.Configuration`
    var configuration: Deck.Configuration {
        switch self {
        case .standard:
            return .standard
        case .standardLight:
            return .standardLight
        case .classicalChallenge:
            return .classicalChallenge
        case .kingOnly:
            return .kingOnly
        case .kingAndKnightBasic:
            return .kingAndKnightBasic
        case .kingPlusKnightOnly:
            return .kingPlusKnightOnly
        case .directionChoice:
            return .directionChoice
        case .directionalRayFocus:
            return .directionalRayFocus
        case .standardWithOrthogonalChoices:
            return .standardWithOrthogonalChoices
        case .standardWithDiagonalChoices:
            return .standardWithDiagonalChoices
        case .standardWithKnightChoices:
            return .standardWithKnightChoices
        case .standardWithAllChoices:
            return .standardWithAllChoices
        case .standardWithWarpCards:
            return .standardWithWarpCards
        case .extendedWithMultiStepMoves:
            return .extendedWithMultiStepMoves
        case .kingOrthogonalChoiceOnly:
            return .kingOrthogonalChoiceOnly
        case .kingDiagonalChoiceOnly:
            return .kingDiagonalChoiceOnly
        case .knightChoiceOnly:
            return .knightChoiceOnly
        case .allChoiceMixed:
            return .allChoiceMixed
        }
    }

    /// 固定ワープカードを含めた構成を取得するヘルパー
    /// - Parameters:
    ///   - weight: 固定ワープカードへ割り当てたい重み（既定値は 1）
    ///   - summarySuffix: 山札概要テキストへ追記するサフィックス（nil の場合は変更しない）
    /// - Returns: 固定ワープカードを含む `Deck.Configuration`
    func configurationIncludingFixedWarpCard(weight: Int = 1, summarySuffix: String? = "＋固定ワープ") -> Deck.Configuration {
        configuration.addingFixedWarpCard(weight: weight, summarySuffix: summarySuffix)
    }
}

public struct GameMode: Equatable, Identifiable {
    /// 識別子。UI や永続化でも使用しやすいよう文字列 RawValue を採用する
    public enum Identifier: String, CaseIterable {
        case standard5x5
        case classicalChallenge
        case dailyFixedChallenge   // 日替わり固定シード用モード。Game Center の仮 ID から本番 ID へ差し替える想定
        case dailyRandomChallenge  // 日替わりランダムシード用モード。将来的に xcconfig で ID を設定予定
        case freeCustom
        case campaignStage
        case dailyFixed
        case dailyRandom
    }

    /// キャンペーン関連の補助情報
    /// - Note: `GameMode` がどのキャンペーンステージから生成されたかを識別するためのメタデータ
    public struct CampaignMetadata: Equatable {
        /// ひも付いたステージの ID
        public let stageID: CampaignStageID

        /// 公開イニシャライザ
        /// - Parameter stageID: 対象となるステージ ID
        public init(stageID: CampaignStageID) {
            self.stageID = stageID
        }
    }

    /// UI で利用する難易度ランク定義
    /// - Note: 文字列を個別に管理すると重複や表記揺れが発生しやすいため、列挙体で統一しておく
    public enum DifficultyRank: String, Codable {
        /// ルールが標準的で初学者にも勧めやすいモード
        case balanced
        /// 明確に難度が高く、熟練者向けのモード
        case advanced
        /// プレイヤーが自由に調整できるモード
        case custom
        /// キャンペーンなどシナリオ進行に応じて難度が変化するモード
        case scenario

        /// バッジ表示で利用する短いラベル
        /// - Returns: カード上に表示する 2〜3 文字の日本語表記
        public var badgeLabel: String {
            switch self {
            case .balanced:
                return "標準"
            case .advanced:
                return "高難度"
            case .custom:
                return "調整可"
            case .scenario:
                return "ステージ"
            }
        }

        /// アクセシビリティ向けの詳細説明
        /// - Returns: VoiceOver などで読み上げる文言
        public var accessibilityDescription: String {
            switch self {
            case .balanced:
                return "難易度は標準です"
            case .advanced:
                return "難易度は高難度です"
            case .custom:
                return "難易度はプレイヤーが調整できます"
            case .scenario:
                return "難易度はステージ進行に応じて変化します"
            }
        }
    }

    /// 初期スポーンの扱い
    public enum SpawnRule: Equatable, Codable {
        /// 固定座標へスポーン
        case fixed(GridPoint)
        /// プレイヤーが任意のマスを選択してスポーン
        case chooseAnyAfterPreview

        /// エンコード/デコードで利用するキー
        private enum CodingKeys: String, CodingKey {
            case type
            case point
        }

        /// ケース識別子
        private enum Kind: String, Codable {
            case fixed
            case chooseAnyAfterPreview
        }

        /// `Decodable` 準拠
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .type)
            switch kind {
            case .fixed:
                let point = try container.decode(GridPoint.self, forKey: .point)
                self = .fixed(point)
            case .chooseAnyAfterPreview:
                self = .chooseAnyAfterPreview
            }
        }

        /// `Encodable` 準拠
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .fixed(let point):
                try container.encode(Kind.fixed, forKey: .type)
                try container.encode(point, forKey: .point)
            case .chooseAnyAfterPreview:
                try container.encode(Kind.chooseAnyAfterPreview, forKey: .type)
            }
        }

        /// UI 表示用にルールの説明テキストを返す
        /// - Note: モード追加時に文字列を個別で管理しなくても済むよう、ここで共通化しておく
        public var summaryText: String {
            switch self {
            case .fixed:
                return "固定スポーン"
            case .chooseAnyAfterPreview:
                return "任意スポーン"
            }
        }

        /// Equatable のカスタム実装
        /// - Note: 固定座標スポーンは座標の一致を厳密に比較し、自由選択スポーンは同一ケースであれば常に等価とみなす。
        public static func == (lhs: SpawnRule, rhs: SpawnRule) -> Bool {
            switch (lhs, rhs) {
            case let (.fixed(lhsPoint), .fixed(rhsPoint)):
                // 固定座標スポーン同士は実際の GridPoint が一致するかどうかで判定する
                return lhsPoint == rhsPoint
            case (.chooseAnyAfterPreview, .chooseAnyAfterPreview):
                // 自由選択スポーン同士はケースが同じであれば同一の振る舞いになるため true を返す
                return true
            default:
                // それ以外の組み合わせはルールの性質が異なるため必ず false
                return false
            }
        }
    }

    /// ペナルティ関連のルールをまとめた設定構造体
    public struct PenaltySettings: Equatable, Codable {
        /// 手詰まり自動検出による引き直し時の加算手数
        public var deadlockPenaltyCost: Int
        /// プレイヤーが任意に引き直しを行った際の加算手数
        public var manualRedrawPenaltyCost: Int
        /// 任意の手札を 1 種類だけ捨て札にする際の加算手数
        public var manualDiscardPenaltyCost: Int
        /// 既踏マスに再訪した際の加算手数
        public var revisitPenaltyCost: Int

        /// メンバーごとに設定できるように明示的なイニシャライザを用意
        /// - Parameters:
        ///   - deadlockPenaltyCost: 自動ペナルティで加算する手数
        ///   - manualRedrawPenaltyCost: 手動ペナルティで加算する手数
        ///   - manualDiscardPenaltyCost: 手札 1 種類を捨て札にする際の手数
        ///   - revisitPenaltyCost: 再訪時のペナルティ手数
        public init(
            deadlockPenaltyCost: Int,
            manualRedrawPenaltyCost: Int,
            manualDiscardPenaltyCost: Int,
            revisitPenaltyCost: Int
        ) {
            self.deadlockPenaltyCost = deadlockPenaltyCost
            self.manualRedrawPenaltyCost = manualRedrawPenaltyCost
            self.manualDiscardPenaltyCost = manualDiscardPenaltyCost
            self.revisitPenaltyCost = revisitPenaltyCost
        }
    }

    /// ゲームモードの根幹となるレギュレーション設定
    /// - Note: 盤面サイズや山札構成、手札スロット数などを一括で扱い、新しいモードを追加しやすくする。
    public struct Regulation: Equatable, Codable {
        /// 盤面サイズ（N×N）
        public var boardSize: Int
        /// 初期手札スロット数（保持できるカード種類の上限を明示する）
        public var handSize: Int
        /// 先読み表示枚数
        public var nextPreviewCount: Int
        /// 同種カードをスタックできるかどうか
        public var allowsStacking: Bool
        /// 適用する山札構成プリセット
        public var deckPreset: GameDeckPreset
        /// 初期スポーンの扱い
        public var spawnRule: SpawnRule
        /// ペナルティ設定一式
        public var penalties: PenaltySettings
        /// マスごとの追加踏破回数設定
        public var additionalVisitRequirements: [GridPoint: Int] = [:]
        /// トグル挙動を適用するマス集合
        /// - Important: 同じ座標に `additionalVisitRequirements` が存在する場合はトグルが優先され、
        ///   ギミックとして 1 回踏むごとに踏破⇔未踏破が反転する。
        public var toggleTilePoints: Set<GridPoint> = []
        /// 完全に移動を禁止する障害物マス集合
        public var impassableTilePoints: Set<GridPoint> = []
        /// 盤面タイルへ付与する特殊効果一覧
        /// - Note: UI 演出とゲームロジックで同じデータを利用するため、`GridPoint` をキーに直接 `TileEffect` を割り当てる
        public var tileEffectOverrides: [GridPoint: TileEffect] = [:]
        /// ワープペアの定義（pairID ごとに 2 点以上の座標を列挙する）
        /// - Important: ここで指定した座標群から `TileEffect.warp` を自動生成し、片方向のみの登録ミスを防ぐ
        public var warpTilePairs: [String: [GridPoint]] = [:]
        /// 固定座標ワープカードで利用する目的地候補
        /// - Important: 盤外や障害物マスを事前に除外し、ゲーム中の `availableMoves` での防御的なチェックを補助する
        public private(set) var fixedWarpCardTargets: [MoveCard: [GridPoint]] = [:]

        /// レギュレーションを組み立てるためのイニシャライザ
        /// - Parameters:
        ///   - boardSize: 盤面サイズ
        ///   - handSize: 手札スロット数
        ///   - nextPreviewCount: 先読み表示枚数
        ///   - allowsStacking: 同種カードをスタックできるかどうか
        ///   - deckPreset: 使用する山札設定
        ///   - spawnRule: 初期スポーンルール
        ///   - penalties: ペナルティ設定
        public init(
            boardSize: Int,
            handSize: Int,
            nextPreviewCount: Int,
            allowsStacking: Bool,
            deckPreset: GameDeckPreset,
            spawnRule: SpawnRule,
            penalties: PenaltySettings,
            additionalVisitRequirements: [GridPoint: Int] = [:],
            toggleTilePoints: Set<GridPoint> = [],
            impassableTilePoints: Set<GridPoint> = [],
            tileEffectOverrides: [GridPoint: TileEffect] = [:],
            warpTilePairs: [String: [GridPoint]] = [:],
            fixedWarpCardTargets: [MoveCard: [GridPoint]] = [:]
        ) {
            self.boardSize = boardSize
            self.handSize = handSize
            self.nextPreviewCount = nextPreviewCount
            self.allowsStacking = allowsStacking
            self.deckPreset = deckPreset
            self.spawnRule = spawnRule
            self.penalties = penalties
            self.additionalVisitRequirements = additionalVisitRequirements
            self.toggleTilePoints = toggleTilePoints
            self.impassableTilePoints = impassableTilePoints
            self.tileEffectOverrides = tileEffectOverrides
            self.warpTilePairs = warpTilePairs
            self.fixedWarpCardTargets = Regulation.finalizeFixedWarpTargets(
                rawTargets: fixedWarpCardTargets,
                boardSize: boardSize,
                impassableTilePoints: impassableTilePoints,
                deckPreset: deckPreset
            )
        }

        /// 固定ワープカードの目的地を検証してから登録するヘルパー
        /// - Parameters:
        ///   - rawTargets: モード設定で宣言された元の座標集合
        ///   - boardSize: 対象盤面サイズ
        ///   - impassableTilePoints: 障害物として扱うマス集合
        /// - Returns: 盤外・障害物・重複を除去した安全な辞書
        private static func sanitizeFixedWarpTargets(
            _ rawTargets: [MoveCard: [GridPoint]],
            boardSize: Int,
            impassableTilePoints: Set<GridPoint>
        ) -> [MoveCard: [GridPoint]] {
            guard boardSize > 0, !rawTargets.isEmpty else { return [:] }

            let validRange = 0..<boardSize
            let isInsideBoard: (GridPoint) -> Bool = { point in
                validRange.contains(point.x) && validRange.contains(point.y)
            }

            var sanitized: [MoveCard: [GridPoint]] = [:]

            for (card, points) in rawTargets {
                guard !points.isEmpty else { continue }

                var filtered: [GridPoint] = []
                filtered.reserveCapacity(points.count)
                var seen: Set<GridPoint> = []

                for point in points {
                    // --- 盤外や障害物は候補から除外し、ゲーム中の安全確認負荷を減らす ---
                    guard isInsideBoard(point), !impassableTilePoints.contains(point) else { continue }
                    // --- 同一座標は 1 度だけ登録して意図しない重複を防ぐ ---
                    guard seen.insert(point).inserted else { continue }
                    filtered.append(point)
                }

                guard !filtered.isEmpty else { continue }
                sanitized[card] = filtered
            }

            return sanitized
        }

        /// 固定ワープカードの最終的な目的地リストを決定する
        /// - Parameters:
        ///   - rawTargets: モード設定で宣言されたターゲット一覧
        ///   - boardSize: 対象となる盤面サイズ
        ///   - impassableTilePoints: 障害物として扱うマス集合
        ///   - deckPreset: 利用する山札プリセット
        /// - Returns: バリデーション済みターゲット。未指定の場合は盤面全域から自動生成した候補を返す
        private static func finalizeFixedWarpTargets(
            rawTargets: [MoveCard: [GridPoint]],
            boardSize: Int,
            impassableTilePoints: Set<GridPoint>,
            deckPreset: GameDeckPreset
        ) -> [MoveCard: [GridPoint]] {
            // --- まずは明示的に指定されたターゲットをバリデーションし、問題がなければそのまま採用する ---
            let sanitized = sanitizeFixedWarpTargets(
                rawTargets,
                boardSize: boardSize,
                impassableTilePoints: impassableTilePoints
            )
            if !sanitized.isEmpty {
                return sanitized
            }

            // --- ワープカードを含むデッキでターゲット未指定の場合は、盤面全域から安全な候補を自動生成する ---
            let allowedMoves = deckPreset.configuration.allowedMoves
            guard allowedMoves.contains(.fixedWarp) else { return [:] }
            return defaultFixedWarpTargets(
                boardSize: boardSize,
                impassableTilePoints: impassableTilePoints
            )
        }

        /// 盤面全域から固定ワープカード用の目的地候補を生成する
        /// - Parameters:
        ///   - boardSize: 盤面の一辺サイズ
        ///   - impassableTilePoints: 障害物マス集合（候補から除外する）
        /// - Returns: 盤面内かつ移動可能な座標のみを含む辞書。候補が存在しない場合は空辞書を返す
        private static func defaultFixedWarpTargets(
            boardSize: Int,
            impassableTilePoints: Set<GridPoint>
        ) -> [MoveCard: [GridPoint]] {
            guard boardSize > 0 else { return [:] }

            // --- BoardGeometry を利用して盤面全座標を列挙し、障害物を除いた順序付きリストを生成する ---
            let allPoints = BoardGeometry.allPoints(for: boardSize)
            let traversablePoints = allPoints.filter { point in
                !impassableTilePoints.contains(point)
            }
            guard !traversablePoints.isEmpty else { return [:] }
            return [.fixedWarp: traversablePoints]
        }

        /// Codable 対応のためのキー定義
        private enum CodingKeys: String, CodingKey {
            case boardSize
            case handSize
            case nextPreviewCount
            case allowsStacking
            case deckPreset
            case spawnRule
            case penalties
            case additionalVisitRequirements
            case toggleTilePoints
            case impassableTilePoints
            case tileEffectOverrides
            case warpTilePairs
            case fixedWarpCardTargets
        }

        /// デコード処理（固定ワープ定義は一旦文字列キーとして受け取り、MoveCard へ変換する）
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            let decodedBoardSize = try container.decode(Int.self, forKey: .boardSize)
            let decodedHandSize = try container.decode(Int.self, forKey: .handSize)
            let decodedNextPreview = try container.decode(Int.self, forKey: .nextPreviewCount)
            let decodedAllowsStacking = try container.decode(Bool.self, forKey: .allowsStacking)
            let decodedDeckPreset = try container.decode(GameDeckPreset.self, forKey: .deckPreset)
            let decodedSpawnRule = try container.decode(SpawnRule.self, forKey: .spawnRule)
            let decodedPenalties = try container.decode(PenaltySettings.self, forKey: .penalties)
            let decodedAdditional = try container.decodeIfPresent([GridPoint: Int].self, forKey: .additionalVisitRequirements) ?? [:]
            let decodedToggle = try container.decodeIfPresent(Set<GridPoint>.self, forKey: .toggleTilePoints) ?? []
            let decodedImpassable = try container.decodeIfPresent(Set<GridPoint>.self, forKey: .impassableTilePoints) ?? []
            let decodedEffects = try container.decodeIfPresent([GridPoint: TileEffect].self, forKey: .tileEffectOverrides) ?? [:]
            let decodedWarpPairs = try container.decodeIfPresent([String: [GridPoint]].self, forKey: .warpTilePairs) ?? [:]
            let rawFixedWarpTargets = try container.decodeIfPresent([String: [GridPoint]].self, forKey: .fixedWarpCardTargets) ?? [:]

            let decodedTargets = Regulation.decodeFixedWarpTargets(from: rawFixedWarpTargets)
            let sanitizedTargets = Regulation.finalizeFixedWarpTargets(
                rawTargets: decodedTargets,
                boardSize: decodedBoardSize,
                impassableTilePoints: decodedImpassable,
                deckPreset: decodedDeckPreset
            )

            boardSize = decodedBoardSize
            handSize = decodedHandSize
            nextPreviewCount = decodedNextPreview
            allowsStacking = decodedAllowsStacking
            deckPreset = decodedDeckPreset
            spawnRule = decodedSpawnRule
            penalties = decodedPenalties
            additionalVisitRequirements = decodedAdditional
            toggleTilePoints = decodedToggle
            impassableTilePoints = decodedImpassable
            tileEffectOverrides = decodedEffects
            warpTilePairs = decodedWarpPairs
            fixedWarpCardTargets = sanitizedTargets
        }

        /// エンコード処理（固定ワープ定義は MoveCard のインデックスをキーに変換する）
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(boardSize, forKey: .boardSize)
            try container.encode(handSize, forKey: .handSize)
            try container.encode(nextPreviewCount, forKey: .nextPreviewCount)
            try container.encode(allowsStacking, forKey: .allowsStacking)
            try container.encode(deckPreset, forKey: .deckPreset)
            try container.encode(spawnRule, forKey: .spawnRule)
            try container.encode(penalties, forKey: .penalties)
            if !additionalVisitRequirements.isEmpty {
                try container.encode(additionalVisitRequirements, forKey: .additionalVisitRequirements)
            }
            if !toggleTilePoints.isEmpty {
                try container.encode(toggleTilePoints, forKey: .toggleTilePoints)
            }
            if !impassableTilePoints.isEmpty {
                try container.encode(impassableTilePoints, forKey: .impassableTilePoints)
            }
            if !tileEffectOverrides.isEmpty {
                try container.encode(tileEffectOverrides, forKey: .tileEffectOverrides)
            }
            if !warpTilePairs.isEmpty {
                try container.encode(warpTilePairs, forKey: .warpTilePairs)
            }
            let encodedTargets = Regulation.encodeFixedWarpTargets(fixedWarpCardTargets)
            if !encodedTargets.isEmpty {
                try container.encode(encodedTargets, forKey: .fixedWarpCardTargets)
            }
        }

        /// エンコード用に MoveCard を安定キーへ変換する
        /// - Parameter targets: 変換対象の辞書
        /// - Returns: MoveCard のインデックスを文字列化したキーを持つ辞書
        private static func encodeFixedWarpTargets(_ targets: [MoveCard: [GridPoint]]) -> [String: [GridPoint]] {
            guard !targets.isEmpty else { return [:] }
            var encoded: [String: [GridPoint]] = [:]
            for (card, points) in targets {
                guard let index = MoveCard.allCases.firstIndex(of: card) else { continue }
                encoded[String(index)] = points
            }
            return encoded
        }

        /// デコード時に MoveCard のインデックスへ戻す
        /// - Parameter raw: 文字列キーで受け取った辞書
        /// - Returns: MoveCard をキーにした辞書
        private static func decodeFixedWarpTargets(from raw: [String: [GridPoint]]) -> [MoveCard: [GridPoint]] {
            guard !raw.isEmpty else { return [:] }
            var decoded: [MoveCard: [GridPoint]] = [:]
            for (key, points) in raw {
                guard let index = Int(key), MoveCard.allCases.indices.contains(index) else { continue }
                let card = MoveCard.allCases[index]
                decoded[card] = points
            }
            return decoded
        }
    }

    /// 一意な識別子
    public let identifier: Identifier
    /// 表示名（タイトル画面などで利用）
    public let displayName: String
    /// レギュレーション設定一式
    private let regulation: Regulation
    /// リーダーボードへスコアを送信するかどうか
    private let leaderboardEligible: Bool
    /// キャンペーンステージ情報（該当しない場合は nil）
    private let campaignMetadata: CampaignMetadata?
    /// 乱数シード（決定論的な山札を構築したい場合に利用）
    public let deckSeed: UInt64?

    /// `Identifiable` 準拠用
    public var id: Identifier { identifier }

    /// メンバーをまとめて設定するためのプライベートイニシャライザ
    /// - Parameters:
    ///   - identifier: モードを識別するための ID
    ///   - displayName: UI で表示する名称
    ///   - regulation: 盤面やペナルティを含むレギュレーション設定
    public init(
        identifier: Identifier,
        displayName: String,
        regulation: Regulation,
        leaderboardEligible: Bool = true,
        campaignMetadata: CampaignMetadata? = nil,
        deckSeed: UInt64? = nil
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.regulation = regulation
        self.leaderboardEligible = leaderboardEligible
        self.campaignMetadata = campaignMetadata
        self.deckSeed = deckSeed
    }

    /// 盤面サイズ（N×N）
    public var boardSize: Int { regulation.boardSize }
    /// 手札スロット数（保持できるカード種類の上限を明示する）
    /// - Note: ここでいう手札サイズは枚数ではなく「異なるカードの種類数」を指す。
    public var handSize: Int { regulation.handSize }
    /// 先読み表示枚数
    public var nextPreviewCount: Int { regulation.nextPreviewCount }
    /// スポーンルール
    public var spawnRule: SpawnRule { regulation.spawnRule }
    /// ペナルティ設定一式
    var penalties: PenaltySettings { regulation.penalties }
    /// 自動ペナルティ（手詰まり引き直し）で加算する手数
    public var deadlockPenaltyCost: Int { penalties.deadlockPenaltyCost }
    /// 手動ペナルティで加算する手数
    public var manualRedrawPenaltyCost: Int { penalties.manualRedrawPenaltyCost }
    /// 捨て札ペナルティで加算する手数
    public var manualDiscardPenaltyCost: Int { penalties.manualDiscardPenaltyCost }
    /// 既踏マスへ再訪した際に加算する手数
    public var revisitPenaltyCost: Int { penalties.revisitPenaltyCost }
    /// 同種カードをスタックできるかどうか
    public var allowsCardStacking: Bool { regulation.allowsStacking }
    /// 山札構成設定（ゲームモジュール内部で使用）
    var deckConfiguration: Deck.Configuration { regulation.deckPreset.configuration }
    /// 利用中の山札プリセット
    public var deckPreset: GameDeckPreset { regulation.deckPreset }
    /// UI で表示する山札の要約
    public var deckSummaryText: String { regulation.deckPreset.summaryText }
    /// UI 表示用のアイコン名
    /// - Note: SF Symbols のシステム名を返し、SwiftUI から共通の描画を行えるようにする
    public var iconSystemName: String {
        switch identifier {
        case .standard5x5:
            return "square.grid.3x3.fill"
        case .classicalChallenge:
            return "checkerboard.rectangle"
        case .dailyFixedChallenge:
            return "calendar"
        case .dailyRandomChallenge:
            return "sparkles"
        case .freeCustom:
            return "slider.horizontal.3"
        case .campaignStage:
            return "map.fill"
        case .dailyFixed:
            return "calendar"
        case .dailyRandom:
            return "sparkles"
        }
    }
    /// モードの難易度ランク
    /// - Note: UI 側でバッジ表示やアクセシビリティ説明に利用する
    public var difficultyRank: DifficultyRank {
        switch identifier {
        case .standard5x5:
            return .balanced
        case .classicalChallenge:
            return .advanced
        case .dailyFixedChallenge:
            return .balanced
        case .dailyRandomChallenge:
            return .advanced
        case .freeCustom:
            return .custom
        case .campaignStage:
            return .scenario
        case .dailyFixed:
            return .advanced
        case .dailyRandom:
            return .custom
        }
    }
    /// 難易度バッジで利用する短縮ラベル
    public var difficultyBadgeLabel: String { difficultyRank.badgeLabel }
    /// 難易度に関するアクセシビリティ説明
    public var difficultyAccessibilityDescription: String { difficultyRank.accessibilityDescription }
    /// 手札スロットと先読み枚数をまとめた説明文
    /// - Note: 同種カードを重ねられるスタック仕様を把握しやすいよう「種類数」で表現する。
    public var handSummaryText: String {
        let stacking = allowsCardStacking ? "スタック可" : "スタック不可"
        return "手札スロット \(handSize) 種類 ・ 先読み \(nextPreviewCount) 枚 ・ \(stacking)"
    }
    /// 手動ペナルティの説明文
    public var manualPenaltySummaryText: String {
        let redrawText = "引き直し +\(manualRedrawPenaltyCost)"
        let discardText: String
        if manualDiscardPenaltyCost > 0 {
            discardText = "捨て札 +\(manualDiscardPenaltyCost)"
        } else {
            discardText = "捨て札 ペナルティなし"
        }
        return "\(redrawText) / \(discardText)"
    }
    /// 再訪ペナルティの説明文
    public var revisitPenaltySummaryText: String {
        if revisitPenaltyCost > 0 {
            return "再訪 +\(revisitPenaltyCost)"
        } else {
            return "再訪ペナルティなし"
        }
    }
    /// 盤面サイズ・スポーン・山札をまとめた要約文
    public var primarySummaryText: String {
        "\(boardSize)×\(boardSize) ・ \(spawnRule.summaryText) ・ \(deckSummaryText)"
    }
    /// 手札・先読み・ペナルティ情報をまとめた詳細文
    public var secondarySummaryText: String {
        "\(handSummaryText) / \(manualPenaltySummaryText) / \(revisitPenaltySummaryText)"
    }

    /// リーダーボードへスコアを送信する対象かどうか
    public var isLeaderboardEligible: Bool { leaderboardEligible }

    /// キャンペーンステージから生成されたモードかどうか
    public var isCampaignStage: Bool { campaignMetadata != nil }

    /// キャンペーンに紐付くメタデータのスナップショット
    public var campaignMetadataSnapshot: CampaignMetadata? { campaignMetadata }

    /// スタック仕様の詳細説明文
    public var stackingRuleDetailText: String {
        if allowsCardStacking {
            return "同じ種類のカードは同じスロット内で重なり、空きスロットがなくても補充できます。"
        } else {
            return "同じ種類のカードは別スロットを占有し、空きスロットが無いと新しいカードを引けません。"
        }
    }

    /// 現在のレギュレーションをそのまま取得するためのスナップショット
    public var regulationSnapshot: Regulation { regulation }

    /// スポーン選択が必要かどうか
    public var requiresSpawnSelection: Bool {
        if case .chooseAnyAfterPreview = spawnRule { return true }
        return false
    }

    /// 初期位置（固定スポーンの場合のみ）
    public var initialSpawnPoint: GridPoint? {
        switch spawnRule {
        case .fixed(let point):
            return point
        case .chooseAnyAfterPreview:
            return nil
        }
    }

    /// 初期状態で踏破済みにしておくマス集合
    public var initialVisitedPoints: [GridPoint] {
        switch spawnRule {
        case .fixed(let point):
            return [point]
        case .chooseAnyAfterPreview:
            return []
        }
    }

    /// 追加踏破回数が必要なマス集合
    public var additionalVisitRequirements: [GridPoint: Int] { regulation.additionalVisitRequirements }
    /// トグル挙動を割り当てたマス集合
    public var toggleTilePoints: Set<GridPoint> { regulation.toggleTilePoints }
    /// 障害物として扱う移動不可マス集合
    public var impassableTilePoints: Set<GridPoint> { regulation.impassableTilePoints }
    /// ワープ定義のスナップショット
    public var warpTilePairs: [String: [GridPoint]] { regulation.warpTilePairs }
    /// 任意に上書きしたタイル効果一覧
    public var tileEffectOverrides: [GridPoint: TileEffect] { regulation.tileEffectOverrides }
    /// 固定ワープカード用の目的地辞書
    public var fixedWarpCardTargets: [MoveCard: [GridPoint]] { regulation.fixedWarpCardTargets }
    /// 固定ワープカードが利用する目的地集合（Deck で順番に割り当てる）
    /// - Note: `.fixedWarp` キーに対応する座標リストのみを公開し、カード配布時のメタデータとして活用する
    public var fixedWarpDestinationPool: [GridPoint] {
        regulation.fixedWarpCardTargets[.fixedWarp] ?? []
    }

    /// 盤面へ適用するタイル効果を合成して返す
    /// - Important: ワープ定義は自動的に `TileEffect.warp` へ展開し、個別指定された効果より優先度は低い（手動指定があればそちらを採用）
    public var tileEffects: [GridPoint: TileEffect] {
        var effects = regulation.tileEffectOverrides
        for (pairID, points) in regulation.warpTilePairs {
            guard points.count >= 2 else { continue }
            var uniquePoints: [GridPoint] = []
            var seen: Set<GridPoint> = []
            for point in points where seen.insert(point).inserted {
                uniquePoints.append(point)
            }
            guard uniquePoints.count >= 2 else { continue }
            for (index, point) in uniquePoints.enumerated() {
                guard effects[point] == nil else { continue }
                let destination = uniquePoints[(index + 1) % uniquePoints.count]
                effects[point] = .warp(pairID: pairID, destination: destination)
            }
        }
        return effects
    }

    /// スタンダードモード（既存仕様）
    public static var standard: GameMode {
        GameMode(identifier: .standard5x5, displayName: "スタンダード", regulation: buildStandardRegulation())
    }

    /// クラシカルチャレンジモード
    public static var classicalChallenge: GameMode {
        GameMode(identifier: .classicalChallenge, displayName: "クラシカルチャレンジ", regulation: buildClassicalChallengeRegulation())
    }

    /// ビルトインで用意しているモードの一覧
    public static var builtInModes: [GameMode] { [standard, classicalChallenge] }

    /// 識別子から対応するモード定義を取り出すヘルパー
    /// - Parameter identifier: 利用したいモードの識別子
    /// - Returns: `identifier` に対応する `GameMode`
    public static func mode(for identifier: Identifier) -> GameMode {
        switch identifier {
        case .standard5x5:
            return standard
        case .classicalChallenge:
            return classicalChallenge
        case .dailyFixedChallenge:
            // 日替わり固定シードは現状ビルトイン定義が存在しないため、スタンダード相当をフォールバックとして返す
            return standard
        case .dailyRandomChallenge:
            // 日替わりランダムシードも同様に将来的な実装を想定し、暫定的にスタンダードを返しておく
            return standard
        case .freeCustom:
            // フリーモードはユーザー設定によって変化するため、デフォルトとしてスタンダード相当を返す
            return standard
        case .campaignStage:
            // キャンペーン専用モードは `CampaignStage` から生成されるため、ここではスタンダードをフォールバックとして返す
            return standard
        case .dailyFixed, .dailyRandom:
            // 日替わりモードは日付とシードから別途生成されるため、ここでは安全側としてスタンダードを返す
            return standard
        }
    }

    /// Equatable 準拠。識別子が一致すれば同一モードとみなす
    public static func == (lhs: GameMode, rhs: GameMode) -> Bool {
        guard lhs.identifier == rhs.identifier else { return false }
        guard lhs.campaignMetadata == rhs.campaignMetadata else { return false }
        guard lhs.deckSeed == rhs.deckSeed else { return false }
        if lhs.requiresRegulationComparison {
            return lhs.regulation == rhs.regulation
        }
        return true
    }

    /// レギュレーション比較が必要な識別子かどうかをまとめたヘルパー
    private var requiresRegulationComparison: Bool {
        switch identifier {
        case .freeCustom, .campaignStage, .dailyFixed, .dailyRandom, .dailyFixedChallenge, .dailyRandomChallenge:
            return true
        case .standard5x5, .classicalChallenge:
            return false
        }
    }

    /// スタンダードモードの定義を生成する
    private static func buildStandardRegulation() -> Regulation {
        Regulation(
            boardSize: BoardGeometry.standardSize,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standard,
            // BoardGeometry を利用して中央座標を求めることで、盤面サイズが変わった場合の修正箇所を 1 箇所に抑える
            spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: BoardGeometry.standardSize)),
            penalties: PenaltySettings(
                // スタンダードモードの基準ペナルティは手詰まり 3／手動引き直し 2／捨て札 1／再訪問 0 に統一する
                deadlockPenaltyCost: 3,
                manualRedrawPenaltyCost: 2,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 0
            )
        )
    }

    /// クラシカルチャレンジモードの定義を生成する
    private static func buildClassicalChallengeRegulation() -> Regulation {
        Regulation(
            boardSize: 8,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .classicalChallenge,
            spawnRule: .chooseAnyAfterPreview,
            penalties: PenaltySettings(
                deadlockPenaltyCost: 2,
                manualRedrawPenaltyCost: 2,
                manualDiscardPenaltyCost: 1,
                revisitPenaltyCost: 1
            )
        )
    }
}
