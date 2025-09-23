import Foundation

/// ゲームルール一式をまとめたモード設定
/// - Note: 盤サイズや山札構成、ペナルティ量などをまとめて扱うことで、新モード追加時の分岐を最小限に抑える。
/// 山札プリセットを識別し、UI からも扱いやすいように公開する列挙体
/// - Note: それぞれのケースは `Deck.Configuration` へ変換可能で、表示名や概要テキストも併せて提供する
public enum GameDeckPreset: String, CaseIterable, Codable, Identifiable {
    /// スタンダードモードと同じ山札構成
    case standard
    /// クラシカルチャレンジと同じ桂馬のみの構成
    case classicalChallenge

    /// `Identifiable` 準拠用の ID
    public var id: String { rawValue }

    /// UI で表示する名称
    public var displayName: String {
        switch self {
        case .standard:
            return "スタンダード構成"
        case .classicalChallenge:
            return "クラシカル構成"
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
        case .classicalChallenge:
            return .classicalChallenge
        }
    }
}

public struct GameMode: Equatable, Identifiable {
    /// 識別子。UI や永続化でも使用しやすいよう文字列 RawValue を採用する
    public enum Identifier: String, CaseIterable {
        case standard5x5
        case classicalChallenge
        case freeCustom
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
            penalties: PenaltySettings
        ) {
            self.boardSize = boardSize
            self.handSize = handSize
            self.nextPreviewCount = nextPreviewCount
            self.allowsStacking = allowsStacking
            self.deckPreset = deckPreset
            self.spawnRule = spawnRule
            self.penalties = penalties
        }
    }

    /// 一意な識別子
    public let identifier: Identifier
    /// 表示名（タイトル画面などで利用）
    public let displayName: String
    /// レギュレーション設定一式
    private let regulation: Regulation

    /// `Identifiable` 準拠用
    public var id: Identifier { identifier }

    /// メンバーをまとめて設定するためのプライベートイニシャライザ
    /// - Parameters:
    ///   - identifier: モードを識別するための ID
    ///   - displayName: UI で表示する名称
    ///   - regulation: 盤面やペナルティを含むレギュレーション設定
    public init(identifier: Identifier, displayName: String, regulation: Regulation) {
        self.identifier = identifier
        self.displayName = displayName
        self.regulation = regulation
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
        }
    }

    /// Equatable 準拠。識別子が一致すれば同一モードとみなす
    public static func == (lhs: GameMode, rhs: GameMode) -> Bool {
        guard lhs.identifier == rhs.identifier else { return false }
        if lhs.identifier == .freeCustom {
            return lhs.regulation == rhs.regulation
        }
        return true
    }

    /// スタンダードモードの定義を生成する
    private static func buildStandardRegulation() -> Regulation {
        Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standard,
            spawnRule: .fixed(GridPoint.center(of: 5)),
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
