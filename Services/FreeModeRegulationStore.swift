import Foundation
import SwiftUI
import Game

/// フリーモードのレギュレーションを永続化し、UI から参照・更新できるようにするストア
/// - Note: `UserDefaults` を介して JSON として保存し、アプリ再起動後も設定を復元する
@MainActor
final class FreeModeRegulationStore: ObservableObject {
    /// 保存に利用する UserDefaults のキー
    private static let storageKey = "free_mode_regulation_v1"
    /// 監視対象のレギュレーション（変更時にビューを更新する）
    @Published private(set) var regulation: GameMode.Regulation
    /// 保存先の UserDefaults
    private let userDefaults: UserDefaults

    /// 初期化時に保存済みレギュレーションを読み込み、存在しない場合はスタンダード設定を初期値とする
    /// - Parameter userDefaults: テスト時などに差し替えたい場合の注入用引数
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Self.storageKey) {
            do {
                let decoded = try JSONDecoder().decode(GameMode.Regulation.self, from: data)
                regulation = decoded
                debugLog("FreeModeRegulationStore: 保存済み設定を復元しました")
            } catch {
                regulation = GameMode.standard.regulationSnapshot
                debugError(error, message: "FreeModeRegulationStore: 復元に失敗したためスタンダードを適用")
            }
        } else {
            regulation = GameMode.standard.regulationSnapshot
            debugLog("FreeModeRegulationStore: 保存データが無いためスタンダードを初期値に設定")
        }
    }

    /// 現在のレギュレーションを別の値で更新し、ただちに永続化する
    /// - Parameter newValue: ユーザーが編集した新しい設定
    func update(_ newValue: GameMode.Regulation) {
        guard regulation != newValue else { return }
        regulation = newValue
        persist()
        debugLog("FreeModeRegulationStore: レギュレーションを更新しました")
    }

    /// 指定したプリセットモードのレギュレーションを適用し、保存する
    /// - Parameter mode: 適用したいビルトインモード
    func applyPreset(from mode: GameMode) {
        update(mode.regulationSnapshot)
        debugLog("FreeModeRegulationStore: プリセット \(mode.identifier.rawValue) を適用")
    }

    /// 現在のレギュレーションを用いた `GameMode` を生成する
    /// - Returns: フリーモードとして利用する `GameMode`
    func makeGameMode() -> GameMode {
        GameMode(identifier: .freeCustom, displayName: "フリーモード", regulation: regulation)
    }

    /// 現在の設定を JSON として UserDefaults へ保存する
    private func persist() {
        do {
            let data = try JSONEncoder().encode(regulation)
            userDefaults.set(data, forKey: Self.storageKey)
            userDefaults.synchronize()
        } catch {
            debugError(error, message: "FreeModeRegulationStore: 永続化に失敗")
        }
    }
}
