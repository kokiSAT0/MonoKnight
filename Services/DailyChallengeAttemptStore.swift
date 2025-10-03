import Foundation
import Combine

/// デイリーチャレンジの挑戦回数を永続化し、UI と同期するためのストア
/// - Important: `@MainActor` を明示して UI スレッド以外からの更新を防ぎ、Swift Concurrency の警告を抑止する。
@MainActor
final class DailyChallengeAttemptStore: ObservableObject {
    /// 現在残っている挑戦回数
    @Published private(set) var remainingAttempts: Int
    /// 現在の定義で到達可能な最大ストック数
    @Published private(set) var maximumAttempts: Int
    /// 前回同期した定義 ID
    @Published private(set) var activeDefinitionID: String?

    /// UserDefaults へ保存する際に利用するキー
    private enum StorageKey {
        static let remainingAttempts = "daily_challenge_remaining_attempts"
        static let maximumAttempts = "daily_challenge_max_attempts"
        static let activeDefinitionID = "daily_challenge_active_definition_id"
    }

    /// データ保存先
    private let userDefaults: UserDefaults

    /// 初期化時に既存データを読み出す
    /// - Parameters:
    ///   - userDefaults: 保存に利用する `UserDefaults`
    ///   - initialDefinition: 起動直後に同期しておきたい定義（任意）
    init(userDefaults: UserDefaults = .standard,
         initialDefinition: DailyChallengeDefinition? = nil) {
        self.userDefaults = userDefaults
        let storedRemaining = userDefaults.object(forKey: StorageKey.remainingAttempts) as? Int
        let storedMaximum = userDefaults.object(forKey: StorageKey.maximumAttempts) as? Int
        let storedDefinition = userDefaults.string(forKey: StorageKey.activeDefinitionID)

        self.remainingAttempts = storedRemaining ?? 0
        self.maximumAttempts = storedMaximum ?? 0
        self.activeDefinitionID = storedDefinition

        if let definition = initialDefinition {
            synchronize(with: definition)
        }
    }

    /// 現在の定義に応じてストック数を更新する
    /// - Parameter definition: 適用したい日替わり定義
    /// - Returns: 新しい定義が適用され、リセットが発生した場合は true
    @discardableResult
    func synchronize(with definition: DailyChallengeDefinition) -> Bool {
        let shouldReset = activeDefinitionID != definition.id
        activeDefinitionID = definition.id
        maximumAttempts = definition.maximumAttemptStock
        if shouldReset {
            remainingAttempts = definition.baseAttemptsPerDay
        } else {
            remainingAttempts = min(remainingAttempts, definition.maximumAttemptStock)
        }
        persist()
        return shouldReset
    }

    /// 挑戦開始時に回数を消費する
    /// - Returns: 消費できた場合は true。残り回数が 0 の場合は false。
    @discardableResult
    func consumeAttempt() -> Bool {
        guard remainingAttempts > 0 else { return false }
        remainingAttempts -= 1
        persist()
        return true
    }

    /// 広告視聴などで挑戦回数を補充する
    /// - Parameters:
    ///   - amount: 追加する回数
    ///   - maximum: 上限となるストック数
    /// - Returns: 実際に増加した回数（上限に達している場合は 0）
    @discardableResult
    func grantAdditionalAttempts(amount: Int, maximum: Int) -> Int {
        guard amount > 0 else { return 0 }
        let previous = remainingAttempts
        maximumAttempts = maximum
        remainingAttempts = min(maximum, remainingAttempts + amount)
        persist()
        return remainingAttempts - previous
    }

    /// 現在の残り回数が 0 かどうか
    var isExhausted: Bool { remainingAttempts <= 0 }

    /// 現在のストックが上限へ達しているかどうか
    var isAtMaximumStock: Bool { remainingAttempts >= maximumAttempts }

    /// データを UserDefaults へ保存
    private func persist() {
        userDefaults.set(remainingAttempts, forKey: StorageKey.remainingAttempts)
        userDefaults.set(maximumAttempts, forKey: StorageKey.maximumAttempts)
        if let activeDefinitionID {
            userDefaults.set(activeDefinitionID, forKey: StorageKey.activeDefinitionID)
        } else {
            userDefaults.removeObject(forKey: StorageKey.activeDefinitionID)
        }
    }
}
