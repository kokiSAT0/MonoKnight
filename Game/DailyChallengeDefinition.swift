import Foundation
#if canImport(GameplayKit)
import GameplayKit
#endif

/// 日替わりチャレンジのレギュレーションを構築するためのヘルパー群
/// - Note: 日付からシードを導出し、固定版・ランダム版それぞれで決定論的なモードを生成する。
public enum DailyChallengeDefinition {
    /// 日替わりチャレンジのバリアント種別
    public enum Variant {
        /// キャンペーン 5-8 と同じレギュレーションを採用する固定版
        case fixed
        /// 山札プリセットや盤面サイズを乱択するランダム版
        case random
    }

    /// 1 日を秒で表現した定数（UTC 判定用）
    private static let secondsPerDay: TimeInterval = 86_400

    /// UTC タイムゾーンを固定したカレンダー
    /// - Important: ローカルタイムゾーンの影響を排除し、世界中で同じ日付が同じシードへ対応するようにする。
    private static var utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // UTC への固定化が失敗するケースは想定していないため、取得に失敗した場合は実装ミスとして即座にクラッシュさせる。
        guard let utc = TimeZone(secondsFromGMT: 0) else {
            fatalError("UTC タイムゾーンの取得に失敗しました")
        }
        calendar.timeZone = utc
        return calendar
    }()

    /// 指定した UTC 日付から決定論的なシード値を算出する
    /// - Parameter date: 判定対象となる日時
    /// - Returns: 当該日の開始時刻 (UTC) を基準に算出した 64bit シード
    public static func seed(for date: Date) -> UInt64 {
        // 日付の開始時刻を UTC で丸め、タイムゾーン差分による揺らぎを完全に除去する。
        let startOfDay = utcCalendar.startOfDay(for: date)
        // Unix 時間を日単位で割り、整数化して 1 日ごとに連番となる値を得る。
        let dayIndex = floor(startOfDay.timeIntervalSince1970 / secondsPerDay)
        let signedValue = Int64(dayIndex)
        // 負数となる可能性も考慮し、ビットパターンを維持したまま UInt64 へ変換する。
        return UInt64(bitPattern: signedValue)
    }

    /// 指定バリアントに対応する `GameMode` を生成する
    /// - Parameters:
    ///   - variant: 固定版かランダム版かを示す種別
    ///   - baseSeed: 日付由来の基準シード
    /// - Returns: 決定論的に構築された `GameMode`
    public static func makeMode(for variant: Variant, baseSeed: UInt64) -> GameMode {
        switch variant {
        case .fixed:
            return makeFixedMode(baseSeed: baseSeed)
        case .random:
            return makeRandomMode(baseSeed: baseSeed)
        }
    }

    /// 固定版モードを生成する
    /// - Parameter baseSeed: 日付から導出したシード
    /// - Returns: キャンペーン 5-8 と同一設定の日替わりモード
    public static func makeFixedMode(baseSeed: UInt64) -> GameMode {
        let stageID = CampaignStageID(chapter: 5, index: 8)
        // キャンペーンライブラリから直接レギュレーションを取得し、定義の二重管理を避ける。
        let regulation = CampaignLibrary.shared.stage(with: stageID)?.regulation ?? GameMode.standard.regulationSnapshot
        let deckSeedValue = deckSeed(for: .fixed, baseSeed: baseSeed)
        return GameMode(
            identifier: .dailyFixed,
            displayName: "日替わり（固定）",
            regulation: regulation,
            leaderboardEligible: false,
            deckSeed: deckSeedValue
        )
    }

    /// ランダム版モードを生成する
    /// - Parameter baseSeed: 日付から導出したシード
    /// - Returns: 乱択ロジックに基づいて構築したモード
    public static func makeRandomMode(baseSeed: UInt64) -> GameMode {
        // レギュレーション用と山札用でシードを分岐させ、同じ日でも挙動が干渉しないようにする。
        let regulationSeed = baseSeed &+ 0x5F5F_F00D
        var randomizer = DailyRandomGenerator(seed: regulationSeed)
        let regulation = buildRandomRegulation(using: &randomizer)
        let deckSeedValue = deckSeed(for: .random, baseSeed: baseSeed)
        return GameMode(
            identifier: .dailyRandom,
            displayName: "日替わり（ランダム）",
            regulation: regulation,
            leaderboardEligible: false,
            deckSeed: deckSeedValue
        )
    }

    /// バリアントごとのデッキシードを計算する
    /// - Parameters:
    ///   - variant: 固定版かランダム版か
    ///   - baseSeed: 日付由来の基準シード
    /// - Returns: モードへ埋め込むシード値
    private static func deckSeed(for variant: Variant, baseSeed: UInt64) -> UInt64 {
        switch variant {
        case .fixed:
            // 固定版はキャンペーンと同じ挙動を維持したいので、軽微なオフセットのみを加える。
            return baseSeed &+ 0x0F0F_A5A5
        case .random:
            // ランダム版は十分に離れたビットパターンを足し、固定版との衝突を確実に防ぐ。
            return baseSeed &+ 0xC3D2_E1F0
        }
    }

    /// ランダム版のレギュレーションを組み立てる
    /// - Parameter randomizer: 乱数生成器（`GKMersenneTwisterRandomSource` をラップ）
    /// - Returns: 盤面や山札プリセット、ペナルティを決定論的に選択した設定
    private static func buildRandomRegulation(using randomizer: inout DailyRandomGenerator) -> GameMode.Regulation {
        // 盤面サイズ候補: 5×5 は既存 UI との互換性を優先し、7×7 で広い盤の練習もできるようにする。
        let boardSizeCandidates = [5, 7]
        let boardSize = choose(from: boardSizeCandidates, using: &randomizer)

        // 山札プリセット候補: 標準系と選択カード入りを中心にラインナップし、極端な訓練用構成は除外する。
        let deckCandidates: [GameDeckPreset] = [
            .standard,
            .standardLight,
            .standardWithOrthogonalChoices,
            .standardWithDiagonalChoices,
            .standardWithKnightChoices,
            .standardWithAllChoices,
            .directionChoice
        ]
        let deckPreset = choose(from: deckCandidates, using: &randomizer)

        // スポーンルールは中央固定と任意選択を 50% ずつで振り分ける。
        let spawnRule: GameMode.SpawnRule
        if randomizer.nextBool() {
            spawnRule = .fixed(BoardGeometry.defaultSpawnPoint(for: boardSize))
        } else {
            spawnRule = .chooseAnyAfterPreview
        }

        // ペナルティ候補は実運用で採用している値をベースに幅を持たせる。
        // deadlock: 3〜6 の範囲、manual redraw: 3〜6 の範囲、discard: 1 or 2、revisit: 0〜2。
        let deadlockOptions = [3, 4, 5, 6]
        let manualRedrawOptions = [3, 4, 5, 6]
        let manualDiscardOptions = [1, 2]
        let revisitOptions = [0, 1, 2]

        let penalties = GameMode.PenaltySettings(
            deadlockPenaltyCost: choose(from: deadlockOptions, using: &randomizer),
            manualRedrawPenaltyCost: choose(from: manualRedrawOptions, using: &randomizer),
            manualDiscardPenaltyCost: choose(from: manualDiscardOptions, using: &randomizer),
            revisitPenaltyCost: choose(from: revisitOptions, using: &randomizer)
        )

        // 盤面ギミックは日替わりランダムでは導入せず、基本ルールに集中できる構成とする。
        return GameMode.Regulation(
            boardSize: boardSize,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: deckPreset,
            spawnRule: spawnRule,
            penalties: penalties
        )
    }

    /// 配列から 1 要素を安全に選択するヘルパー
    /// - Parameters:
    ///   - candidates: 選択対象の配列
    ///   - randomizer: 利用する乱数生成器
    /// - Returns: 乱数で選ばれた要素（候補が空の場合は致命的エラー）
    private static func choose<T>(from candidates: [T], using randomizer: inout DailyRandomGenerator) -> T {
        precondition(!candidates.isEmpty, "候補配列が空です")
        let index = randomizer.nextInt(upperBound: candidates.count)
        return candidates[index]
    }
}

/// GameplayKit が利用できない環境向けの代替乱数生成器
/// - Important: iOS / 実機では GKMersenneTwisterRandomSource を使用し、テスト用の Linux 等では簡易 Xorshift で同等 API を提供する。
private struct DailyRandomGenerator {
#if canImport(GameplayKit)
    /// GameplayKit のメルセンヌツイスタを内包
    private let source: GKMersenneTwisterRandomSource

    /// 指定シードで初期化
    /// - Parameter seed: 乱数シード
    init(seed: UInt64) {
        source = GKMersenneTwisterRandomSource(seed: seed)
    }

    /// 上限を指定して乱数を生成
    /// - Parameter upperBound: 生成したい上限値（排他的）
    mutating func nextInt(upperBound: Int) -> Int {
        source.nextInt(upperBound: upperBound)
    }

    /// 真偽値を生成
    mutating func nextBool() -> Bool {
        source.nextInt(upperBound: 2) == 0
    }
#else
    /// Xorshift64* による簡易シード値
    private var state: UInt64

    /// 指定シードで初期化
    /// - Parameter seed: 乱数シード
    init(seed: UInt64) {
        state = seed == 0 ? 0x4d595df4d0f33173 : seed
    }

    /// 上限を指定して乱数を生成
    /// - Parameter upperBound: 生成したい上限値（排他的）
    mutating func nextInt(upperBound: Int) -> Int {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        let value = state % UInt64(upperBound)
        return Int(value)
    }

    /// 真偽値を生成
    mutating func nextBool() -> Bool {
        nextInt(upperBound: 2) == 0
    }
#endif
}
