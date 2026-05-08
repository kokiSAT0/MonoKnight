import Foundation

public struct GameMode: Equatable, Identifiable {
    /// 識別子。UI や永続化でも使用しやすいよう文字列 RawValue を採用する
    public enum Identifier: String, CaseIterable {
        case dungeonFloor
    }

    /// 塔ダンジョン関連の補助情報
    /// - Note: UI が選択元のダンジョンとフロアを参照するための軽量なメタデータ。
    public struct DungeonMetadata: Equatable {
        public let dungeonID: String
        public let floorID: String
        public let runState: DungeonRunState?

        public init(
            dungeonID: String,
            floorID: String,
            runState: DungeonRunState? = nil
        ) {
            self.dungeonID = dungeonID
            self.floorID = floorID
            self.runState = runState
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

    /// ゲームの完了条件を表す設定
    public enum CompletionRule: Equatable, Codable {
        /// 指定出口マスへ到達するとクリア
        case dungeonExit(exitPoint: GridPoint)

        private enum CodingKeys: String, CodingKey {
            case type
            case exitPoint
        }

        private enum Kind: String, Codable {
            case dungeonExit
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .type)
            switch kind {
            case .dungeonExit:
                let exitPoint = try container.decode(GridPoint.self, forKey: .exitPoint)
                self = .dungeonExit(exitPoint: exitPoint)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .dungeonExit(let exitPoint):
                try container.encode(Kind.dungeonExit, forKey: .type)
                try container.encode(exitPoint, forKey: .exitPoint)
            }
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
        /// ラン中報酬などで一時的に山札へ加える移動カード
        public var bonusMoveCards: [MoveCard]?
        /// 初期スポーンの扱い
        public var spawnRule: SpawnRule
        /// ペナルティ設定一式
        public var penalties: PenaltySettings
        /// 完全に移動を禁止する障害物マス集合
        public var impassableTilePoints: Set<GridPoint> = []
        /// 盤面タイルへ付与する特殊効果一覧
        /// - Note: UI 演出とゲームロジックで同じデータを利用するため、`GridPoint` をキーに直接 `TileEffect` を割り当てる
        public var tileEffectOverrides: [GridPoint: TileEffect] = [:]
        /// ワープペアの定義（pairID ごとに 2 点以上の座標を列挙する）
        /// - Important: ここで指定した座標群から `TileEffect.warp` を自動生成し、片方向のみの登録ミスを防ぐ
        public var warpTilePairs: [String: [GridPoint]] = [:]
        /// クリア条件
        public var completionRule: CompletionRule
        /// 塔ダンジョン用の追加ルール。出口到達型以外では nil を基本とする
        public var dungeonRules: DungeonRules?

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
            bonusMoveCards: [MoveCard] = [],
            spawnRule: SpawnRule,
            penalties: PenaltySettings,
            impassableTilePoints: Set<GridPoint> = [],
            tileEffectOverrides: [GridPoint: TileEffect] = [:],
            warpTilePairs: [String: [GridPoint]] = [:],
            completionRule: CompletionRule = .dungeonExit(exitPoint: BoardGeometry.defaultSpawnPoint(for: BoardGeometry.standardSize)),
            dungeonRules: DungeonRules? = nil
        ) {
            self.boardSize = boardSize
            self.handSize = handSize
            self.nextPreviewCount = nextPreviewCount
            self.allowsStacking = allowsStacking
            self.deckPreset = deckPreset
            self.bonusMoveCards = bonusMoveCards.isEmpty ? nil : bonusMoveCards
            self.spawnRule = spawnRule
            self.penalties = penalties
            self.impassableTilePoints = impassableTilePoints
            self.tileEffectOverrides = tileEffectOverrides
            self.warpTilePairs = warpTilePairs
            self.completionRule = completionRule
            self.dungeonRules = dungeonRules
        }

        /// Codable 対応のためのキー定義
        enum CodingKeys: String, CodingKey {
            case boardSize
            case handSize
            case nextPreviewCount
            case allowsStacking
            case deckPreset
            case bonusMoveCards
            case spawnRule
            case penalties
            case impassableTilePoints
            case tileEffectOverrides
            case warpTilePairs
            case completionRule
            case dungeonRules
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
    /// 塔ダンジョン情報（該当しない場合は nil）
    private let dungeonMetadata: DungeonMetadata?
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
        leaderboardEligible: Bool = false,
        dungeonMetadata: DungeonMetadata? = nil,
        deckSeed: UInt64? = nil
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.regulation = regulation
        self.leaderboardEligible = leaderboardEligible
        self.dungeonMetadata = dungeonMetadata
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
    var deckConfiguration: Deck.Configuration {
        let bonusMoveCards = regulation.bonusMoveCards ?? []
        return regulation.deckPreset.configuration.addingBonusMoveCards(bonusMoveCards)
    }
    /// 利用中の山札プリセット
    public var deckPreset: GameDeckPreset { regulation.deckPreset }
    /// ラン中報酬などで一時的に山札へ加わった移動カード
    public var bonusMoveCards: [MoveCard] { regulation.bonusMoveCards ?? [] }
    /// UI で表示する山札の要約
    public var deckSummaryText: String { deckConfiguration.deckSummaryText }
    /// クリア条件
    public var completionRule: CompletionRule { regulation.completionRule }
    /// 出口到達型ダンジョンモードかどうか
    public var usesDungeonExit: Bool {
        if case .dungeonExit = regulation.completionRule { return true }
        return false
    }
    /// 出口到達型ダンジョンの出口マス
    public var dungeonExitPoint: GridPoint? {
        if case .dungeonExit(let exitPoint) = regulation.completionRule {
            return exitPoint
        }
        return nil
    }
    /// 出口到達型ダンジョンの追加ルール
    public var dungeonRules: DungeonRules? { regulation.dungeonRules }

    /// リーダーボードへスコアを送信する対象かどうか
    public var isLeaderboardEligible: Bool { leaderboardEligible }

    /// 塔ダンジョンに紐付くメタデータのスナップショット
    public var dungeonMetadataSnapshot: DungeonMetadata? { dungeonMetadata }

    /// 塔ダンジョンのフロアとして扱うモードかどうか
    public var isDungeonFloor: Bool { usesDungeonExit }

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

    /// 障害物として扱う移動不可マス集合
    public var impassableTilePoints: Set<GridPoint> { regulation.impassableTilePoints }
    /// ワープ定義のスナップショット
    public var warpTilePairs: [String: [GridPoint]] { regulation.warpTilePairs }
    /// 任意に上書きしたタイル効果一覧
    public var tileEffectOverrides: [GridPoint: TileEffect] { regulation.tileEffectOverrides }
    /// Equatable 準拠。識別子が一致すれば同一モードとみなす
    public static func == (lhs: GameMode, rhs: GameMode) -> Bool {
        guard lhs.identifier == rhs.identifier else { return false }
        guard lhs.dungeonMetadata == rhs.dungeonMetadata else { return false }
        guard lhs.deckSeed == rhs.deckSeed else { return false }
        if lhs.requiresRegulationComparison {
            return lhs.regulation == rhs.regulation
        }
        return true
    }

    /// レギュレーション比較が必要な識別子かどうかをまとめたヘルパー
    private var requiresRegulationComparison: Bool {
        true
    }
}
