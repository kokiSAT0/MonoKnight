import Foundation
import Game

// MARK: - 日替わりチャレンジ情報の公開インターフェース
/// 日替わりチャレンジで利用するレギュレーションや表示用メタ情報を供給するプロトコル
/// - Important: 依存注入しやすいようにプロトコルとして公開し、プレビューやテストで差し替え可能にしている
@MainActor
protocol DailyChallengeDefinitionProviding: AnyObject {
    /// 指定日時に対応するチャレンジ情報束を生成する
    /// - Parameter date: 判定対象となる日時（UTC 基準で日付境界を判断）
    /// - Returns: 固定・ランダム双方のモード情報を含むバンドル
    func challengeBundle(for date: Date) -> DailyChallengeDefinitionService.ChallengeBundle

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
    /// 同日に公開する全チャレンジ情報をまとめた構造体
    struct ChallengeBundle {
        /// 対象日（UTC 基準での当日）
        let date: Date
        /// `DailyChallengeDefinition.seed(for:)` から算出したシード値
        let baseSeed: UInt64
        /// 固定レギュレーションの情報
        let fixed: ChallengeInfo
        /// ランダムレギュレーションの情報
        let random: ChallengeInfo

        /// UI 側で順序付きに扱いやすくするための一覧
        var orderedInfos: [ChallengeInfo] { [fixed, random] }

        /// バリアント種別から対応する情報を引き当てるヘルパー
        /// - Parameter variant: 固定かランダムかの別
        /// - Returns: 指定バリアントに対応する `ChallengeInfo`
        func info(for variant: DailyChallengeDefinition.Variant) -> ChallengeInfo {
            switch variant {
            case .fixed:
                return fixed
            case .random:
                return random
            }
        }
    }

    /// 個々のステージカードで表示・利用する情報をまとめた構造体
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

        /// アクセシビリティ識別子などで利用する接尾辞（固定/ランダム）
        var identifierSuffix: String {
            switch variant {
            case .fixed:
                return "fixed"
            case .random:
                return "random"
            }
        }
    }

    /// UTC 固定のカレンダー。日付境界の計算で利用する
    private let utcCalendar: Calendar

    /// - Parameters:
    ///   - calendar: 日付計算に利用するカレンダー。既定ではグレゴリオ暦の UTC 固定とする。
    init(
        calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
            return calendar
        }()
    ) {
        self.utcCalendar = calendar
    }

    /// 指定日時に対応するチャレンジ情報束を生成する
    func challengeBundle(for date: Date) -> ChallengeBundle {
        let baseSeed = DailyChallengeDefinition.seed(for: date)
        // 固定・ランダム双方のモードを同時に構築し、UI 側で常に 2 段構成を利用できるようにする
        let fixedMode = DailyChallengeDefinition.makeMode(for: .fixed, baseSeed: baseSeed)
        let randomMode = DailyChallengeDefinition.makeMode(for: .random, baseSeed: baseSeed)

        let fixedInfo = Self.makeInfo(
            variant: .fixed,
            date: date,
            baseSeed: baseSeed,
            mode: fixedMode
        )
        let randomInfo = Self.makeInfo(
            variant: .random,
            date: date,
            baseSeed: baseSeed,
            mode: randomMode
        )

        return ChallengeBundle(
            date: date,
            baseSeed: baseSeed,
            fixed: fixedInfo,
            random: randomInfo
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

    // 純粋関数のためメインアクター不要
    /// バリアントごとの共通情報を構築するヘルパー
    /// - Parameters:
    ///   - variant: 固定版かランダム版か
    ///   - date: 対象日
    ///   - baseSeed: 日付由来の基準シード
    ///   - mode: 実際にゲーム開始へ渡す `GameMode`
    /// - Returns: UI 表示・開始処理に必要な情報一式
    private nonisolated static func makeInfo(
        variant: DailyChallengeDefinition.Variant,
        date: Date,
        baseSeed: UInt64,
        mode: GameMode
    ) -> ChallengeInfo {
        let leaderboardIdentifier: GameMode.Identifier
        switch variant {
        case .fixed:
            leaderboardIdentifier = .dailyFixedChallenge
        case .random:
            leaderboardIdentifier = .dailyRandomChallenge
        }

        return ChallengeInfo(
            date: date,
            baseSeed: baseSeed,
            variant: variant,
            mode: mode,
            leaderboardIdentifier: leaderboardIdentifier
        )
    }
}
