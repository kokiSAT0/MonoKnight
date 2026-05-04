import Foundation

/// マス辞典で盤面上の見た目を例示するための分類
public enum TileMarkerPreviewKind: Equatable {
    case normal
    case spawn
    case target
    case nextTarget
    case multiVisit
    case toggle
    case impassable
    case effect(TileEffect)
}

/// ヘルプ内のマス辞典で表示する 1 件分の情報
public struct TileEncyclopediaEntry: Identifiable, Equatable {
    public let id: String
    public let displayName: String
    public let category: String
    public let description: String
    public let previewKind: TileMarkerPreviewKind

    public init(
        id: String,
        displayName: String,
        category: String,
        description: String,
        previewKind: TileMarkerPreviewKind
    ) {
        self.id = id
        self.displayName = displayName
        self.category = category
        self.description = description
        self.previewKind = previewKind
    }

    /// マス辞典に表示する全マス種別
    public static let allEntries: [TileEncyclopediaEntry] = [
        TileEncyclopediaEntry(
            id: "normal",
            displayName: "通常マス",
            category: "基本",
            description: "踏むと踏破済みになります。目的地制では通過や停止の経路として扱います。",
            previewKind: .normal
        ),
        TileEncyclopediaEntry(
            id: "spawn",
            displayName: "スポーンマス",
            category: "基本",
            description: "ゲーム開始時の位置です。固定スポーンでは最初から踏破済みとして扱います。",
            previewKind: .spawn
        ),
        TileEncyclopediaEntry(
            id: "target",
            displayName: "目的地マーカー",
            category: "目的地",
            description: "表示中の目的地です。どれからでも獲得でき、獲得後は新しい目的地が補充されます。",
            previewKind: .target
        ),
        TileEncyclopediaEntry(
            id: "nextTarget",
            displayName: "表示中の目的地",
            category: "目的地",
            description: "目的地マーカーとして表示されます。手札を見て取りやすいものから踏めます。",
            previewKind: .nextTarget
        ),
        TileEncyclopediaEntry(
            id: "multiVisit",
            displayName: "複数回踏破マス",
            category: "踏破",
            description: "指定回数だけ踏むまで未踏扱いが残ります。残り回数が 0 になると踏破済みです。",
            previewKind: .multiVisit
        ),
        TileEncyclopediaEntry(
            id: "toggle",
            displayName: "トグルマス",
            category: "踏破",
            description: "踏むたびに踏破済みと未踏が入れ替わります。最後に踏破済み側で止める必要があります。",
            previewKind: .toggle
        ),
        TileEncyclopediaEntry(
            id: "impassable",
            displayName: "障害物マス",
            category: "障害物",
            description: "岩や柱の印がある移動できないマスです。移動候補から除外され、レイカードや敵の視線も手前で止まります。",
            previewKind: .impassable
        ),
        TileEncyclopediaEntry(
            id: "warp",
            displayName: "ワープマス",
            category: "特殊効果",
            description: "同じペアのマスへ移動します。無効な行き先や障害物へのワープは安全に無視されます。",
            previewKind: .effect(.warp(pairID: "dictionary", destination: GridPoint(x: 0, y: 0)))
        ),
        TileEncyclopediaEntry(
            id: "shuffleHand",
            displayName: "シャッフルマス",
            category: "特殊効果",
            description: "移動後に手札をランダムに並び替えます。",
            previewKind: .effect(.shuffleHand)
        ),
        TileEncyclopediaEntry(
            id: "boost",
            displayName: "加速マス",
            category: "特殊効果",
            description: "踏むと進行方向へもう 1 マス進みます。加速先が盤外や障害物ならその場で止まります。",
            previewKind: .effect(.boost)
        ),
        TileEncyclopediaEntry(
            id: "slow",
            displayName: "減速マス",
            category: "特殊効果",
            description: "踏むとその手の残り移動をそこで打ち切ります。減速マス自体は踏破されます。",
            previewKind: .effect(.slow)
        ),
        TileEncyclopediaEntry(
            id: "nextRefresh",
            displayName: "NEXT更新マス",
            category: "特殊効果",
            description: "移動後、手札は維持したまま NEXT だけを引き直します。",
            previewKind: .effect(.nextRefresh)
        ),
        TileEncyclopediaEntry(
            id: "freeFocus",
            displayName: "無料フォーカスマス",
            category: "特殊効果",
            description: "フォーカス回数を増やさず、目的地へ近づきやすい手札と NEXT に再配布します。",
            previewKind: .effect(.freeFocus)
        ),
        TileEncyclopediaEntry(
            id: "preserveCard",
            displayName: "カード温存マス",
            category: "特殊効果",
            description: "その手で使ったカードを消費せずに残します。移動や目的地獲得は通常どおり処理されます。",
            previewKind: .effect(.preserveCard)
        ),
        TileEncyclopediaEntry(
            id: "draft",
            displayName: "ドラフトマス",
            category: "特殊効果",
            description: "使用カードを消費した後、目的地へ近づきやすい手札と NEXT に再配布します。",
            previewKind: .effect(.draft)
        ),
        TileEncyclopediaEntry(
            id: "overload",
            displayName: "過負荷マス",
            category: "特殊効果",
            description: "反動コストを受ける代わりに、次の 1 手だけ使用カードを消費しない状態になります。",
            previewKind: .effect(.overload)
        ),
        TileEncyclopediaEntry(
            id: "targetSwap",
            displayName: "転換マス",
            category: "特殊効果",
            description: "目的地取得を解決した後、表示中目的地の先頭と NEXT 目的地の先頭を入れ替えます。",
            previewKind: .effect(.targetSwap)
        ),
        TileEncyclopediaEntry(
            id: "openGate",
            displayName: "開門マス",
            category: "特殊効果",
            description: "指定された障害物 1 マスを通常の未踏破マスへ変えます。",
            previewKind: .effect(.openGate(target: GridPoint(x: 0, y: 0)))
        )
    ]
}
