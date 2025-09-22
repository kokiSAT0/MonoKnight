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
    }

    /// 一意な識別子
    public let identifier: Identifier
    /// 表示名（タイトル画面などで利用）
    public let displayName: String
    /// 盤面サイズ（N×N）
    public let boardSize: Int
    /// 初期手札枚数
    public let handSize: Int
    /// 先読み表示枚数
    public let nextPreviewCount: Int
    /// 山札構成設定（ゲームモジュール内部で使用）
    let deckConfiguration: Deck.Configuration
    /// スポーンルール
    public let spawnRule: SpawnRule
    /// 自動ペナルティ（手詰まり引き直し）で加算する手数
    public let deadlockPenaltyCost: Int
    /// 手動ペナルティで加算する手数
    public let manualRedrawPenaltyCost: Int
    /// 既踏マスへ再訪した際に加算する手数
    public let revisitPenaltyCost: Int

    /// `Identifiable` 準拠用
    public var id: Identifier { identifier }

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
    public static let standard: GameMode = GameMode(
        identifier: .standard5x5,
        displayName: "スタンダード",
        boardSize: 5,
        handSize: 5,
        nextPreviewCount: 3,
        deckConfiguration: .standard,
        spawnRule: .fixed(GridPoint.center(of: 5)),
        deadlockPenaltyCost: 5,
        manualRedrawPenaltyCost: 5,
        revisitPenaltyCost: 0
    )

    /// クラシカルチャレンジモード
    public static let classicalChallenge: GameMode = GameMode(
        identifier: .classicalChallenge,
        displayName: "クラシカルチャレンジ",
        boardSize: 8,
        handSize: 5,
        nextPreviewCount: 3,
        deckConfiguration: .classicalChallenge,
        spawnRule: .chooseAnyAfterPreview,
        deadlockPenaltyCost: 2,
        manualRedrawPenaltyCost: 2,
        revisitPenaltyCost: 1
    )

    /// 利用可能な全モードを列挙した配列
    /// - Note: タイトル画面のモード選択など UI 側で繰り返し利用するため、順序付きの一覧を提供する
    public static let allModes: [GameMode] = Identifier.allCases.map { identifier in
        mode(for: identifier)
    }

    /// 識別子から対応するモード定義を取り出すヘルパー
    /// - Parameter identifier: 利用したいモードの識別子
    /// - Returns: `identifier` に対応する `GameMode`
    public static func mode(for identifier: Identifier) -> GameMode {
        switch identifier {
        case .standard5x5:
            return .standard
        case .classicalChallenge:
            return .classicalChallenge
        }
    }

    /// Equatable 準拠。識別子が一致すれば同一モードとみなす
    public static func == (lhs: GameMode, rhs: GameMode) -> Bool {
        lhs.identifier == rhs.identifier
    }
}
