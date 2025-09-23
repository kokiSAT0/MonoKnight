import Foundation

/// ゲームルール一式をまとめたモード設定
/// - Note: 盤サイズや山札構成、ペナルティ量などをまとめて扱うことで、新モード追加時の分岐を最小限に抑える。
public struct GameMode: Equatable, Identifiable {
    /// 識別子。UI や永続化でも使用しやすいよう文字列 RawValue を採用する
    public enum Identifier: String, CaseIterable {
        case standard5x5
        case classicalChallenge
    }

    /// 初期スポーンの扱い
    public enum SpawnRule: Equatable {
        /// 固定座標へスポーン
        case fixed(GridPoint)
        /// プレイヤーが任意のマスを選択してスポーン
        case chooseAnyAfterPreview

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
    struct PenaltySettings {
        /// 手詰まり自動検出による引き直し時の加算手数
        let deadlockPenaltyCost: Int
        /// プレイヤーが任意に引き直しを行った際の加算手数
        let manualRedrawPenaltyCost: Int
        /// 既踏マスに再訪した際の加算手数
        let revisitPenaltyCost: Int

        /// メンバーごとに設定できるように明示的なイニシャライザを用意
        /// - Parameters:
        ///   - deadlockPenaltyCost: 自動ペナルティで加算する手数
        ///   - manualRedrawPenaltyCost: 手動ペナルティで加算する手数
        ///   - revisitPenaltyCost: 再訪時のペナルティ手数
        init(
            deadlockPenaltyCost: Int,
            manualRedrawPenaltyCost: Int,
            revisitPenaltyCost: Int
        ) {
            self.deadlockPenaltyCost = deadlockPenaltyCost
            self.manualRedrawPenaltyCost = manualRedrawPenaltyCost
            self.revisitPenaltyCost = revisitPenaltyCost
        }
    }

    /// ゲームモードの根幹となるレギュレーション設定
    /// - Note: 盤面サイズや山札構成、手札枚数などを一括で扱い、新しいモードを追加しやすくする。
    struct Regulation {
        /// 盤面サイズ（N×N）
        let boardSize: Int
        /// 手札スロット数（同時に保持できるカード種類数）
        let handSize: Int
        /// 先読み表示枚数
        let nextPreviewCount: Int
        /// 適用する山札構成
        let deckConfiguration: Deck.Configuration
        /// 初期スポーンの扱い
        let spawnRule: SpawnRule
        /// ペナルティ設定一式
        let penalties: PenaltySettings

        /// レギュレーションを組み立てるためのイニシャライザ
        /// - Parameters:
        ///   - boardSize: 盤面サイズ
        ///   - handSize: 手札枚数
        ///   - nextPreviewCount: 先読み表示枚数
        ///   - deckConfiguration: 使用する山札設定
        ///   - spawnRule: 初期スポーンルール
        ///   - penalties: ペナルティ設定
        init(
            boardSize: Int,
            handSize: Int,
            nextPreviewCount: Int,
            deckConfiguration: Deck.Configuration,
            spawnRule: SpawnRule,
            penalties: PenaltySettings
        ) {
            self.boardSize = boardSize
            self.handSize = handSize
            self.nextPreviewCount = nextPreviewCount
            self.deckConfiguration = deckConfiguration
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
    init(identifier: Identifier, displayName: String, regulation: Regulation) {
        self.identifier = identifier
        self.displayName = displayName
        self.regulation = regulation
    }

    /// 盤面サイズ（N×N）
    public var boardSize: Int { regulation.boardSize }
    /// 手札スロット数（同時に保持できるカード種類数）
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
    /// 既踏マスへ再訪した際に加算する手数
    public var revisitPenaltyCost: Int { penalties.revisitPenaltyCost }
    /// 山札構成設定（ゲームモジュール内部で使用）
    var deckConfiguration: Deck.Configuration { regulation.deckConfiguration }
    /// UI で表示する山札の要約
    public var deckSummaryText: String { regulation.deckConfiguration.deckSummaryText }
    /// 手札と先読み枚数をまとめた説明文
    public var handSummaryText: String {
        "手札 \(handSize) 種類 / 先読み \(nextPreviewCount) 枚"
    }
    /// 手動ペナルティの説明文
    public var manualPenaltySummaryText: String {
        "引き直し +\(manualRedrawPenaltyCost)"
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

    /// モード識別子と定義を結び付けたレジストリ
    /// - Note: 新しいモードを追加する際は `buildXXXMode()` を増やし、この配列にまとめて登録するだけで良い。
    private static let registry: [Identifier: GameMode] = {
        let modes: [GameMode] = [
            buildStandardMode(),
            buildClassicalChallengeMode()
        ]
        return Dictionary(uniqueKeysWithValues: modes.map { ($0.identifier, $0) })
    }()

    /// スタンダードモード（既存仕様）
    public static let standard: GameMode = {
        guard let mode = registry[.standard5x5] else {
            fatalError("標準モードのレジストリ登録に失敗しました")
        }
        return mode
    }()

    /// クラシカルチャレンジモード
    public static let classicalChallenge: GameMode = {
        guard let mode = registry[.classicalChallenge] else {
            fatalError("クラシカルチャレンジのレジストリ登録に失敗しました")
        }
        return mode
    }()

    /// 利用可能な全モードを列挙した配列
    /// - Note: タイトル画面のモード選択など UI 側で繰り返し利用するため、順序付きの一覧を提供する
    public static let allModes: [GameMode] = Identifier.allCases.compactMap { identifier in
        registry[identifier]
    }

    /// 識別子から対応するモード定義を取り出すヘルパー
    /// - Parameter identifier: 利用したいモードの識別子
    /// - Returns: `identifier` に対応する `GameMode`
    public static func mode(for identifier: Identifier) -> GameMode {
        registry[identifier] ?? standard
    }

    /// Equatable 準拠。識別子が一致すれば同一モードとみなす
    public static func == (lhs: GameMode, rhs: GameMode) -> Bool {
        lhs.identifier == rhs.identifier
    }

    /// スタンダードモードの定義を生成する
    private static func buildStandardMode() -> GameMode {
        let regulation = Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            deckConfiguration: .standard,
            spawnRule: .fixed(GridPoint.center(of: 5)),
            penalties: PenaltySettings(
                deadlockPenaltyCost: 5,
                manualRedrawPenaltyCost: 5,
                revisitPenaltyCost: 0
            )
        )
        return GameMode(identifier: .standard5x5, displayName: "スタンダード", regulation: regulation)
    }

    /// クラシカルチャレンジモードの定義を生成する
    private static func buildClassicalChallengeMode() -> GameMode {
        let regulation = Regulation(
            boardSize: 8,
            handSize: 5,
            nextPreviewCount: 3,
            deckConfiguration: .classicalChallenge,
            spawnRule: .chooseAnyAfterPreview,
            penalties: PenaltySettings(
                deadlockPenaltyCost: 2,
                manualRedrawPenaltyCost: 2,
                revisitPenaltyCost: 1
            )
        )
        return GameMode(identifier: .classicalChallenge, displayName: "クラシカルチャレンジ", regulation: regulation)
    }
}
