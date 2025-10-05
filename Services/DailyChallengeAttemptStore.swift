import Foundation
import Combine
import SwiftUI
import Game // DailyChallengeDefinition を参照するため追加
import SharedSupport // ログユーティリティを活用するため追加

// MARK: - 日替わりチャレンジ挑戦回数の公開インターフェース
/// UI 全体から挑戦回数の残量や付与処理を扱えるようにするためのプロトコル
/// - Note: `ObservableObject` に準拠しているため、SwiftUI の `@EnvironmentObject` としても利用できる
@MainActor
/// - Note: `ObservableObjectPublisher` を明示することで `objectWillChange` を型消去経由でも購読可能にする
protocol DailyChallengeAttemptStoreProtocol: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    /// 指定したバリアントにおける残り挑戦回数（無料 1 回 + リワード広告による加算分 - 消費済み回数）
    /// - Parameter variant: 固定版かランダム版かを示す種別
    func remainingAttempts(for variant: DailyChallengeDefinition.Variant) -> Int
    /// 指定したバリアントでリワード広告によって付与済みの回数
    /// - Parameter variant: 固定版かランダム版かを示す種別
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
    /// 実体となるストアを保持
    private let base: any DailyChallengeAttemptStoreProtocol
    /// `objectWillChange` を購読して自身の通知へ橋渡しするためのキャンセラ
    private var cancellable: AnyCancellable?

    /// 1 日あたりのリワード広告付与上限（元ストアをそのまま参照）
    let maximumRewardedAttempts: Int

    /// - Parameter base: 実装を差し替え可能にするための具象ストア
    init(base: any DailyChallengeAttemptStoreProtocol) {
        self.base = base
        self.maximumRewardedAttempts = base.maximumRewardedAttempts

        // 元ストアで変更が起きたら、自身の objectWillChange も伝播させる
        cancellable = base.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.objectWillChange.send()
            }
        }
    }

    func remainingAttempts(for variant: DailyChallengeDefinition.Variant) -> Int {
        base.remainingAttempts(for: variant)
    }

    func rewardedAttemptsGranted(for variant: DailyChallengeDefinition.Variant) -> Int {
        base.rewardedAttemptsGranted(for: variant)
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
        static let state = "daily_challenge_attempt_state_v1" // JSON で `State` を保存
    }

    /// デバッグ無制限モードの保存に利用するキー
    private static let debugUnlimitedStorageKey = "daily_challenge_debug_unlimited_v1"

    /// 日付キーを生成する際のフォーマット
    private enum DateFormat {
        /// `yyyy-MM-dd` 形式で UTC 日付を表現する
        static let pattern = "yyyy-MM-dd"
    }

    /// バリアントごとの挑戦状況を辞書に保存する際のキー
    private enum VariantKey: String, Codable, CaseIterable {
        case fixed
        case random

        /// `DailyChallengeDefinition.Variant` から辞書キーへ変換する
        /// - Parameter variant: 固定版かランダム版かを示す種別
        init(variant: DailyChallengeDefinition.Variant) {
            switch variant {
            case .fixed:
                self = .fixed
            case .random:
                self = .random
            }
        }
    }

    /// バリアント単位の挑戦記録
    private struct VariantRecord: Codable {
        /// 当日消費した挑戦回数
        var usedAttempts: Int
        /// 当日リワード広告で付与した回数
        var rewardedAttemptsGranted: Int

        init(usedAttempts: Int = 0, rewardedAttemptsGranted: Int = 0) {
            self.usedAttempts = usedAttempts
            self.rewardedAttemptsGranted = rewardedAttemptsGranted
        }
    }

    /// UserDefaults 保存用の状態
    private struct State: Codable {
        /// UTC 基準の日付キー（例: 2025-05-25）
        var dateKey: String
        /// バリアントごとの挑戦記録
        private var records: [VariantKey: VariantRecord]

        init(dateKey: String, records: [VariantKey: VariantRecord] = [:]) {
            self.dateKey = dateKey
            self.records = records
            ensureAllVariantsInitialized()
        }

        /// バリアント別の記録を常に用意しておき、欠損データを防ぐ
        mutating func ensureAllVariantsInitialized() {
            for key in VariantKey.allCases where records[key] == nil {
                records[key] = VariantRecord()
            }
        }

        /// 指定したバリアントの記録を取得する
        func record(for key: VariantKey) -> VariantRecord {
            records[key] ?? VariantRecord()
        }

        /// 指定したバリアントの記録を更新する
        mutating func updateRecord(for key: VariantKey, mutate: (inout VariantRecord) -> Void) {
            ensureAllVariantsInitialized()
            var record = records[key] ?? VariantRecord()
            mutate(&record)
            records[key] = record
        }
    }

    /// 最大付与可能なリワード広告回数（仕様で 3 回）
    let maximumRewardedAttempts: Int = 3

    /// 現在の状態（更新時に `updatePublishedValues()` を手動で呼び出す）
    private var state: State

    /// 現在の UTC 日付キーを生成するためのフォーマッタ
    private let dateFormatter: DateFormatter
    /// 永続化先 UserDefaults（テスト注入のため DI 対応）
    private let userDefaults: UserDefaults
    /// 現在日時を取得するクロージャ（テストで任意の日時を差し替える）
    private let nowProvider: () -> Date

    /// 状態更新を SwiftUI へ伝えるためのカウンタ（変更時にインクリメント）
    @Published private var stateVersion: Int
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
                var decoded = try JSONDecoder().decode(State.self, from: data)
                decoded.ensureAllVariantsInitialized()
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

        // 格納プロパティの初期化順序を明示的に統一（state → stateVersion → フラグ類）
        self.state = initialState
        self.stateVersion = 0
        self.isDebugUnlimitedEnabled = userDefaults.bool(forKey: Self.debugUnlimitedStorageKey)

        if shouldPersistInitialState {
            // 初期状態作成・更新が発生したケースのみ永続化を行う
            persistState()
        }
    }

    /// 日付境界を跨いだ場合に状態を初期化する
    func refreshForCurrentDate() {
        let currentKey = dateFormatter.string(from: nowProvider())
        guard state.dateKey != currentKey else { return }
        state = State(dateKey: currentKey)
        debugLog("DailyChallengeAttemptStore: 新しい日付 (\(currentKey)) が検出されたため全バリアントの挑戦回数をリセットしました")
        // リセット後は Published プロパティと永続化内容を手動で同期させる
        updatePublishedValues()
        persistState()
    }

    /// 指定バリアントの残量を計算する
    /// - Parameter variant: 固定版かランダム版かの種別
    func remainingAttempts(for variant: DailyChallengeDefinition.Variant) -> Int {
        let key = Self.variantKey(for: variant)
        let record = state.record(for: key)
        return Self.computeRemainingAttempts(from: record)
    }

    /// 指定バリアントの広告付与済み回数を返す
    /// - Parameter variant: 固定版かランダム版かの種別
    func rewardedAttemptsGranted(for variant: DailyChallengeDefinition.Variant) -> Int {
        let key = Self.variantKey(for: variant)
        return state.record(for: key).rewardedAttemptsGranted
    }

    @discardableResult
    func consumeAttempt(for variant: DailyChallengeDefinition.Variant) -> Bool {
        refreshForCurrentDate()

        if isDebugUnlimitedEnabled {
            // デバッグ無制限モードでは消費上限を撤廃し、状態更新を行わずに成功扱いとする
            debugLog("DailyChallengeAttemptStore: デバッグ無制限モードのため挑戦回数消費をスキップしました (variant: \(Self.variantLogLabel(for: variant)))")
            return true
        }

        let key = Self.variantKey(for: variant)
        let record = state.record(for: key)
        let totalAvailable = 1 + record.rewardedAttemptsGranted
        guard record.usedAttempts < totalAvailable else {
            debugLog("DailyChallengeAttemptStore: 挑戦回数の上限に達しているため消費できません (variant: \(Self.variantLogLabel(for: variant)))")
            return false
        }

        state.updateRecord(for: key) { record in
            record.usedAttempts += 1
        }
        // 消費結果を UI とストレージへ即座に反映させる
        updatePublishedValues()
        persistState()
        let updated = state.record(for: key)
        debugLog("DailyChallengeAttemptStore: 挑戦回数を 1 消費しました (variant: \(Self.variantLogLabel(for: variant)) used: \(updated.usedAttempts)/total: \(totalAvailable))")
        return true
    }

    @discardableResult
    func grantRewardedAttempt(for variant: DailyChallengeDefinition.Variant) -> Bool {
        refreshForCurrentDate()

        if isDebugUnlimitedEnabled {
            // デバッグ無制限モード時は広告視聴による加算が不要なため、常に成功を返す
            debugLog("DailyChallengeAttemptStore: デバッグ無制限モードのため広告付与をスキップしました (variant: \(Self.variantLogLabel(for: variant)))")
            return true
        }

        let key = Self.variantKey(for: variant)
        let record = state.record(for: key)
        guard record.rewardedAttemptsGranted < maximumRewardedAttempts else {
            debugLog("DailyChallengeAttemptStore: リワード広告による付与上限に達しているため増加できません (variant: \(Self.variantLogLabel(for: variant)))")
            return false
        }

        state.updateRecord(for: key) { record in
            record.rewardedAttemptsGranted += 1
        }
        // 付与後も同様に Published プロパティと永続化内容を整合させる
        updatePublishedValues()
        persistState()
        let updated = state.record(for: key)
        debugLog("DailyChallengeAttemptStore: リワード広告成功により挑戦回数を 1 追加しました (variant: \(Self.variantLogLabel(for: variant)) granted: \(updated.rewardedAttemptsGranted))")
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
        stateVersion &+= 1
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

    /// `DailyChallengeDefinition.Variant` を内部管理用キーへ変換する
    private static func variantKey(for variant: DailyChallengeDefinition.Variant) -> VariantKey {
        VariantKey(variant: variant)
    }

    /// ログ出力向けのバリアント名称
    private static func variantLogLabel(for variant: DailyChallengeDefinition.Variant) -> String {
        switch variant {
        case .fixed:
            return "固定"
        case .random:
            return "ランダム"
        }
    }

    private static func computeRemainingAttempts(from record: VariantRecord) -> Int {
        let total = 1 + record.rewardedAttemptsGranted
        return max(0, total - record.usedAttempts)
    }
}

private extension TimeZone {
    /// GMT (UTC±0) の TimeZone を安全に取得するためのヘルパー
    static var gmt: TimeZone {
        TimeZone(secondsFromGMT: 0) ?? TimeZone(identifier: "GMT") ?? .current
    }
}
