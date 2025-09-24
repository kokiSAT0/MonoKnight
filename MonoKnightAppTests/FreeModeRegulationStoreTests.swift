import Foundation
import Testing
import Game
@testable import MonoKnightApp

// MARK: - テスト用ユーティリティ
/// ユニットテストごとに独立した UserDefaults スイートを提供するヘルパー
/// - Important: 各テストケースで `tearDown()` を呼び出してクリーンアップすること
private struct IsolatedUserDefaults {
    /// 一時的なスイート名（UUID を含めて衝突を回避）
    let suiteName: String
    /// 実際にテストへ注入する UserDefaults インスタンス
    let userDefaults: UserDefaults

    /// 新しい一時スイートを生成し、初期状態をクリアする
    init?() {
        // ランダムな UUID を付与してテスト並列実行時の衝突を防ぐ
        self.suiteName = "FreeModeRegulationStoreTests." + UUID().uuidString
        // 指定したスイート名で UserDefaults を生成できなければテスト続行不可
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return nil
        }
        self.userDefaults = defaults
        // 念のため既存データを全削除し、真に空の状態から検証を始める
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// テスト終了時に呼び出し、永続化データを完全に破棄する
    func tearDown() {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults.synchronize()
    }
}

// MARK: - FreeModeRegulationStore の挙動検証
struct FreeModeRegulationStoreTests {

    /// 保存データが存在しない場合にスタンダードモード相当の設定が読み込まれることを検証
    @MainActor
    @Test func storeInitializesWithStandardRegulationWhenNoSavedData() async throws {
        // テスト専用の UserDefaults を用意できなければテストをスキップ
        guard let isolatedDefaults = IsolatedUserDefaults() else {
            Issue.record("テスト用 UserDefaults の生成に失敗しました")
            return
        }
        // defer でクリーンアップを忘れないようにする
        defer { isolatedDefaults.tearDown() }

        // 保存データが無い状態でストアを初期化
        let store = FreeModeRegulationStore(userDefaults: isolatedDefaults.userDefaults)
        // フリーモード用の GameMode を生成
        let freeMode = store.makeGameMode()

        // 生成された識別子が .freeCustom 固定であることを確認
        #expect(freeMode.identifier == .freeCustom)
        // スタンダードモードと同一レギュレーションで初期化されることを保証
        #expect(freeMode.regulationSnapshot == GameMode.standard.regulationSnapshot)
    }

    /// カスタムレギュレーションへ更新した内容が UserDefaults に永続化されることを検証
    @MainActor
    @Test func storePersistsCustomRegulationAcrossInstances() async throws {
        guard let isolatedDefaults = IsolatedUserDefaults() else {
            Issue.record("テスト用 UserDefaults の生成に失敗しました")
            return
        }
        defer { isolatedDefaults.tearDown() }

        // 任意のカスタム設定を組み立てる（盤面 7×7・スタック不可など）
        let customRegulation = GameMode.Regulation(
            boardSize: 7,
            handSize: 4,
            nextPreviewCount: 2,
            allowsStacking: false,
            deckPreset: .classicalChallenge,
            spawnRule: .chooseAnyAfterPreview,
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 3,
                manualRedrawPenaltyCost: 4,
                manualDiscardPenaltyCost: 2,
                revisitPenaltyCost: 1
            )
        )

        // 1 回目のインスタンスで設定を保存
        let firstStore = FreeModeRegulationStore(userDefaults: isolatedDefaults.userDefaults)
        firstStore.update(customRegulation)

        // 2 回目のインスタンスを生成し、永続化された内容が復元されるか確認
        let reloadedStore = FreeModeRegulationStore(userDefaults: isolatedDefaults.userDefaults)
        let reloadedMode = reloadedStore.makeGameMode()

        // カスタム設定がそのまま復元されること
        #expect(reloadedMode.regulationSnapshot == customRegulation)
        // 識別子はフリーモードのまま変化しないこと
        #expect(reloadedMode.identifier == .freeCustom)
    }

    /// プリセット適用が GameMode.standard と同じ内容へ戻すことを検証
    @MainActor
    @Test func applyingPresetRestoresStandardConfiguration() async throws {
        guard let isolatedDefaults = IsolatedUserDefaults() else {
            Issue.record("テスト用 UserDefaults の生成に失敗しました")
            return
        }
        defer { isolatedDefaults.tearDown() }

        let store = FreeModeRegulationStore(userDefaults: isolatedDefaults.userDefaults)

        // 事前にカスタム設定へ変更して差分が出る状態にしておく
        store.update(GameMode.Regulation(
            boardSize: 6,
            handSize: 3,
            nextPreviewCount: 1,
            allowsStacking: false,
            deckPreset: .standard,
            spawnRule: .chooseAnyAfterPreview,
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 7,
                manualRedrawPenaltyCost: 6,
                manualDiscardPenaltyCost: 0,
                revisitPenaltyCost: 2
            )
        ))

        // スタンダードプリセットを適用
        store.applyPreset(from: .standard)
        let restored = store.makeGameMode()

        // レギュレーションがスタンダードモードと完全一致しているか確認
        #expect(restored.regulationSnapshot == GameMode.standard.regulationSnapshot)
        // 依然として識別子は .freeCustom であるため UI 側の扱いが変わらないこと
        #expect(restored.identifier == .freeCustom)
    }
}
