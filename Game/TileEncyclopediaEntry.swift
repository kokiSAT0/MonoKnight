import Foundation

/// マス辞典で盤面上の見た目を例示するための分類
public enum TileMarkerPreviewKind: Equatable {
    case normal
    case spawn
    case dungeonExit
    case lockedDungeonExit
    case dungeonKey
    case cardPickup
    case dungeonRelicPickup
    case damageTrap
    case healingTile
    case brittleFloor
    case collapsedFloor
    case enemyDanger
    case enemyWarning
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
    public var encyclopediaDiscoveryID: EncyclopediaDiscoveryID {
        EncyclopediaDiscoveryID(category: .tile, itemID: id)
    }

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
            description: "騎士が通れる床です。基本移動やカード移動で通過し、階段までのルートになります。",
            previewKind: .normal
        ),
        TileEncyclopediaEntry(
            id: "spawn",
            displayName: "開始位置",
            category: "基本",
            description: "その階の開始位置です。成長塔の連続進行では、前の階の階段位置から始まることがあります。",
            previewKind: .spawn
        ),
        TileEncyclopediaEntry(
            id: "dungeonExit",
            displayName: "出口 / 階段",
            category: "攻略",
            description: "ここへ到達すると階をクリアします。レイ型カードなどの途中移動でも、解錠済みなら到達した時点で止まります。",
            previewKind: .dungeonExit
        ),
        TileEncyclopediaEntry(
            id: "lockedDungeonExit",
            displayName: "施錠階段",
            category: "攻略",
            description: "鍵を取るまでクリアできない階段です。鍵を取ると通常の出口として使えます。",
            previewKind: .lockedDungeonExit
        ),
        TileEncyclopediaEntry(
            id: "dungeonKey",
            displayName: "鍵",
            category: "攻略",
            description: "施錠階段を開けるためのマスです。踏むと取得され、盤面から消えます。",
            previewKind: .dungeonKey
        ),
        TileEncyclopediaEntry(
            id: "cardPickup",
            displayName: "床落ちカード",
            category: "攻略",
            description: "踏むと追加手数なしで拾えます。未使用分は同じ区間の次の階へ持ち越せます。",
            previewKind: .cardPickup
        ),
        TileEncyclopediaEntry(
            id: "dungeonRelicPickup",
            displayName: "宝箱",
            category: "攻略",
            description: "踏むと遺物やイベントが発生するマスです。カード所持枠は使いません。",
            previewKind: .dungeonRelicPickup
        ),
        TileEncyclopediaEntry(
            id: "impassable",
            displayName: "障害物マス",
            category: "障害物",
            description: "岩や柱の印がある移動できないマスです。移動候補から除外され、レイカードや敵の視線も手前で止まります。",
            previewKind: .impassable
        ),
        TileEncyclopediaEntry(
            id: "damageTrap",
            displayName: "罠",
            category: "危険",
            description: "見えているダメージ床です。踏むと HP を失いますが、近道として使える場面もあります。",
            previewKind: .damageTrap
        ),
        TileEncyclopediaEntry(
            id: "healingTile",
            displayName: "回復マス",
            category: "攻略",
            description: "踏むと HP が 1 増えて消費されます。最大 HP を超えて増えるため、危険な近道の前後で立て直せます。",
            previewKind: .healingTile
        ),
        TileEncyclopediaEntry(
            id: "brittleFloor",
            displayName: "ひび割れ床",
            category: "危険",
            description: "1 回踏むとひび割れ、もう一度踏むと崩れて HP を失い、下の階へ落ちることがあります。",
            previewKind: .brittleFloor
        ),
        TileEncyclopediaEntry(
            id: "collapsedFloor",
            displayName: "崩落床",
            category: "危険",
            description: "崩れたあとの穴です。入るともう一度落下し、敵の経路からは外れます。",
            previewKind: .collapsedFloor
        ),
        TileEncyclopediaEntry(
            id: "enemyDanger",
            displayName: "敵の危険範囲",
            category: "危険",
            description: "この範囲に入ると敵からダメージを受けます。敵によって向き、射線、隣接、巡回の読み方が変わります。",
            previewKind: .enemyDanger
        ),
        TileEncyclopediaEntry(
            id: "enemyWarning",
            displayName: "予告床",
            category: "危険",
            description: "次の敵ターンで危険になる床です。安全な待機マスをずらす必要があります。",
            previewKind: .enemyWarning
        ),
        TileEncyclopediaEntry(
            id: "warp",
            displayName: "ワープマス",
            category: "特殊効果",
            description: "対応するワープ床へ移動します。近道にも危険な転移にもなるため、行き先を見てから踏みます。",
            previewKind: .effect(.warp(pairID: "dictionary", destination: GridPoint(x: 0, y: 0)))
        ),
        TileEncyclopediaEntry(
            id: "blast",
            displayName: "吹き飛ばしマス",
            category: "特殊効果",
            description: "矢印の方向へ、壁や障害物に当たる直前まで移動します。通ったマスも踏んだ扱いになります。",
            previewKind: .effect(.blast(direction: MoveVector(dx: 1, dy: 0)))
        ),
        TileEncyclopediaEntry(
            id: "shuffleHand",
            displayName: "手札混乱マス",
            category: "特殊効果",
            description: "踏むと手札の並びが入れ替わります。移動先の候補をもう一度確認します。",
            previewKind: .effect(.shuffleHand)
        ),
        TileEncyclopediaEntry(
            id: "preserveCard",
            displayName: "カード温存マス",
            category: "特殊効果",
            description: "踏むと使ったカードを消費せずに温存します。危険地帯の突破前に使うと手札を保ちやすくなります。",
            previewKind: .effect(.preserveCard)
        ),
        TileEncyclopediaEntry(
            id: "paralysisTrap",
            displayName: "麻痺罠",
            category: "危険",
            description: "踏むとしびれて1回休みになります。レイ型移動はこの罠で止まり、敵が続けて動きます。",
            previewKind: .effect(.slow)
        ),
        TileEncyclopediaEntry(
            id: "swamp",
            displayName: "沼",
            category: "特殊効果",
            description: "移動系カードで入るとそこで止まり、沼の上では移動系カードを使えません。基本移動と補給は使えます。",
            previewKind: .effect(.swamp)
        ),
        TileEncyclopediaEntry(
            id: "discardRandomHandTrap",
            displayName: "手札喪失罠",
            category: "危険",
            description: "踏むと手札スロットをランダムに1つ失います。失った枠はすぐには補充されません。",
            previewKind: .effect(.discardRandomHand)
        ),
        TileEncyclopediaEntry(
            id: "discardAllHandsTrap",
            displayName: "全手札喪失罠",
            category: "危険",
            description: "踏むと手札スロットをすべて失います。複数の割れたカードが目印の上位罠です。",
            previewKind: .effect(.discardAllHands)
        )
    ]
}
