import Foundation

/// 盤面とヘルプ辞典で共有する敵の表示分類
public enum EnemyPresentationKind: String, CaseIterable, Equatable, Identifiable, Sendable {
    case guardPost
    case patrol
    case watcher
    case rotatingWatcher
    case chaser
    case marker
    case starReader

    public var id: String { rawValue }

    public var encyclopediaDiscoveryID: EncyclopediaDiscoveryID {
        EncyclopediaDiscoveryID(category: .enemy, itemID: rawValue)
    }

    public var displayName: String {
        switch self {
        case .guardPost:
            return "氷鎧のアザラシ"
        case .patrol:
            return "氷路のセイウチ"
        case .watcher:
            return "シロフクロウ"
        case .rotatingWatcher:
            return "オーロラフクロウ"
        case .chaser:
            return "ホッキョクギツネ"
        case .marker:
            return "氷下のシャチ"
        case .starReader:
            return "オーロラシャチ"
        }
    }

    public var behaviorSummary: String {
        switch self {
        case .guardPost:
            return "氷の盾を構えて動かず、隣接マスを守ります。"
        case .patrol:
            return "牙の向きに沿って、決まった氷路を1手ごとに進みます。"
        case .watcher:
            return "大きな目で、向いている直線方向を見張ります。"
        case .rotatingWatcher:
            return "現在の射線に獲物がいなければ、1手ごとに視線方向を右回りまたは左回りに変えます。"
        case .chaser:
            return "雪上の足跡を残し、モノへ最短経路で1マス近づきます。"
        case .marker:
            return "氷下を泳ぎ、ランダムな床へ突き上げ予告を出します。"
        case .starReader:
            return "オーロラを読み、ランダムな床に加えて今いるマスにも突き上げ予告を出します。"
        }
    }

    public var dangerSummary: String {
        switch self {
        case .guardPost:
            return "上下左右が危険です。敵本体は踏むと倒せますが、隣で止まると被弾します。"
        case .patrol:
            return "隣接マスが危険です。レールと矢印を見て、待つか越えるかを選びます。"
        case .watcher:
            return "目元から伸びるレーザー上が危険です。岩、柱、壁の手前でレーザーは止まります。"
        case .rotatingWatcher:
            return "目元から伸びるレーザーが現在の危険範囲です。レーザー外では、敵アイコンの回転矢印から次の向きを読みます。"
        case .chaser:
            return "移動先は盤面の小矢印で読みます。近づいた後の隣接範囲まで危険です。"
        case .marker:
            return "背びれと波紋が出たマスは次の敵ターンだけ危険です。予告を見て、止まる場所をずらします。"
        case .starReader:
            return "二重の背びれ予告中にその場へ留まると被弾します。次の手で現在地から離れます。"
        }
    }
}

public extension EnemyBehavior {
    var presentationKind: EnemyPresentationKind {
        switch self {
        case .guardPost:
            return .guardPost
        case .patrol:
            return .patrol
        case .watcher:
            return .watcher
        case .rotatingWatcher:
            return .rotatingWatcher
        case .chaser:
            return .chaser
        case .marker:
            return .marker
        case .targetedMarker:
            return .starReader
        }
    }

    var rotatingWatcherDirection: RotatingWatcherDirection? {
        guard case .rotatingWatcher(_, let rotationDirection, _) = self else { return nil }
        return rotationDirection
    }
}

/// ヘルプ内の敵辞典で表示する1件分の情報
public struct EnemyEncyclopediaEntry: Identifiable, Equatable, Sendable {
    public let kind: EnemyPresentationKind

    public var id: String { kind.id }
    public var displayName: String { kind.displayName }
    public var behaviorSummary: String { kind.behaviorSummary }
    public var dangerSummary: String { kind.dangerSummary }
    public var damageSummary: String {
        "敵の形は挙動を、色は攻撃力を表します。後半ほど攻撃力2や3の敵が出ます。"
    }

    public init(kind: EnemyPresentationKind) {
        self.kind = kind
    }

    public static let allEntries: [EnemyEncyclopediaEntry] = EnemyPresentationKind.allCases.map {
        EnemyEncyclopediaEntry(kind: $0)
    }
}
