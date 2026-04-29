import Foundation

public struct GameMode: Equatable, Identifiable {
    /// 識別子。UI や永続化でも使用しやすいよう文字列 RawValue を採用する
    public enum Identifier: String, CaseIterable {
        case standard5x5
        case classicalChallenge
        case targetLab
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
        /// 従来通り、踏破対象マスをすべて踏むとクリア
        case boardClear
        /// 目的地を指定数獲得するとクリア
        case targetCollection(goalCount: Int)

        private enum CodingKeys: String, CodingKey {
            case type
            case goalCount
        }

        private enum Kind: String, Codable {
            case boardClear
            case targetCollection
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let kind = try container.decode(Kind.self, forKey: .type)
            switch kind {
            case .boardClear:
                self = .boardClear
            case .targetCollection:
                let goalCount = try container.decode(Int.self, forKey: .goalCount)
                self = .targetCollection(goalCount: goalCount)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .boardClear:
                try container.encode(Kind.boardClear, forKey: .type)
            case .targetCollection(let goalCount):
                try container.encode(Kind.targetCollection, forKey: .type)
                try container.encode(goalCount, forKey: .goalCount)
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
        public internal(set) var fixedWarpCardTargets: [MoveCard: [GridPoint]] = [:]
        /// クリア条件
        public var completionRule: CompletionRule
        /// 実験場用のカード・特殊マス有効設定
        public var targetLabExperimentSettings: TargetLabExperimentSettings?

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
            fixedWarpCardTargets: [MoveCard: [GridPoint]] = [:],
            completionRule: CompletionRule = .boardClear,
            targetLabExperimentSettings: TargetLabExperimentSettings? = nil
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
            if targetLabExperimentSettings?.enabledCardGroups.contains(.warp) == false {
                self.fixedWarpCardTargets = [:]
            }
            self.completionRule = completionRule
            self.targetLabExperimentSettings = targetLabExperimentSettings
        }

        /// Codable 対応のためのキー定義
        enum CodingKeys: String, CodingKey {
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
            case completionRule
            case targetLabExperimentSettings
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
    var deckConfiguration: Deck.Configuration {
        if regulation.deckPreset == .targetLabAllIn,
           let settings = regulation.targetLabExperimentSettings {
            return regulation.deckPreset.configuration.filteringTargetLabCards(for: settings)
        }
        return regulation.deckPreset.configuration
    }
    /// 利用中の山札プリセット
    public var deckPreset: GameDeckPreset { regulation.deckPreset }
    /// UI で表示する山札の要約
    public var deckSummaryText: String { regulation.deckPreset.summaryText }
    /// クリア条件
    public var completionRule: CompletionRule { regulation.completionRule }
    /// 目的地制モードかどうか
    public var usesTargetCollection: Bool {
        if case .targetCollection = regulation.completionRule { return true }
        return false
    }
    /// 目的地制モードの目標獲得数
    public var targetGoalCount: Int {
        if case .targetCollection(let goalCount) = regulation.completionRule {
            return max(goalCount, 1)
        }
        return 0
    }

    /// リーダーボードへスコアを送信する対象かどうか
    public var isLeaderboardEligible: Bool { leaderboardEligible }

    /// キャンペーンステージから生成されたモードかどうか
    public var isCampaignStage: Bool { campaignMetadata != nil }

    /// キャンペーンに紐付くメタデータのスナップショット
    public var campaignMetadataSnapshot: CampaignMetadata? { campaignMetadata }

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
        case .standard5x5, .classicalChallenge, .targetLab:
            return false
        }
    }
}
