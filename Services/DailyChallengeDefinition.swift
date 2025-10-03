import Foundation
import Game

/// デイリーチャレンジで使用するレギュレーションや表示用情報をまとめた定義構造体
/// - Note: 1 日ごとにユニークな ID を生成し、挑戦回数ストアがリセット判定に利用できるようにする。
struct DailyChallengeDefinition: Equatable, Identifiable {
    /// ビュー表示時に利用する補足説明のリスト
    /// - Important: 画面側で箇条書き表示するため、短い文章で統一する。
    let regulationNotes: [String]
    /// ユーザーへ提示する短い見出し
    let regulationHeadline: String
    /// レギュレーション詳細（盤面サイズやペナルティの概要）
    let regulationDetail: String
    /// 1 日あたりの基本挑戦回数
    let baseAttemptsPerDay: Int
    /// 広告視聴などで追加ストックできる上限数
    let bonusAttemptCapacity: Int
    /// リワード広告 1 回あたりで補充する挑戦回数
    let adRewardAmount: Int
    /// リセット時刻（現地タイムゾーン基準）
    let resetTime: DateComponents
    /// 当日のプレイに使用するゲームモード
    let gameMode: GameMode
    /// 定義を作成した日付（表示用）
    let targetDate: Date
    /// 定義生成に利用したカレンダー識別子
    let calendarIdentifier: Calendar.Identifier
    /// 表示やリセット計算で利用するタイムゾーン
    let timeZone: TimeZone
    /// 定義ごとに一意な識別子
    let id: String

    /// 最大ストック数（基本回数 + 広告補充上限）
    var maximumAttemptStock: Int { baseAttemptsPerDay + bonusAttemptCapacity }

    /// View 側で表示する日付文字列を生成する
    /// - Parameters:
    ///   - calendar: 表示に使用するカレンダー
    ///   - locale: 表示ロケール
    /// - Returns: 例 "2024年4月20日(土)"
    func formattedDateText(calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy年M月d日(EEE)"
        return formatter.string(from: targetDate)
    }

    /// 次回リセットの日時を求める
    /// - Parameters:
    ///   - referenceDate: 現在時刻
    ///   - calendar: 計算に利用するカレンダー
    /// - Returns: 次に回数がリセットされる日時
    func nextResetDate(after referenceDate: Date, calendar: Calendar) -> Date {
        var calendar = calendar
        calendar.timeZone = timeZone

        let hour = resetTime.hour ?? 0
        let minute = resetTime.minute ?? 0
        let second = resetTime.second ?? 0

        if let sameDay = calendar.date(bySettingHour: hour, minute: minute, second: second, of: referenceDate),
           referenceDate < sameDay {
            return sameDay
        }

        // 当日分を過ぎている場合は翌日の同時刻を返す
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate
        return calendar.date(bySettingHour: hour, minute: minute, second: second, of: tomorrow) ?? referenceDate
    }

    /// 次回リセットの表示用文字列を生成する
    /// - Parameters:
    ///   - referenceDate: 現在時刻
    ///   - calendar: 計算に利用するカレンダー
    ///   - locale: 表示ロケール
    /// - Returns: 例 "4/20 4:00 にリセット"
    func formattedNextResetText(after referenceDate: Date, calendar: Calendar, locale: Locale) -> String {
        let nextReset = nextResetDate(after: referenceDate, calendar: calendar)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "M/d H:mm"
        return "\(formatter.string(from: nextReset)) にリセット"
    }

    /// 表示用の挑戦回数テキストを生成する
    /// - Parameter remainingAttempts: 現在残っている回数
    /// - Returns: "残り 3 / 5 回" のような文字列
    func attemptStatusText(remainingAttempts: Int) -> String {
        "残り \(remainingAttempts) / \(maximumAttemptStock) 回"
    }

    /// タイトルタイルなどで使用するコンパクトな表記
    /// - Parameter remainingAttempts: 現在残っている回数
    /// - Returns: "3/5" のような簡易表記
    func compactAttemptStatus(remainingAttempts: Int) -> String {
        "\(remainingAttempts)/\(maximumAttemptStock)"
    }

    /// 現在日付に応じた定義を生成する
    /// - Parameters:
    ///   - calendar: 使用するカレンダー（デフォルトは日本語環境で一般的な和暦グレゴリオ暦）
    ///   - date: 判定基準となる日付
    /// - Returns: 当日の定義
    static func makeForToday(calendar: Calendar = Calendar(identifier: .gregorian),
                             date: Date = Date(),
                             timeZone: TimeZone = .current) -> DailyChallengeDefinition {
        var calendar = calendar
        calendar.timeZone = timeZone

        let presets = regulationPresets
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 0
        let preset = presets[dayOfYear % presets.count]

        var regulation = GameMode.standard.regulationSnapshot
        regulation.deckPreset = preset.deckPreset
        if let penalties = preset.penalties {
            regulation.penalties = penalties
        }
        if let spawnRule = preset.spawnRule {
            regulation.spawnRule = spawnRule
        }

        let mode = GameMode(
            identifier: .dailyChallenge,
            displayName: "デイリー: \(preset.title)",
            regulation: regulation,
            leaderboardEligible: true,
            campaignMetadata: nil
        )

        let notes: [String] = [
            "盤面: \(mode.boardSize)×\(mode.boardSize) ・ \(mode.spawnRule.summaryText)",
            "山札: \(mode.deckPreset.displayName)",
            mode.manualPenaltySummaryText,
            mode.stackingRuleDetailText
        ]

        let identifierFormatter = DateFormatter()
        identifierFormatter.calendar = calendar
        identifierFormatter.timeZone = timeZone
        identifierFormatter.dateFormat = "yyyyMMdd"
        let identifier = "\(identifierFormatter.string(from: date))_preset_\(preset.identifier)"

        return DailyChallengeDefinition(
            regulationNotes: notes,
            regulationHeadline: preset.headline,
            regulationDetail: mode.secondarySummaryText,
            baseAttemptsPerDay: 3,
            bonusAttemptCapacity: 2,
            adRewardAmount: 1,
            resetTime: DateComponents(hour: 4, minute: 0, second: 0),
            gameMode: mode,
            targetDate: date,
            calendarIdentifier: calendar.identifier,
            timeZone: timeZone,
            id: identifier
        )
    }
}

private extension DailyChallengeDefinition {
    /// レギュレーションプリセットの簡易定義
    struct RegulationPreset {
        let identifier: String
        let title: String
        let headline: String
        let deckPreset: GameDeckPreset
        let penalties: GameMode.PenaltySettings?
        let spawnRule: GameMode.SpawnRule?
    }

    /// 日替わりで循環させるプリセット定義一覧
    static let regulationPresets: [RegulationPreset] = [
        RegulationPreset(
            identifier: "knight_focus",
            title: "桂馬ブリッツ",
            headline: "桂馬強化デッキで素早く踏破",
            deckPreset: .standardWithKnightChoices,
            penalties: nil,
            spawnRule: nil
        ),
        RegulationPreset(
            identifier: "orthogonal_training",
            title: "直線訓練",
            headline: "縦横選択カードで道筋を描く",
            deckPreset: .standardWithOrthogonalChoices,
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 4,
                manualRedrawPenaltyCost: 4,
                manualDiscardPenaltyCost: 2,
                revisitPenaltyCost: 1
            ),
            spawnRule: nil
        ),
        RegulationPreset(
            identifier: "diagonal_escape",
            title: "対角エスケープ",
            headline: "斜め選択で包囲網を突破",
            deckPreset: .standardWithDiagonalChoices,
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 5,
                manualRedrawPenaltyCost: 5,
                manualDiscardPenaltyCost: 0,
                revisitPenaltyCost: 0
            ),
            spawnRule: .chooseAnyAfterPreview
        )
    ]
}
