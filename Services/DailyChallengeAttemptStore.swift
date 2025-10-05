import Foundation
import Combine
import SwiftUI
import SharedSupport // ログユーティリティを活用するため追加

// MARK: - 日替わりチャレンジ挑戦回数の公開インターフェース
/// UI 全体から挑戦回数の残量や付与処理を扱えるようにするためのプロトコル
/// - Note: `ObservableObject` に準拠しているため、SwiftUI の `@EnvironmentObject` としても利用できる
@MainActor
/// - Note: `ObservableObjectPublisher` を明示することで `objectWillChange` を型消去経由でも購読可能にする
protocol DailyChallengeAttemptStoreProtocol: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
    /// 残り挑戦回数（無料 1 回 + リワード広告による加算分 - 消費済み回数）
    var remainingAttempts: Int { get }
    /// その日のリワード広告によって付与済みの回数
    var rewardedAttemptsGranted: Int { get }
    /// 1 日あたり付与できるリワード広告ボーナス回数の上限（仕様で 3 回）
    var maximumRewardedAttempts: Int { get }
    /// デバッグ用の無制限フラグが有効かどうか
    var isDebugUnlimitedEnabled: Bool { get }

    /// UTC 日付の境界を跨いだ場合に状態を初期化する
    func refreshForCurrentDate()
    /// 残り挑戦回数を 1 消費し、成功したかを返す
    @discardableResult
    func consumeAttempt() -> Bool
    /// リワード広告視聴が成功した際に 1 回分の挑戦回数を付与する
    @discardableResult
    func grantRewardedAttempt() -> Bool
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
    /// `objectWillChange` を購読し Published プロパティへ反映するためのストア
    private var cancellable: AnyCancellable?

    /// 残り挑戦回数を公開（Published で SwiftUI へ伝播）
    @Published private(set) var remainingAttempts: Int
    /// 付与済みリワード回数
    @Published private(set) var rewardedAttemptsGranted: Int
    /// 仕様で定めた 1 日あたりの付与上限
    let maximumRewardedAttempts: Int
    /// デバッグ無制限モードの有効/無効
    @Published private(set) var isDebugUnlimitedEnabled: Bool

    init(base: any DailyChallengeAttemptStoreProtocol) {
        self.base = base
        self.remainingAttempts = base.remainingAttempts
        self.rewardedAttemptsGranted = base.rewardedAttemptsGranted
        self.maximumRewardedAttempts = base.maximumRewardedAttempts
        self.isDebugUnlimitedEnabled = base.isDebugUnlimitedEnabled

        // objectWillChange を購読して最新値を同期
        cancellable = base.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // base から取得した最新値をローカル変数へ退避して比較を行う
                let latestRemainingAttempts = base.remainingAttempts
                if self.remainingAttempts != latestRemainingAttempts {
                    // 差分がある場合のみ Published プロパティを更新する
                    self.remainingAttempts = latestRemainingAttempts
                }

                let latestRewardedAttempts = base.rewardedAttemptsGranted
                if self.rewardedAttemptsGranted != latestRewardedAttempts {
                    // 付与済み回数も差分が存在するときのみ更新を行い再描画ループを防止する
                    self.rewardedAttemptsGranted = latestRewardedAttempts
                }

                let latestDebugFlag = base.isDebugUnlimitedEnabled
                if self.isDebugUnlimitedEnabled != latestDebugFlag {
                    // デバッグ無制限モードの状態が変化した場合のみ Published を更新する
                    self.isDebugUnlimitedEnabled = latestDebugFlag
                }
            }
        }
    }

    func refreshForCurrentDate() {
        base.refreshForCurrentDate()
        synchronizeAfterAsyncChange()
    }

    @discardableResult
    func consumeAttempt() -> Bool {
        let result = base.consumeAttempt()
        synchronizeAfterAsyncChange()
        return result
    }

    @discardableResult
    func grantRewardedAttempt() -> Bool {
        let result = base.grantRewardedAttempt()
        synchronizeAfterAsyncChange()
        return result
    }

    func enableDebugUnlimited() {
        base.enableDebugUnlimited()
        synchronizeAfterAsyncChange()
    }

    func disableDebugUnlimited() {
        base.disableDebugUnlimited()
        synchronizeAfterAsyncChange()
    }

    /// `base` 側の値が変化した直後にメインアクターで同期する
    private func synchronizeAfterAsyncChange() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // base 側の状態をローカル変数へ取得し、差分が存在する場合のみ代入を実施する
            let latestRemainingAttempts = base.remainingAttempts
            if self.remainingAttempts != latestRemainingAttempts {
                // 差分が無い場合は代入をスキップして不要な objectWillChange 通知を抑制する
                self.remainingAttempts = latestRemainingAttempts
            }

            let latestRewardedAttempts = base.rewardedAttemptsGranted
            if self.rewardedAttemptsGranted != latestRewardedAttempts {
                // 差分があるケースのみ更新して無限再描画やログ増加を防ぐ
                self.rewardedAttemptsGranted = latestRewardedAttempts
            }

            let latestDebugFlag = base.isDebugUnlimitedEnabled
            if self.isDebugUnlimitedEnabled != latestDebugFlag {
                // デバッグフラグの変更も同期し、設定画面からの切り替えを即時反映する
                self.isDebugUnlimitedEnabled = latestDebugFlag
            }
        }
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

    /// 最大付与可能なリワード広告回数（仕様で 3 回）
    let maximumRewardedAttempts: Int = 3

    /// UserDefaults 保存用の状態
    private struct State: Codable {
        /// UTC 基準の日付キー（例: 2025-05-25）
        let dateKey: String
        /// その日に消費した挑戦回数
        var usedAttempts: Int
        /// その日にリワード広告で付与済みの回数
        var rewardedAttemptsGranted: Int
    }

    /// 現在の状態（更新時に `updatePublishedValues()` を手動で呼び出す）
    private var state: State

    /// 現在の UTC 日付キーを生成するためのフォーマッタ
    private let dateFormatter: DateFormatter
    /// 永続化先 UserDefaults（テスト注入のため DI 対応）
    private let userDefaults: UserDefaults
    /// 現在日時を取得するクロージャ（テストで任意の日時を差し替える）
    private let nowProvider: () -> Date

    /// 残り挑戦回数（Published で公開）
    @Published private(set) var remainingAttempts: Int
    /// リワード広告による付与済み回数（Published で公開）
    @Published private(set) var rewardedAttemptsGranted: Int
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
                    initialState = State(dateKey: currentDateKey, usedAttempts: 0, rewardedAttemptsGranted: 0)
                    shouldPersistInitialState = true
                    debugLog("DailyChallengeAttemptStore: 日付が変わっていたため挑戦回数をリセットしました")
                }
            } catch {
                initialState = State(dateKey: currentDateKey, usedAttempts: 0, rewardedAttemptsGranted: 0)
                shouldPersistInitialState = true
                debugError(error, message: "DailyChallengeAttemptStore: 復元に失敗したため状態を初期化しました")
            }
        } else {
            initialState = State(dateKey: currentDateKey, usedAttempts: 0, rewardedAttemptsGranted: 0)
            shouldPersistInitialState = true
            debugLog("DailyChallengeAttemptStore: 保存データが無かったため本日の挑戦状況を新規作成しました")
        }

        // 格納プロパティの初期化順序を明示的に統一（state → remainingAttempts → rewardedAttemptsGranted）
        self.state = initialState
        self.remainingAttempts = Self.computeRemainingAttempts(from: initialState)
        self.rewardedAttemptsGranted = initialState.rewardedAttemptsGranted
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
        state = State(dateKey: currentKey, usedAttempts: 0, rewardedAttemptsGranted: 0)
        debugLog("DailyChallengeAttemptStore: 新しい日付 (\(currentKey)) が検出されたため挑戦回数をリセットしました")
        // リセット後は Published プロパティと永続化内容を手動で同期させる
        updatePublishedValues()
        persistState()
    }

    @discardableResult
    func consumeAttempt() -> Bool {
        refreshForCurrentDate()

        if isDebugUnlimitedEnabled {
            // デバッグ無制限モードでは消費上限を撤廃し、状態更新を行わずに成功扱いとする
            debugLog("DailyChallengeAttemptStore: デバッグ無制限モードのため挑戦回数消費をスキップしました")
            return true
        }

        let totalAvailable = 1 + state.rewardedAttemptsGranted
        guard state.usedAttempts < totalAvailable else {
            debugLog("DailyChallengeAttemptStore: 挑戦回数の上限に達しているため消費できません")
            return false
        }

        state.usedAttempts += 1
        // 消費結果を UI とストレージへ即座に反映させる
        updatePublishedValues()
        persistState()
        debugLog("DailyChallengeAttemptStore: 挑戦回数を 1 消費しました (used: \(state.usedAttempts)/total: \(totalAvailable))")
        return true
    }

    @discardableResult
    func grantRewardedAttempt() -> Bool {
        refreshForCurrentDate()

        if isDebugUnlimitedEnabled {
            // デバッグ無制限モード時は広告視聴による加算が不要なため、常に成功を返す
            debugLog("DailyChallengeAttemptStore: デバッグ無制限モードのため広告付与をスキップしました")
            return true
        }

        guard state.rewardedAttemptsGranted < maximumRewardedAttempts else {
            debugLog("DailyChallengeAttemptStore: リワード広告による付与上限に達しているため増加できません")
            return false
        }

        state.rewardedAttemptsGranted += 1
        // 付与後も同様に Published プロパティと永続化内容を整合させる
        updatePublishedValues()
        persistState()
        debugLog("DailyChallengeAttemptStore: リワード広告成功により挑戦回数を 1 追加しました (granted: \(state.rewardedAttemptsGranted))")
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
        remainingAttempts = Self.computeRemainingAttempts(from: state)
        rewardedAttemptsGranted = state.rewardedAttemptsGranted
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

    private static func computeRemainingAttempts(from state: State) -> Int {
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
