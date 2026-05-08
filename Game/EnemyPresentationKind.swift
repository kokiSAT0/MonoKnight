import Foundation

/// 盤面とヘルプ辞典で共有する敵の表示分類
public enum EnemyPresentationKind: String, CaseIterable, Equatable, Identifiable {
    case guardPost
    case patrol
    case watcher
    case rotatingWatcher
    case chaser
    case marker

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .guardPost:
            return "番兵"
        case .patrol:
            return "巡回兵"
        case .watcher:
            return "見張り"
        case .rotatingWatcher:
            return "回転見張り"
        case .chaser:
            return "追跡兵"
        case .marker:
            return "予告兵"
        }
    }

    public var behaviorSummary: String {
        switch self {
        case .guardPost:
            return "その場から動かず、隣接マスを守ります。"
        case .patrol:
            return "決まった巡回路を1手ごとに進みます。"
        case .watcher:
            return "向いている直線方向を見張ります。"
        case .rotatingWatcher:
            return "1手ごとに視線方向を順番に変えます。"
        case .chaser:
            return "プレイヤーへ最短経路で1マス近づきます。"
        case .marker:
            return "次の敵ターンで危険になる床を予告します。"
        }
    }

    public var dangerSummary: String {
        switch self {
        case .guardPost:
            return "上下左右が危険です。敵本体は踏むと倒せますが、隣で止まると被弾します。"
        case .patrol:
            return "隣接マスが危険です。レールと矢印を見て、待つか越えるかを選びます。"
        case .watcher:
            return "視線の直線上が危険です。岩、柱、壁の手前で視線は止まります。"
        case .rotatingWatcher:
            return "今の視線と次の向きを合わせて読みます。矢印方向へ次に向き直ります。"
        case .chaser:
            return "近づいた後の隣接範囲まで危険になります。寄り道や待機で詰められます。"
        case .marker:
            return "薄い警告床は次の敵ターンだけ危険です。今安全でも、待つ場所をずらします。"
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
        }
    }
}

/// ヘルプ内の敵辞典で表示する1件分の情報
public struct EnemyEncyclopediaEntry: Identifiable, Equatable {
    public let kind: EnemyPresentationKind

    public var id: String { kind.id }
    public var displayName: String { kind.displayName }
    public var behaviorSummary: String { kind.behaviorSummary }
    public var dangerSummary: String { kind.dangerSummary }

    public init(kind: EnemyPresentationKind) {
        self.kind = kind
    }

    public static let allEntries: [EnemyEncyclopediaEntry] = EnemyPresentationKind.allCases.map {
        EnemyEncyclopediaEntry(kind: $0)
    }
}
