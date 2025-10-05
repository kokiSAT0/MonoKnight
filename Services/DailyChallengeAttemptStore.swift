import Foundation
import Combine
import SwiftUI
import Game
import SharedSupport // ログユーティリティを活用するため追加

// MARK: - 日替わりチャレンジ挑戦回数の公開インターフェース
/// UI 全体から挑戦回数の残量や付与処理を扱えるようにするためのプロトコル
/// - Note: `ObservableObject` に準拠しているため、SwiftUI の `@EnvironmentObject` としても利用できる
@MainActor
/// - Note: `ObservableObjectPublisher` を明示することで `objectWillChange` を型消去経由でも購読可能にする
protocol DailyChallengeAttemptStoreProtocol: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    /// 残り挑戦回数（無料 1 回 + リワード広告による加算分 - 消費済み回数）をバリアント単位で参照する
    /// - Parameter variant: 固定ステージかランダムステージか
    func remainingAttempts(for variant: DailyChallengeDefinition.Variant) -> Int
    /// その日にリワード広告によって付与済みの回数をバリアント単位で参照する
    /// - Parameter variant: 固定ステージかランダムステージか
    func rewardedAttemptsGranted(for variant: DailyChallengeDefinition.Variant) -> Int
    /// 1 日あたり付与できるリワード広告ボーナス回数の上限（仕様で 3 回）
    var maximumRewardedAttempts: Int { get }
    /// デバッグ用の無制限フラグが有効かどうか
    var isDebugUnlimitedEnabled: Bool { get }

    /// UTC 日付の境界を跨いだ場合に状態を初期化する
    func refreshForCurrentDate()
    /// 残り挑戦回数を 1 消費し、成功したかを返す
    @discardableResult
    func consumeAttempt(for variant: DailyChallengeDefinition.Variant) -> Bool
    /// リワード広告視聴が成功した際に 1 回分の挑戦回数を付与する
    @discardableResult
    func grantRewardedAttempt(for variant: DailyChallengeDefinition.Variant) -> Bool
    /// デバッグパスコード入力などで無制限モードを有効化する
    func enableDebugUnlimited()
    /// デバッグ無制限モードを明示的に無効化する
    func disableDebugUnlimited()
}

// MARK: - 型消去ラッパー
/// 具象ストアを `ObservableObject` のまま別タイプへ差し替えられるようにするためのタイプイレース
@MainActor
final class AnyDailyChallengeAttemptStore: ObservableObject, DailyChallengeAttemptStoreProtocol {
    /// 自身の `objectWillChange` を `nonisolated` として公開し、`ObservableObject` の要件を満たす
    /// - Important: SwiftUI 側からメインアクター外でも購読できるようにするため `nonisolated` を指定
    nonisolated let objectWillChange = ObservableObjectPublisher()
    /// 実体となるストアを保持し、全メソッドを委譲する
    private let base: any DailyChallengeAttemptStoreProtocol
    /// ストアの変更通知を横取りして上位へ再送するためのキャンセラ
    private var cancellable: AnyCancellable?

    init(base: any DailyChallengeAttemptStoreProtocol) {
        self.base = base

        // ベースストアが発行した変更通知をそのまま転送し、SwiftUI 側で再描画されるようにする
        cancellable = base.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.objectWillChange.send()
            }
        }
    }

    // MARK: - Protocol forwarding（メソッドはすべて委譲）

    func remainingAttempts(for variant: DailyChallengeDefinition.Variant) -> Int {
        base.remainingAttempts(for: variant)
    }

    func rewardedAttemptsGranted(for variant: DailyChallengeDefinition.Variant) -> Int {
        base.rewardedAttemptsGranted(for: variant)
    }

    var maximumRewardedAttempts: Int {
        base.maximumRewardedAttempts
    }

    var isDebugUnlimitedEnabled: Bool {
        base.isDebugUnlimitedEnabled
    }

    func refreshForCurrentDate() {
        base.refreshForCurrentDate()
    }

    @discardableResult
    func consumeAttempt(for variant: DailyChallengeDefinition.Variant) -> Bool {
        base.consumeAttempt(for: variant)
    }

    @discardableResult
    func grantRewardedAttempt(for variant: DailyChallengeDefinition.Variant) -> Bool {
        base.grantRewardedAttempt(for: variant)
    }

    func enableDebugUnlimited() {
        base.enableDebugUnlimited()
    }

    func disableDebugUnlimited() {
        base.disableDebugUnlimited()
    }
}

// MARK: - 実ストア実装
/// UserDefaults へ挑戦回数の履歴を保存し、毎日 UTC 基準でリセットするストア
@MainActor
final class DailyChallengeAttemptStore: ObservableObject, DailyChallengeAttemptStoreProtocol {
    /// UserDefaults 保存時のキー
    /// - Important: バージョンを明記しておくことで将来のスキーマ変更に備える
    private enum StorageKey {
        /// 本日の挑戦状況（JSON エンコードした `State` を格納）
        static let state = "daily_challenge_attempt_state_v2" // JSON で `State` を保存
    }

    /// デバッグ無制限モードの保存に利用するキー
    private static let debugUnlimitedStorageKey = "daily_challenge_debug_unlimited_v1"

    /// 日付キーを生成する際のフォーマット
    private enum DateFormat {
        /// `yyyy-MM-dd` 形式で UTC 日付を表現する
        static let pattern = "yyyy-MM-dd"
    }

    /// 最大付与可能なリワード広告回数（仕様で 3 回）
    let maximumRewardedAttempts: Int = 3

    /// UserDefaults 保存用の状態
    private struct State: Codable {
        /// バリアントごとの保存キー
        enum VariantKey: String, Codable, CaseIterable {
            case fixed
            case random

            /// `DailyChallengeDefinition.Variant` から保存用キーへ変換する
            /// - Parameter variant: 固定/ランダムいずれかのバリアント
            init(variant: DailyChallengeDefinition.Variant) {
                switch variant {
                case .fixed:
                    self = .fixed
                case .random:
                    self = .random
                }
            }

            /// 保存用キーから `DailyChallengeDefinition.Variant` へ戻す
            var variant: DailyChallengeDefinition.Variant {
                switch self {
                case .fixed:
                    return .fixed
                case .random:
                    return .random
                }
            }

            /// ログ出力時に利用する日本語ラベル
            var debugLabel: String {
                switch self {
                case .fixed:
                    return "固定"
                case .random:
                    return "ランダム"
                }
            }
        }

        /// バリアント単位の挑戦状況
        struct VariantAttempts: Codable {
            /// 消費済み挑戦回数
            var usedAttempts: Int
            /// リワード広告で付与済みの回数
            var rewardedAttemptsGranted: Int

            init(usedAttempts: Int = 0, rewardedAttemptsGranted: Int = 0) {
                self.usedAttempts = usedAttempts
                self.rewardedAttemptsGranted = rewardedAttemptsGranted
            }
        }

        /// UTC 基準の日付キー（例: 2025-05-25）
        let dateKey: String
        /// バリアントごとの挑戦状況
        var variants: [VariantKey: VariantAttempts]

        init(dateKey: String, variants: [VariantKey: VariantAttempts] = [:]) {
            self.dateKey = dateKey
            self.variants = variants
            normalizeVariants()
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            dateKey = try container.decode(String.self, forKey: .dateKey)
            variants = try container.decodeIfPresent([VariantKey: VariantAttempts].self, forKey: .variants) ?? [:]
            normalizeVariants()
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(dateKey, forKey: .dateKey)
            try container.encode(variants, forKey: .variants)
        }

        /// 必要な全バリアント分の状態が揃っているか確認し、不足していれば 0 初期値で補完する
        mutating func normalizeVariants() {
            for key in VariantKey.allCases where variants[key] == nil {
                variants[key] = VariantAttempts()
            }
        }

        /// 指定バリアントの状態を取得する（存在しない場合はゼロ初期値を返す）
        func variantState(for key: VariantKey) -> VariantAttempts {
            variants[key] ?? VariantAttempts()
        }

        /// 指定バリアントの状態を更新する
        mutating func updateVariantState(_ value: VariantAttempts, for key: VariantKey) {
            variants[key] = value
        }

        private enum CodingKeys: String, CodingKey {
            case dateKey
            case variants
        }
    }

    /// 現在の状態（更新時に `updatePublishedValues()` を手動で呼び出す）
    private var state: State

    /// 現在の UTC 日付キーを生成するためのフォーマッタ
    private let dateFormatter: DateFormatter
    /// 永続化先 UserDefaults（テスト注入のため DI 対応）
    private let userDefaults: UserDefaults
    /// 現在日時を取得するクロージャ（テストで任意の日時を差し替える）
    private let nowProvider: () -> Date

    /// 残り挑戦回数をバリアント別に公開するディクショナリ
    /// - Note: `remainingAttempts(for:)` や `updatePublishedValues()` など同一クラス内のメソッドからのみ参照しているため、`private` 指定で外部へ公開せずとも挙動は変わらない
    @Published private var remainingAttemptsByVariant: [State.VariantKey: Int]
    /// リワード広告による付与済み回数をバリアント別に公開するディクショナリ
    /// - Note: こちらも `rewardedAttemptsGranted(for:)` や `updatePublishedValues()` など内部利用に限定されているため `private` 化しても UI 連携に影響しない
    @Published private var rewardedAttemptsGrantedByVariant: [State.VariantKey: Int]
    /// デバッグ無制限モードが有効かどうか
    @Published private(set) var isDebugUnlimitedEnabled: Bool

    init(
        userDefaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = { Date() }
    ) {
        self.userDefaults = userDefaults
        self.nowProvider = nowProvider

        // UTC（協定世界時）で日付を判定するため、TimeZone(secondsFromGMT: 0) をセットしたカレンダーを採用
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt

        // `yyyy-MM-dd` 形式で日付キーを生成するフォーマッタを用意
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = DateFormat.pattern
        self.dateFormatter = formatter

        // 起動時に現在日付の状態を復元し、必要なら永続化対象かを判断
        let currentDateKey = formatter.string(from: nowProvider())
        let initialState: State
        var shouldPersistInitialState = false

        if let data = userDefaults.data(forKey: StorageKey.state) {
            do {
                let decoded = try JSONDecoder().decode(State.self, from: data)
                if decoded.dateKey == currentDateKey {
                    initialState = decoded
                    debugLog("DailyChallengeAttemptStore: 保存済みの挑戦状況を復元しました (dateKey: \(decoded.dateKey))")
                } else {
                    initialState = State(dateKey: currentDateKey)
                    shouldPersistInitialState = true
                    debugLog("DailyChallengeAttemptStore: 日付が変わっていたため挑戦回数をリセットしました")
                }
            } catch {
                initialState = State(dateKey: currentDateKey)
                shouldPersistInitialState = true
                debugError(error, message: "DailyChallengeAttemptStore: 復元に失敗したため状態を初期化しました")
            }
        } else {
            initialState = State(dateKey: currentDateKey)
            shouldPersistInitialState = true
            debugLog("DailyChallengeAttemptStore: 保存データが無かったため本日の挑戦状況を新規作成しました")
        }

        // Published プロパティの初期値は空ディクショナリとしておき、直後に `updatePublishedValues()` で埋める
        self.state = initialState
        self.remainingAttemptsByVariant = [:]
        self.rewardedAttemptsGrantedByVariant = [:]
        self.isDebugUnlimitedEnabled = userDefaults.bool(forKey: Self.debugUnlimitedStorageKey)
        updatePublishedValues()

        if shouldPersistInitialState {
            // 初期状態作成・更新が発生したケースのみ永続化を行う
            persistState()
        }
    }

    /// 指定バリアントの残量を返す
    func remainingAttempts(for variant: DailyChallengeDefinition.Variant) -> Int {
        let key = State.VariantKey(variant: variant)
        return remainingAttemptsByVariant[key] ?? Self.computeRemainingAttempts(from: state.variantState(for: key))
    }

    /// 指定バリアントの広告付与済み回数を返す
    func rewardedAttemptsGranted(for variant: DailyChallengeDefinition.Variant) -> Int {
        let key = State.VariantKey(variant: variant)
        return rewardedAttemptsGrantedByVariant[key] ?? state.variantState(for: key).rewardedAttemptsGranted
    }

    /// 日付境界を跨いだ場合に状態を初期化する
    func refreshForCurrentDate() {
        let currentKey = dateFormatter.string(from: nowProvider())
        guard state.dateKey != currentKey else { return }
        state = State(dateKey: currentKey)
        debugLog("DailyChallengeAttemptStore: 新しい日付 (\(currentKey)) が検出されたため固定/ランダムの挑戦回数をリセットしました")
        // リセット後は Published プロパティと永続化内容を手動で同期させる
        updatePublishedValues()
        persistState()
    }

    @discardableResult
    func consumeAttempt(for variant: DailyChallengeDefinition.Variant) -> Bool {
        refreshForCurrentDate()

        if isDebugUnlimitedEnabled {
            // デバッグ無制限モードでは消費上限を撤廃し、状態更新を行わずに成功扱いとする
            debugLog("DailyChallengeAttemptStore: デバッグ無制限モードのため \(State.VariantKey(variant: variant).debugLabel) の挑戦回数消費をスキップしました")
            return true
        }

        let key = State.VariantKey(variant: variant)
        var variantState = state.variantState(for: key)
        let totalAvailable = 1 + variantState.rewardedAttemptsGranted
        guard variantState.usedAttempts < totalAvailable else {
            debugLog("DailyChallengeAttemptStore: \(key.debugLabel) の挑戦回数が上限に達しているため消費できません")
            return false
        }

        variantState.usedAttempts += 1
        state.updateVariantState(variantState, for: key)
        // 消費結果を UI とストレージへ即座に反映させる
        updatePublishedValues()
        persistState()
        debugLog("DailyChallengeAttemptStore: \(key.debugLabel) の挑戦回数を 1 消費しました (used: \(variantState.usedAttempts)/total: \(totalAvailable))")
        return true
    }

    @discardableResult
    func grantRewardedAttempt(for variant: DailyChallengeDefinition.Variant) -> Bool {
        refreshForCurrentDate()

        if isDebugUnlimitedEnabled {
            // デバッグ無制限モード時は広告視聴による加算が不要なため、常に成功を返す
            debugLog("DailyChallengeAttemptStore: デバッグ無制限モードのため \(State.VariantKey(variant: variant).debugLabel) への広告付与をスキップしました")
            return true
        }

        let key = State.VariantKey(variant: variant)
        var variantState = state.variantState(for: key)
        guard variantState.rewardedAttemptsGranted < maximumRewardedAttempts else {
            debugLog("DailyChallengeAttemptStore: \(key.debugLabel) の広告付与が上限に達しているため増加できません")
            return false
        }

        variantState.rewardedAttemptsGranted += 1
        state.updateVariantState(variantState, for: key)
        // 付与後も同様に Published プロパティと永続化内容を整合させる
        updatePublishedValues()
        persistState()
        debugLog("DailyChallengeAttemptStore: \(key.debugLabel) へ広告成功により挑戦回数を 1 追加しました (granted: \(variantState.rewardedAttemptsGranted))")
        return true
    }

    /// デバッグ用の無制限モードを永続化し、即時反映する
    func enableDebugUnlimited() {
        guard !isDebugUnlimitedEnabled else { return }
        isDebugUnlimitedEnabled = true
        userDefaults.set(true, forKey: Self.debugUnlimitedStorageKey)
        userDefaults.synchronize()
        debugLog("DailyChallengeAttemptStore: デバッグ無制限モードを有効化しました")
    }

    /// デバッグ無制限モードを解除し、通常の挑戦回数管理へ戻す
    func disableDebugUnlimited() {
        // 無効化操作時にのみ処理を行い、不要な永続化を避ける
        guard isDebugUnlimitedEnabled else { return }
        isDebugUnlimitedEnabled = false
        userDefaults.set(false, forKey: Self.debugUnlimitedStorageKey)
        userDefaults.synchronize()
        debugLog("DailyChallengeAttemptStore: デバッグ無制限モードを無効化しました")
    }

    // MARK: - 内部処理
    private func updatePublishedValues() {
        var remaining: [State.VariantKey: Int] = [:]
        var rewarded: [State.VariantKey: Int] = [:]
        for key in State.VariantKey.allCases {
            let variantState = state.variantState(for: key)
            remaining[key] = Self.computeRemainingAttempts(from: variantState)
            rewarded[key] = variantState.rewardedAttemptsGranted
        }
        remainingAttemptsByVariant = remaining
        rewardedAttemptsGrantedByVariant = rewarded
    }

    private func persistState() {
        do {
            let data = try JSONEncoder().encode(state)
            userDefaults.set(data, forKey: StorageKey.state)
            userDefaults.synchronize()
        } catch {
            debugError(error, message: "DailyChallengeAttemptStore: 永続化に失敗しました")
        }
    }

    private static func computeRemainingAttempts(from state: State.VariantAttempts) -> Int {
        let total = 1 + state.rewardedAttemptsGranted
        return max(0, total - state.usedAttempts)
    }
}

private extension TimeZone {
    /// GMT (UTC±0) の TimeZone を安全に取得するためのヘルパー
    static var gmt: TimeZone {
        TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "GMT") ?? .current
    }
}
