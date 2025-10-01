import XCTest
@testable import MonoKnightApp
import Game

/// GameViewModel の動作を検証するテスト群
/// - Note: ViewModel は MainActor 上での実行を前提としているため、テストメソッドにも @MainActor を付与する。
@MainActor
final class GameViewModelTests: XCTestCase {

    /// プレイ中は GameCore.liveElapsedSeconds を参照して経過時間が増加することを確認
    func testUpdateDisplayedElapsedTimeUsesLiveElapsedSecondsWhilePlaying() {
        // 120 秒前にゲームが開始された状況を再現し、リアルタイム計測の挙動を確認する。
        let targetElapsedSeconds: TimeInterval = 120
        let core = GameCore(mode: .standard)
        core.setStartDateForTesting(Date().addingTimeInterval(-targetElapsedSeconds))

        // GameModuleInterfaces 経由で上記 GameCore を注入し、サービスは最小限のダミーを渡す。
        let interfaces = GameModuleInterfaces { _ in core }
        let viewModel = GameViewModel(
            mode: .standard,
            gameInterfaces: interfaces,
            gameCenterService: DummyGameCenterService(),
            adsService: DummyAdsService(),
            onRequestReturnToTitle: nil
        )

        // liveElapsedSeconds は Int へ丸められるため、呼び出し直後の差分許容範囲を確保して検証する。
        viewModel.updateDisplayedElapsedTime()
        XCTAssertGreaterThanOrEqual(
            viewModel.displayedElapsedSeconds,
            Int(targetElapsedSeconds) - 1,
            "リアルタイム経過秒数が期待よりも小さすぎます"
        )
        XCTAssertLessThanOrEqual(
            viewModel.displayedElapsedSeconds,
            Int(targetElapsedSeconds) + 2,
            "リアルタイム経過秒数が許容範囲を超えてしまいました"
        )
    }

    /// 捨て札ボタンを押すとモードが開始されることを確認
    func testToggleManualDiscardSelectionActivatesWhenPlayable() {
        let (viewModel, core) = makeViewModel(mode: .standard)
        XCTAssertTrue(viewModel.isManualDiscardButtonEnabled, "スタンダードモードでは捨て札ボタンが有効であるべきです")
        XCTAssertFalse(core.isAwaitingManualDiscardSelection, "初期状態では捨て札モードが無効であるべきです")

        viewModel.toggleManualDiscardSelection()

        XCTAssertTrue(core.isAwaitingManualDiscardSelection, "ボタン操作で捨て札モードが有効化されていません")
    }

    /// 捨て札モード中に再度ボタンを押すと解除されることを確認
    func testToggleManualDiscardSelectionCancelsWhenAlreadyActive() {
        let (viewModel, core) = makeViewModel(mode: .standard)
        viewModel.toggleManualDiscardSelection()
        XCTAssertTrue(core.isAwaitingManualDiscardSelection, "前提として捨て札モードが開始している必要があります")

        viewModel.toggleManualDiscardSelection()

        XCTAssertFalse(core.isAwaitingManualDiscardSelection, "2 回目の操作で捨て札モードが解除されていません")
    }

    /// 手動ペナルティが進行中のみで発火し、ペナルティ量が一致することを確認
    func testRequestManualPenaltySetsPendingActionWhenPlayable() {
        let (viewModel, core) = makeViewModel(mode: .standard)
        XCTAssertNil(viewModel.pendingMenuAction, "初期状態では確認ダイアログが未設定であるべきです")

        viewModel.requestManualPenalty()

        XCTAssertEqual(
            viewModel.pendingMenuAction,
            .manualPenalty(penaltyCost: core.mode.manualRedrawPenaltyCost),
            "ペナルティ要求時の確認アクションが期待と一致しません"
        )
    }

    /// プレイ待機中は手動ペナルティの確認がセットされないことを確認
    func testRequestManualPenaltyIgnoredWhenNotPlaying() {
        let (viewModel, core) = makeViewModel(mode: .classicalChallenge)
        XCTAssertEqual(core.progress, .awaitingSpawn, "クラシカルモードではスポーン待機が初期状態です")

        viewModel.requestManualPenalty()

        XCTAssertNil(viewModel.pendingMenuAction, "プレイ開始前にペナルティ確認が設定されてはいけません")
    }

    /// キャンペーンステージを連続でクリアした場合でも次の未クリアステージを newlyUnlockedStages に保持することを確認
    func testNewlyUnlockedStagesRemainAfterClearingSameCampaignStageTwice() throws {
        // UserDefaults の衝突を避けるため、テスト専用のスイートを生成する
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let progressStore = CampaignProgressStore(userDefaults: defaults)
        let library = CampaignLibrary.shared
        let stage11ID = CampaignStageID(chapter: 1, index: 1)
        let stage12ID = CampaignStageID(chapter: 1, index: 2)

        guard
            let stage11 = library.stage(with: stage11ID),
            let stage12 = library.stage(with: stage12ID)
        else {
            XCTFail("キャンペーンステージの定義取得に失敗しました")
            return
        }

        XCTAssertFalse(progressStore.isStageUnlocked(stage12), "前提として 1-2 は初期状態でロックされている必要があります")

        let core = GameCore(mode: stage11.makeGameMode())
        let interfaces = GameModuleInterfaces { _ in core }
        let viewModel = GameViewModel(
            mode: stage11.makeGameMode(),
            gameInterfaces: interfaces,
            gameCenterService: DummyGameCenterService(),
            adsService: DummyAdsService(),
            campaignProgressStore: progressStore,
            onRequestGameCenterSignIn: nil,
            onRequestReturnToTitle: nil,
            onRequestStartCampaignStage: nil
        )

        XCTAssertTrue(viewModel.newlyUnlockedStages.isEmpty, "プレイ前は newlyUnlockedStages が空である必要があります")

        // 1 回目のクリアで次ステージが解放され、newlyUnlockedStages に含まれることを検証する
        core.overrideMetricsForTesting(moveCount: 12, penaltyCount: 0, elapsedSeconds: 80)
        viewModel.handleProgressChangeForTesting(.cleared)

        XCTAssertTrue(progressStore.isStageUnlocked(stage12), "1-1 クリア後は 1-2 が解放される想定です")
        XCTAssertEqual(viewModel.newlyUnlockedStages.map(\.id), [stage12.id], "解放直後は newlyUnlockedStages に 1-2 のみが含まれるべきです")
        XCTAssertEqual(viewModel.latestCampaignClearRecord?.stage.id, stage11.id, "最新クリア記録が 1-1 になっている必要があります")

        // 2 回目のクリアでも 1-2 を案内し続け、ボタン表示が維持されることを確認する
        core.overrideMetricsForTesting(moveCount: 10, penaltyCount: 0, elapsedSeconds: 75)
        viewModel.handleProgressChangeForTesting(.cleared)

        XCTAssertEqual(viewModel.newlyUnlockedStages.map(\.id), [stage12.id], "2 回目のクリアでも未クリアの 1-2 を案内し続ける必要があります")
    }

    /// テストで使い回す ViewModel と GameCore の組み合わせを生成するヘルパー
    private func makeViewModel(
        mode: GameMode,
        onRequestReturnToTitle: (() -> Void)? = nil
    ) -> (GameViewModel, GameCore) {
        let core = GameCore(mode: mode)
        let interfaces = GameModuleInterfaces { _ in core }
        let viewModel = GameViewModel(
            mode: mode,
            gameInterfaces: interfaces,
            gameCenterService: DummyGameCenterService(),
            adsService: DummyAdsService(),
            onRequestReturnToTitle: onRequestReturnToTitle
        )
        return (viewModel, core)
    }

    /// テスト専用の UserDefaults スイートを作成し、永続化データの混在を防ぐ
    private func makeIsolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "GameViewModelTests." + UUID().uuidString
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            XCTFail("UserDefaults スイートの生成に失敗しました")
            throw NSError(domain: "GameViewModelTests", code: -1)
        }
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}

// MARK: - テスト用ダミーサービス

/// GameCenterServiceProtocol を満たす最小限のダミー実装
@MainActor
private final class DummyGameCenterService: GameCenterServiceProtocol {
    var isAuthenticated: Bool = false
    func authenticateLocalPlayer(completion: ((Bool) -> Void)?) { completion?(true) }
    func submitScore(_ score: Int, for modeIdentifier: GameMode.Identifier) {}
    func showLeaderboard(for modeIdentifier: GameMode.Identifier) {}
}

/// AdsServiceProtocol を満たす最小限のダミー実装
@MainActor
private final class DummyAdsService: AdsServiceProtocol {
    func showInterstitial() {}
    func resetPlayFlag() {}
    func disableAds() {}
    func requestTrackingAuthorization() async {}
    func requestConsentIfNeeded() async {}
    func refreshConsentStatus() async {}
}
