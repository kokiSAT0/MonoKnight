import XCTest
import SwiftUI
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

    /// ポーズメニュー用のペナルティ説明がモード設定と一致することを確認
    func testPauseMenuPenaltyItemsMatchModePenalties() {
        // 手詰まりと捨て札のみペナルティが発生するモードを用意し、ゼロの場合の表記も同時に検証する。
        let penalties = GameMode.PenaltySettings(
            deadlockPenaltyCost: 7,
            manualRedrawPenaltyCost: 0,
            manualDiscardPenaltyCost: 4,
            revisitPenaltyCost: 0
        )
        let regulation = GameMode.Regulation(
            boardSize: 5,
            handSize: 5,
            nextPreviewCount: 3,
            allowsStacking: true,
            deckPreset: .standard,
            spawnRule: .fixed(GridPoint(x: 2, y: 2)),
            penalties: penalties
        )
        let mode = GameMode(
            identifier: .freeCustom,
            displayName: "テスト用カスタムモード",
            regulation: regulation
        )
        let (viewModel, _) = makeViewModel(mode: mode)

        XCTAssertEqual(
            viewModel.pauseMenuPenaltyItems,
            [
                "手詰まり +7 手",
                "引き直し ペナルティなし",
                "捨て札 +4 手",
                "再訪ペナルティなし"
            ],
            "RootView の表記と同じ並び・文言でペナルティ説明が生成される必要があります"
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

    /// メニュー経由でタイトルへ戻る際に GameCore.reset() を呼び出さず、広告フラグのみ初期化されることを確認
    func testPerformMenuActionReturnToTitleSkipsCoreResetButResetsAdsFlag() {
        // タイトル遷移コールバックの呼び出し回数と広告リセットを検証するため、専用のスパイを注入する
        let adsService = SpyAdsService()
        var returnToTitleCallCount = 0
        let (viewModel, core) = makeViewModel(
            mode: .standard,
            adsService: adsService,
            onRequestReturnToTitle: { returnToTitleCallCount += 1 }
        )

        // reset() が動いてしまうと手数が 0 に戻るため、明確な値を設定しておき検証に利用する
        core.overrideMetricsForTesting(moveCount: 42, penaltyCount: 3, elapsedSeconds: 90)

        viewModel.performMenuAction(.returnToTitle)

        XCTAssertEqual(core.moveCount, 42, "タイトル復帰では GameCore.reset() を呼ばず手数が維持される必要があります")
        XCTAssertEqual(adsService.resetPlayFlagCallCount, 1, "タイトル復帰時に広告表示フラグの初期化が行われていません")
        XCTAssertEqual(returnToTitleCallCount, 1, "タイトル復帰の通知が親へ転送されていません")
    }

    /// 結果画面からタイトルへ戻る際も reset() が動かず、UI 状態と広告フラグのみ初期化されることを確認
    func testHandleResultReturnToTitleSkipsCoreResetButResetsAdsFlag() {
        // リザルト経由の復帰でも同じ挙動になるか、別パスを明示的に検証する
        let adsService = SpyAdsService()
        var returnToTitleCallCount = 0
        let (viewModel, core) = makeViewModel(
            mode: .standard,
            adsService: adsService,
            onRequestReturnToTitle: { returnToTitleCallCount += 1 }
        )

        core.overrideMetricsForTesting(moveCount: 55, penaltyCount: 1, elapsedSeconds: 120)
        viewModel.showingResult = true

        viewModel.handleResultReturnToTitle()

        XCTAssertEqual(core.moveCount, 55, "結果画面からのタイトル復帰でも GameCore.reset() は発火しない想定です")
        XCTAssertFalse(viewModel.showingResult, "タイトル復帰時には結果画面フラグが確実に折れている必要があります")
        XCTAssertEqual(adsService.resetPlayFlagCallCount, 1, "結果画面経由でも広告フラグの初期化が実行されていません")
        XCTAssertEqual(returnToTitleCallCount, 1, "タイトル復帰通知がルートへ届いていません")
    }

    /// ゲーム準備オーバーレイ表示中はキャンペーンタイマーが進行しないことを確認
    func testPreparationOverlayPausesTimerDuringCampaignLoading() throws {
        // UserDefaults 衝突を避けるため、テスト専用スイートを準備する
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // キャンペーン 1-1 を利用してタイマー停止挙動を検証する
        guard let campaignMode = CampaignLibrary.shared.stage(with: CampaignStageID(chapter: 1, index: 1))?.makeGameMode() else {
            XCTFail("キャンペーンモードの取得に失敗しました")
            return
        }

        let dateProvider = MutableDateProvider(now: Date(timeIntervalSince1970: 50_000))
        let (viewModel, core) = makeViewModel(
            mode: campaignMode,
            campaignProgressStore: CampaignProgressStore(userDefaults: defaults),
            dateProvider: dateProvider
        )

        // 120 秒経過した状態を再現してからローディングオーバーレイを表示する
        core.setStartDateForTesting(dateProvider.now.addingTimeInterval(-120))
        XCTAssertEqual(core.liveElapsedSecondsForTesting(asOf: dateProvider.now), 120, "前提となる経過時間の再現に失敗しました")

        viewModel.handlePreparationOverlayChange(isVisible: true)
        dateProvider.now = dateProvider.now.addingTimeInterval(60)
        XCTAssertEqual(core.liveElapsedSecondsForTesting(asOf: dateProvider.now), 120, "ローディング表示中に経過秒数が増加しています")

        viewModel.handlePreparationOverlayChange(isVisible: false)
        dateProvider.now = dateProvider.now.addingTimeInterval(30)
        XCTAssertEqual(core.liveElapsedSecondsForTesting(asOf: dateProvider.now), 150, "ローディング解除後に計測が再開されていません")
    }

    /// キャンペーンモードではポーズメニュー表示中にタイマーが停止し、ハイスコアモードでは継続することを確認
    func testPauseMenuControlsTimerOnlyForCampaignMode() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        guard let campaignMode = CampaignLibrary.shared.stage(with: CampaignStageID(chapter: 1, index: 1))?.makeGameMode() else {
            XCTFail("キャンペーンモードの取得に失敗しました")
            return
        }

        let campaignDateProvider = MutableDateProvider(now: Date(timeIntervalSince1970: 10_000))
        let (campaignViewModel, campaignCore) = makeViewModel(
            mode: campaignMode,
            campaignProgressStore: CampaignProgressStore(userDefaults: defaults),
            dateProvider: campaignDateProvider
        )

        // 100 秒経過している状態からポーズメニューを開く
        campaignCore.setStartDateForTesting(campaignDateProvider.now.addingTimeInterval(-100))
        XCTAssertEqual(campaignCore.liveElapsedSecondsForTesting(asOf: campaignDateProvider.now), 100, "キャンペーン初期計測値が一致しません")

        campaignViewModel.presentPauseMenu()
        campaignDateProvider.now = campaignDateProvider.now.addingTimeInterval(200)
        XCTAssertEqual(campaignCore.liveElapsedSecondsForTesting(asOf: campaignDateProvider.now), 100, "キャンペーンの一時停止中に経過時間が進んでいます")

        // メニューを閉じると再び計測が進む
        campaignViewModel.setPauseMenuPresentedForTesting(false)
        campaignDateProvider.now = campaignDateProvider.now.addingTimeInterval(10)
        XCTAssertEqual(campaignCore.liveElapsedSecondsForTesting(asOf: campaignDateProvider.now), 110, "キャンペーンでポーズ解除後の再開が期待通りではありません")

        // ハイスコアモードではポーズメニュー表示中も計測が継続する
        let scoreDateProvider = MutableDateProvider(now: Date(timeIntervalSince1970: 20_000))
        let (scoreViewModel, scoreCore) = makeViewModel(
            mode: .standard,
            campaignProgressStore: CampaignProgressStore(userDefaults: defaults),
            dateProvider: scoreDateProvider
        )

        scoreCore.setStartDateForTesting(scoreDateProvider.now.addingTimeInterval(-100))
        XCTAssertEqual(scoreCore.liveElapsedSecondsForTesting(asOf: scoreDateProvider.now), 100, "ハイスコア初期計測値が一致しません")

        scoreViewModel.presentPauseMenu()
        scoreDateProvider.now = scoreDateProvider.now.addingTimeInterval(200)
        XCTAssertEqual(scoreCore.liveElapsedSecondsForTesting(asOf: scoreDateProvider.now), 300, "ハイスコアモードではポーズ中も計測が継続する想定です")
    }

    /// scenePhase の変化によるタイマー制御がキャンペーン専用であることを確認
    func testScenePhasePauseAppliesOnlyToCampaignMode() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        guard let campaignMode = CampaignLibrary.shared.stage(with: CampaignStageID(chapter: 1, index: 1))?.makeGameMode() else {
            XCTFail("キャンペーンモードの取得に失敗しました")
            return
        }

        let campaignDateProvider = MutableDateProvider(now: Date(timeIntervalSince1970: 30_000))
        let (campaignViewModel, campaignCore) = makeViewModel(
            mode: campaignMode,
            campaignProgressStore: CampaignProgressStore(userDefaults: defaults),
            dateProvider: campaignDateProvider
        )

        campaignCore.setStartDateForTesting(campaignDateProvider.now.addingTimeInterval(-80))
        XCTAssertEqual(campaignCore.liveElapsedSecondsForTesting(asOf: campaignDateProvider.now), 80, "キャンペーン初期計測値が一致しません")

        campaignViewModel.handleScenePhaseChange(.background)
        campaignDateProvider.now = campaignDateProvider.now.addingTimeInterval(120)
        XCTAssertEqual(campaignCore.liveElapsedSecondsForTesting(asOf: campaignDateProvider.now), 80, "バックグラウンド中にキャンペーンタイマーが進行しています")

        campaignViewModel.handleScenePhaseChange(.active)
        XCTAssertTrue(campaignViewModel.isPauseMenuPresented, "バックグラウンド復帰後はポーズメニューが自動表示される必要があります")

        campaignDateProvider.now = campaignDateProvider.now.addingTimeInterval(40)
        XCTAssertEqual(campaignCore.liveElapsedSecondsForTesting(asOf: campaignDateProvider.now), 80, "ポーズメニューを閉じるまではタイマーが再開されてはいけません")

        campaignViewModel.setPauseMenuPresentedForTesting(false)
        campaignDateProvider.now = campaignDateProvider.now.addingTimeInterval(30)
        XCTAssertEqual(campaignCore.liveElapsedSecondsForTesting(asOf: campaignDateProvider.now), 110, "ポーズ解除後にタイマーが再開されていません")

        let scoreDateProvider = MutableDateProvider(now: Date(timeIntervalSince1970: 40_000))
        let (scoreViewModel, scoreCore) = makeViewModel(
            mode: .standard,
            campaignProgressStore: CampaignProgressStore(userDefaults: defaults),
            dateProvider: scoreDateProvider
        )

        scoreCore.setStartDateForTesting(scoreDateProvider.now.addingTimeInterval(-50))
        XCTAssertEqual(scoreCore.liveElapsedSecondsForTesting(asOf: scoreDateProvider.now), 50, "ハイスコア初期計測値が一致しません")

        scoreViewModel.handleScenePhaseChange(.background)
        scoreDateProvider.now = scoreDateProvider.now.addingTimeInterval(100)
        XCTAssertEqual(scoreCore.liveElapsedSecondsForTesting(asOf: scoreDateProvider.now), 150, "ハイスコアモードはバックグラウンドでも計測継続する想定です")
    }

    /// テストで使い回す ViewModel と GameCore の組み合わせを生成するヘルパー
    private func makeViewModel(
        mode: GameMode,
        adsService: AdsServiceProtocol = DummyAdsService(),
        onRequestReturnToTitle: (() -> Void)? = nil,
        campaignProgressStore: CampaignProgressStore = CampaignProgressStore(),
        dateProvider: MutableDateProvider? = nil
    ) -> (GameViewModel, GameCore) {
        let core = GameCore(mode: mode)
        if mode.requiresSpawnSelection {
            // テストがスポーン選択待機で停止しないように、盤面中央へスポーンを確定させる
            let spawnPoint = mode.initialSpawnPoint ?? GridPoint(x: mode.boardSize / 2, y: mode.boardSize / 2)
            core.simulateSpawnSelection(forTesting: spawnPoint)
        }

        let interfaces = GameModuleInterfaces { _ in core }
        let resolvedDateProvider = dateProvider ?? MutableDateProvider(now: Date())
        let viewModel = GameViewModel(
            mode: mode,
            gameInterfaces: interfaces,
            gameCenterService: DummyGameCenterService(),
            adsService: adsService,
            campaignProgressStore: campaignProgressStore,
            onRequestGameCenterSignIn: nil,
            onRequestReturnToTitle: onRequestReturnToTitle,
            onRequestStartCampaignStage: nil,
            currentDateProvider: { resolvedDateProvider.now }
        )
        return (viewModel, core)
    }

    /// 任意の現在時刻を提供するためのテスト専用クラス
    private final class MutableDateProvider {
        /// 現在時刻として利用する値
        var now: Date

        init(now: Date) {
            self.now = now
        }
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
    func showRewardedAd() async -> Bool { true }
    func requestTrackingAuthorization() async {}
    func requestConsentIfNeeded() async {}
    func refreshConsentStatus() async {}
}

/// resetPlayFlag の呼び出し回数を追跡するテスト専用スパイ
@MainActor
private final class SpyAdsService: AdsServiceProtocol {
    /// resetPlayFlag が何度呼ばれたかを確認するためのカウンタ
    private(set) var resetPlayFlagCallCount = 0

    func showInterstitial() {}

    func resetPlayFlag() {
        // タイトル復帰時の挙動を確認するため、呼び出し回数を加算しておく
        resetPlayFlagCallCount += 1
    }

    func disableAds() {}
    func showRewardedAd() async -> Bool { true }
    func requestTrackingAuthorization() async {}
    func requestConsentIfNeeded() async {}
    func refreshConsentStatus() async {}
}
