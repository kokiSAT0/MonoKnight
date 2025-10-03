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
    /// 標準デッキに上下左右の選択キングを加えた構成
    case standardWithOrthogonalChoices
    /// 標準デッキに斜め選択キングを加えた構成
    case standardWithDiagonalChoices
    /// 標準デッキに桂馬の選択カードを加えた構成
    case standardWithKnightChoices
    /// 標準デッキにすべての選択カードを加えた構成
    case standardWithAllChoices
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
        case .standardWithOrthogonalChoices:
            return "標準＋縦横選択キング構成"
        case .standardWithDiagonalChoices:
            return "標準＋斜め選択キング構成"
        case .standardWithKnightChoices:
            return "標準＋桂馬選択構成"
        case .standardWithAllChoices:
            return "標準＋全選択カード構成"
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
        case .standardWithOrthogonalChoices:
            return .standardWithOrthogonalChoices
        case .standardWithDiagonalChoices:
            return .standardWithDiagonalChoices
        case .standardWithKnightChoices:
            return .standardWithKnightChoices
        case .standardWithAllChoices:
            return .standardWithAllChoices
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
}

public struct GameMode: Equatable, Identifiable {
    /// 識別子。UI や永続化でも使用しやすいよう文字列 RawValue を採用する
    public enum Identifier: String, CaseIterable {
        case standard5x5
        case classicalChallenge
        case freeCustom
        case campaignStage
        case dailyChallenge
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
            impassableTilePoints: Set<GridPoint> = []
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
        campaignMetadata: CampaignMetadata? = nil
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.regulation = regulation
        self.leaderboardEligible = leaderboardEligible
        self.campaignMetadata = campaignMetadata
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
        case .freeCustom:
            return "slider.horizontal.3"
        case .campaignStage:
            return "map.fill"
        case .dailyChallenge:
            return "calendar"
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
        case .freeCustom:
            return .custom
        case .campaignStage:
            return .scenario
        case .dailyChallenge:
            return .balanced
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
        case .freeCustom:
            // フリーモードはユーザー設定によって変化するため、デフォルトとしてスタンダード相当を返す
            return standard
        case .campaignStage:
            // キャンペーン専用モードは `CampaignStage` から生成されるため、ここではスタンダードをフォールバックとして返す
            return standard
        case .dailyChallenge:
            return standard
        }
    }

    /// Equatable 準拠。識別子が一致すれば同一モードとみなす
    public static func == (lhs: GameMode, rhs: GameMode) -> Bool {
        guard lhs.identifier == rhs.identifier else { return false }
        guard lhs.campaignMetadata == rhs.campaignMetadata else { return false }
        if lhs.identifier == .freeCustom || lhs.identifier == .campaignStage {
            return lhs.regulation == rhs.regulation
        }
        return true
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
                deadlockPenaltyCost: 5,
                manualRedrawPenaltyCost: 5,
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
