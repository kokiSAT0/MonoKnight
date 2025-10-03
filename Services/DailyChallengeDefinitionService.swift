import Foundation
import Game

// MARK: - 日替わりチャレンジ情報の公開インターフェース
/// 日替わりチャレンジで利用するレギュレーションや表示用メタ情報を供給するプロトコル
/// - Important: 依存注入しやすいようにプロトコルとして公開し、プレビューやテストで差し替え可能にしている
@MainActor
protocol DailyChallengeDefinitionProviding: AnyObject {
    /// 指定日時に対応するチャレンジ情報を生成する
    /// - Parameter date: 判定対象となる日時（UTC 基準で日付境界を判断）
    /// - Returns: 日替わりチャレンジのモードや表示文言をまとめた情報
    func challengeInfo(for date: Date) -> DailyChallengeDefinitionService.ChallengeInfo

    /// 指定日時の翌日 0 時 (UTC) を計算し、リセット時刻として返す
    /// - Parameter date: 判定対象となる日時
    /// - Returns: UTC で日付が切り替わる瞬間の日時
    func nextResetDate(after date: Date) -> Date
}

// MARK: - 具象サービス実装
/// `DailyChallengeDefinition` を利用して当日のモード情報を構築するサービス
/// - Note: `ObservableObject` に準拠させておくことで、将来的に情報を Published で公開したくなった際にも拡張しやすいようにしている
@MainActor
final class DailyChallengeDefinitionService: ObservableObject, DailyChallengeDefinitionProviding {
    /// 日替わりチャレンジの表示・開始に必要な情報をまとめた構造体
    struct ChallengeInfo {
        /// 対象日（UTC 基準での当日）
        let date: Date
        /// `DailyChallengeDefinition.seed(for:)` から算出したシード値
        let baseSeed: UInt64
        /// 採用バリアント（固定 or ランダム）
        let variant: DailyChallengeDefinition.Variant
        /// 実際にゲーム開始へ渡す `GameMode`
        let mode: GameMode
        /// ランキング表示時に使用する Game Center 用モード識別子
        let leaderboardIdentifier: GameMode.Identifier

        /// UI で読み上げる際のバリアント名称
        var variantDisplayName: String {
            switch variant {
            case .fixed:
                return "固定レギュレーション"
            case .random:
                return "ランダムレギュレーション"
            }
        }

        /// タイトル画面カード用のヘッドライン文言
        var tileHeadlineText: String {
            "本日のモード: \(mode.displayName)"
        }

        /// タイトル画面カード用の詳細文言（盤面サイズや山札構成の概要）
        var tileDetailText: String {
            mode.primarySummaryText
        }

        /// レギュレーション要約の 1 行目（盤面サイズやスポーンルールなど）
        var regulationPrimaryText: String {
            mode.primarySummaryText
        }

        /// レギュレーション要約の 2 行目（手札やペナルティ設定など）
        var regulationSecondaryText: String {
            mode.secondarySummaryText
        }
    }

    /// バリアント決定に利用するクロージャ（シード値から決定する）
    private let variantResolver: (UInt64) -> DailyChallengeDefinition.Variant
    /// UTC 固定のカレンダー。日付境界の計算で利用する
    private let utcCalendar: Calendar

    /// - Parameters:
    ///   - variantResolver: シード値からバリアントを決めるロジック。テストで差し替えやすいよう外部注入できるようにしている。
    ///   - calendar: 日付計算に利用するカレンダー。既定ではグレゴリオ暦の UTC 固定とする。
    init(
        variantResolver: @escaping (UInt64) -> DailyChallengeDefinition.Variant = DailyChallengeDefinitionService.defaultVariantResolver,
        calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            return calendar
        }()
    ) {
        self.variantResolver = variantResolver
        self.utcCalendar = calendar
    }

    /// 指定日時に対応するチャレンジ情報を生成する
    func challengeInfo(for date: Date) -> ChallengeInfo {
        let baseSeed = DailyChallengeDefinition.seed(for: date)
        let resolvedVariant = variantResolver(baseSeed)
        let mode = DailyChallengeDefinition.makeMode(for: resolvedVariant, baseSeed: baseSeed)
        let leaderboardIdentifier: GameMode.Identifier
        switch resolvedVariant {
        case .fixed:
            leaderboardIdentifier = .dailyFixedChallenge
        case .random:
            leaderboardIdentifier = .dailyRandomChallenge
        }

        return ChallengeInfo(
            date: date,
            baseSeed: baseSeed,
            variant: resolvedVariant,
            mode: mode,
            leaderboardIdentifier: leaderboardIdentifier
        )
    }

    /// 指定日時の翌日 0 時 (UTC) を返す
    func nextResetDate(after date: Date) -> Date {
        let startOfDay = utcCalendar.startOfDay(for: date)
        // 翌日が取得できないケースは想定していないが、万が一失敗した場合でも 24 時間後へフォールバックさせる
        guard let nextDay = utcCalendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return startOfDay.addingTimeInterval(86_400)
        }
        return nextDay
    }

    /// 既定のバリアント決定ロジック（偶数シードは固定、奇数シードはランダム）
    private static func defaultVariantResolver(_ seed: UInt64) -> DailyChallengeDefinition.Variant {
        // seed の最下位ビットで偶奇を判定し、シンプルかつ決定論的にバリアントを切り替える
        if seed & 1 == 0 {
            return .fixed
        } else {
            return .random
        }
    }
}
