import XCTest
import SwiftUI
@testable import MonoKnightApp
@testable import Game

/// GameViewModel の動作を検証するテスト群
/// - Note: ViewModel は MainActor 上での実行を前提としているため、テストメソッドにも @MainActor を付与する。
@MainActor
final class GameViewModelTests: XCTestCase {

    /// プレイ中は GameCore.liveElapsedSeconds を参照して経過時間が増加することを確認
    func testUpdateDisplayedElapsedTimeUsesLiveElapsedSecondsWhilePlaying() {
        // 120 秒前にゲームが開始された状況を再現し、リアルタイム計測の挙動を確認する。
        let targetElapsedSeconds: TimeInterval = 120
        let core = GameCore(mode: .dungeonPlaceholder)
        core.setStartDateForTesting(Date().addingTimeInterval(-targetElapsedSeconds))

        // GameModuleInterfaces 経由で上記 GameCore を注入し、サービスは最小限のダミーを渡す。
        let interfaces = GameModuleInterfaces { _ in core }
        let viewModel = GameViewModel(
            mode: .dungeonPlaceholder,
            gameInterfaces: interfaces,
            gameCenterService: DummyGameCenterService(),
            adsService: DummyAdsService(),
            dungeonRunResumeStore: makeIsolatedDungeonRunResumeStore(),
            onRequestGameCenterSignIn: nil,
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
        let (viewModel, core) = makeViewModel(mode: legacyControlTestMode)
        XCTAssertTrue(viewModel.isManualDiscardButtonEnabled, "スタンダードモードでは捨て札ボタンが有効であるべきです")
        XCTAssertFalse(core.isAwaitingManualDiscardSelection, "初期状態では捨て札モードが無効であるべきです")

        viewModel.toggleManualDiscardSelection()

        XCTAssertTrue(core.isAwaitingManualDiscardSelection, "ボタン操作で捨て札モードが有効化されていません")
    }

    /// 捨て札モード中に再度ボタンを押すと解除されることを確認
    func testToggleManualDiscardSelectionCancelsWhenAlreadyActive() {
        let (viewModel, core) = makeViewModel(mode: legacyControlTestMode)
        viewModel.toggleManualDiscardSelection()
        XCTAssertTrue(core.isAwaitingManualDiscardSelection, "前提として捨て札モードが開始している必要があります")

        viewModel.toggleManualDiscardSelection()

        XCTAssertFalse(core.isAwaitingManualDiscardSelection, "2 回目の操作で捨て札モードが解除されていません")
    }

    /// 補助カードは盤面候補なしでも手札から使用できることを確認
    func testSupportCardCanBeTappedWithoutBoardMoveCandidates() {
        let deck = Deck.makeTestDeck(playableCards: [
            .support(.refillEmptySlots),
            .move(.straightRight2),
            .move(.kingUpRight),
            .move(.straightLeft2),
            .move(.straightDown2),
            .move(.straightRight2),
            .move(.straightUp2),
            .move(.straightLeft2)
        ], configuration: .supportToolkit)
        let mode = legacyControlTestMode
        let core = GameCore.makeTestInstance(deck: deck, current: GridPoint(x: 2, y: 2), mode: mode)
        let viewModel = makeViewModel(mode: mode, core: core)

        guard let supportIndex = core.handStacks.firstIndex(where: { $0.topCard?.supportCard == .refillEmptySlots }) else {
            return XCTFail("補給補助カードが手札にありません")
        }

        XCTAssertTrue(viewModel.isCardUsable(core.handStacks[supportIndex]))
        XCTAssertFalse(core.availableMoves().contains { $0.stackID == core.handStacks[supportIndex].id }, "補助カードは盤面移動候補を出さない想定です")

        viewModel.handleHandSlotTap(at: supportIndex)

        XCTAssertEqual(core.moveCount, 1, "補助カードタップで 1 手消費する想定です")
    }

    /// 手動ペナルティが進行中のみで発火し、ペナルティ量が一致することを確認
    func testRequestManualPenaltySetsPendingActionWhenPlayable() {
        let (viewModel, core) = makeViewModel(mode: legacyControlTestMode)
        XCTAssertNil(viewModel.pendingMenuAction, "初期状態では確認ダイアログが未設定であるべきです")

        viewModel.requestManualPenalty()

        XCTAssertEqual(
            viewModel.pendingMenuAction,
            .manualPenalty(penaltyCost: core.mode.usesTargetCollection ? -15 : core.mode.manualRedrawPenaltyCost),
            "ペナルティ要求時の確認アクションが期待と一致しません"
        )
    }

    /// タイトル復帰要求が既存の確認フローへ載ることを確認
    func testRequestReturnToTitleSetsPendingAction() {
        let (viewModel, _) = makeViewModel(mode: .dungeonPlaceholder)

        viewModel.requestReturnToTitle()

        XCTAssertEqual(
            viewModel.pendingMenuAction,
            .returnToTitle,
            "タイトル復帰要求が確認ダイアログ用の pending action に反映されていません"
        )
    }

    /// プレイ待機中は手動ペナルティの確認がセットされないことを確認
    func testRequestManualPenaltyIgnoredWhenNotPlaying() {
        let (viewModel, core) = makeViewModel(mode: legacyControlTestMode, resolvesSpawnSelection: false)
        XCTAssertEqual(core.progress, .awaitingSpawn, "クラシカルモードではスポーン待機が初期状態です")

        viewModel.requestManualPenalty()

        XCTAssertNil(viewModel.pendingMenuAction, "プレイ開始前にペナルティ確認が設定されてはいけません")
    }

    func testDungeonResultPresentationCombinesHandCardUses() {
        let presentation = ResultSummaryPresentation(
            moveCount: 6,
            penaltyCount: 0,
            focusCount: 0,
            usesTargetCollection: false,
            usesDungeonExit: true,
            isFailed: false,
            failureReason: nil,
            dungeonHP: 2,
            remainingDungeonTurns: 3,
            dungeonRunFloorText: "基礎塔 2/3F",
            dungeonRunTotalMoveCount: 10,
            dungeonRewardMoveCards: [],
            dungeonInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2, pickupUses: 1),
                DungeonInventoryEntry(card: .straightUp2, pickupUses: 1)
            ],
            dungeonGrowthAward: nil,
            hasNextDungeonFloor: true,
            elapsedSeconds: 20
        )

        XCTAssertEqual(presentation.dungeonRewardInventoryText, "右2×3、上2×1")
        XCTAssertTrue(presentation.dungeonPickupInventoryEntries.isEmpty)
    }

    func testDungeonResultTitleUsesCurrentTowerName() {
        let presentation = ResultSummaryPresentation(
            moveCount: 8,
            penaltyCount: 0,
            focusCount: 0,
            usesTargetCollection: false,
            usesDungeonExit: true,
            isFailed: false,
            failureReason: nil,
            dungeonHP: 2,
            remainingDungeonTurns: 0,
            dungeonRunFloorText: "巡回塔 3/3F",
            dungeonRunTotalMoveCount: 20,
            dungeonRewardMoveCards: [],
            dungeonInventoryEntries: [],
            dungeonGrowthAward: nil,
            hasNextDungeonFloor: false,
            elapsedSeconds: 35
        )

        XCTAssertEqual(presentation.resultTitle, "巡回塔クリア")
    }

    func testGrowthTowerPointIsAwardedAtFifthFloorMilestoneOnlyOnce() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let milestoneFloor = dungeon.floors[4]
        let runState = DungeonRunState(
            dungeonID: dungeon.id,
            currentFloorIndex: 4,
            carriedHP: 3,
            clearedFloorCount: 4
        )
        let mode = milestoneFloor.makeGameMode(
            dungeonID: dungeon.id,
            difficulty: dungeon.difficulty,
            carriedHP: 3,
            runState: runState
        )
        let (viewModel, _) = makeViewModel(
            mode: mode,
            dungeonGrowthStore: growthStore
        )

        viewModel.handleProgressChange(.cleared)

        XCTAssertEqual(growthStore.points, 1)
        XCTAssertEqual(viewModel.latestDungeonGrowthAward?.points, 1)
        XCTAssertEqual(viewModel.latestDungeonGrowthAward?.milestoneID, "growth-tower-5f")

        viewModel.handleProgressChange(.cleared)
        XCTAssertEqual(growthStore.points, 1)
    }

    func testGrowthTowerPointIsAwardedAtTenthFloorAndUnlocksSecondSectionOnlyOnce() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let milestoneFloor = dungeon.floors[9]
        let runState = DungeonRunState(
            dungeonID: dungeon.id,
            currentFloorIndex: 9,
            carriedHP: 3,
            clearedFloorCount: 9
        )
        let mode = milestoneFloor.makeGameMode(
            dungeonID: dungeon.id,
            difficulty: dungeon.difficulty,
            carriedHP: 3,
            runState: runState
        )
        let (viewModel, _) = makeViewModel(
            mode: mode,
            dungeonGrowthStore: growthStore
        )

        viewModel.handleProgressChange(.cleared)

        XCTAssertEqual(growthStore.points, 1)
        XCTAssertEqual(viewModel.latestDungeonGrowthAward?.points, 1)
        XCTAssertTrue(growthStore.hasRewardedGrowthMilestone("growth-tower-10f"))
        XCTAssertEqual(growthStore.availableGrowthStartFloorNumbers(for: dungeon), [1, 11])

        viewModel.handleProgressChange(.cleared)
        XCTAssertEqual(growthStore.points, 1)
    }

    func testGrowthTowerPointIsAwardedAtTwentiethFloorMilestoneOnlyOnce() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let finalFloor = dungeon.floors[19]
        let runState = DungeonRunState(
            dungeonID: dungeon.id,
            currentFloorIndex: 19,
            carriedHP: 3,
            clearedFloorCount: 19
        )
        let mode = finalFloor.makeGameMode(
            dungeonID: dungeon.id,
            difficulty: dungeon.difficulty,
            carriedHP: 3,
            runState: runState
        )
        let (viewModel, _) = makeViewModel(
            mode: mode,
            dungeonGrowthStore: growthStore
        )

        viewModel.handleProgressChange(.cleared)

        XCTAssertEqual(growthStore.points, 1)
        XCTAssertEqual(viewModel.latestDungeonGrowthAward?.points, 1)
        XCTAssertTrue(growthStore.hasRewardedGrowthMilestone("growth-tower-20f"))

        viewModel.handleProgressChange(.cleared)
        XCTAssertEqual(growthStore.points, 1)
    }

    func testRoguelikeTowerDoesNotAwardGrowthPointOnFinalFloorClear() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let finalFloor = try XCTUnwrap(dungeon.floors.last)
        let runState = DungeonRunState(
            dungeonID: dungeon.id,
            currentFloorIndex: 2,
            carriedHP: 3,
            clearedFloorCount: 2
        )
        let mode = finalFloor.makeGameMode(
            dungeonID: dungeon.id,
            difficulty: dungeon.difficulty,
            carriedHP: 3,
            runState: runState
        )
        let (viewModel, _) = makeViewModel(
            mode: mode,
            dungeonGrowthStore: growthStore
        )

        viewModel.handleProgressChange(.cleared)

        XCTAssertEqual(growthStore.points, 0)
        XCTAssertNil(viewModel.latestDungeonGrowthAward)
        XCTAssertTrue(growthStore.growthMilestoneIDs(for: dungeon).isEmpty)
    }

    func testRoguelikeTowerDoesNotUseGrowthRewardBoostOrRewardAdjustment() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let growthDungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let rogueDungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let growthRunState = DungeonRunState(dungeonID: growthDungeon.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = growthStore.registerDungeonClear(dungeon: growthDungeon, runState: growthRunState, hasNextFloor: true)
        XCTAssertTrue(growthStore.unlock(.rewardScout))

        let runState = DungeonRunState(
            dungeonID: rogueDungeon.id,
            currentFloorIndex: 0,
            carriedHP: 3
        )
        let mode = rogueDungeon.floors[0].makeGameMode(
            dungeonID: rogueDungeon.id,
            difficulty: rogueDungeon.difficulty,
            runState: runState
        )
        let (viewModel, _) = makeViewModel(
            mode: mode,
            dungeonGrowthStore: growthStore
        )

        XCTAssertEqual(viewModel.availableDungeonRewardMoveCards, rogueDungeon.floors[0].rewardMoveCardsAfterClear)
        XCTAssertTrue(viewModel.adjustableDungeonRewardEntries.isEmpty)
    }

    func testDungeonGrowthPointIsNotAwardedBeforeFinalFloor() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let firstFloor = try XCTUnwrap(dungeon.floors.first)
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: dungeon))
        let (viewModel, _) = makeViewModel(
            mode: firstFloor.makeGameMode(
                dungeonID: dungeon.id,
                carriedHP: 3,
                runState: mode.dungeonMetadataSnapshot?.runState
            ),
            dungeonGrowthStore: growthStore
        )

        viewModel.handleProgressChange(.cleared)

        XCTAssertEqual(growthStore.points, 0)
        XCTAssertNil(viewModel.latestDungeonGrowthAward)
    }

    func testDungeonRewardCandidatesUseGrowthBoostWhenUnlocked() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = growthStore.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: true)
        XCTAssertTrue(growthStore.unlock(.rewardScout))

        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: dungeon))
        let (viewModel, _) = makeViewModel(
            mode: mode,
            dungeonGrowthStore: growthStore
        )

        let resolvedRunState = try XCTUnwrap(mode.dungeonMetadataSnapshot?.runState)
        let baseCards = try XCTUnwrap(
            dungeon.resolvedFloor(at: resolvedRunState.currentFloorIndex, runState: resolvedRunState)?
                .rewardMoveCardsAfterClear
        )

        XCTAssertEqual(viewModel.availableDungeonRewardMoveCards.count, 3)
        XCTAssertEqual(Array(viewModel.availableDungeonRewardMoveCards.prefix(2)), Array(baseCards.prefix(2)))
        XCTAssertNotEqual(viewModel.availableDungeonRewardMoveCards, Array(baseCards.prefix(3)))
    }

    func testDungeonRewardCardsMergeSupportIntoThreeChoicesAndAdvance() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 10,
            carriedHP: 3,
            clearedFloorCount: 10
        )
        let floor = try XCTUnwrap(tower.resolvedFloor(at: 10, runState: runState))
        let mode = floor.makeGameMode(
            dungeonID: tower.id,
            difficulty: tower.difficulty,
            runState: runState
        )
        var requestedMode: GameMode?
        let (viewModel, core) = makeViewModel(
            mode: mode,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )
        core.overrideMetricsForTesting(moveCount: 6, penaltyCount: 0, elapsedSeconds: 20)
        core.overrideDungeonHPForTesting(3)

        XCTAssertEqual(
            viewModel.availableDungeonRewardCards,
            [.move(.rayDown), .move(.straightDown2), .support(.refillEmptySlots)]
        )

        viewModel.showingResult = true
        viewModel.handleDungeonRewardSelection(.addSupport(.refillEmptySlots))

        let nextRunState = try XCTUnwrap(requestedMode?.dungeonMetadataSnapshot?.runState)
        XCTAssertEqual(nextRunState.currentFloorIndex, 11)
        XCTAssertEqual(
            nextRunState.rewardInventoryEntries,
            [DungeonInventoryEntry(support: .refillEmptySlots, rewardUses: 1)]
        )
        XCTAssertFalse(viewModel.showingResult)
    }

    /// finalizeResultDismissal が結果表示フラグのみを閉じることを確認
    func testFinalizeResultDismissalClosesResultFlag() {
        let (viewModel, _) = makeViewModel(mode: .dungeonPlaceholder)
        viewModel.showingResult = true

        viewModel.finalizeResultDismissal()

        XCTAssertFalse(viewModel.showingResult, "結果画面の明示クローズ後も showingResult が残っています")
    }

    /// セッション UI mutation helper が公開 state へ同期されることを確認
    func testApplySessionUIMutationSynchronizesPublishedState() {
        let (viewModel, _) = makeViewModel(mode: .dungeonPlaceholder)
        let event = PenaltyEvent(penaltyAmount: 2, trigger: .automaticDeadlock)

        viewModel.applySessionUIMutation { state in
            state.setActivePenaltyBanner(event)
            state.requestReturnToTitle()
            state.setPauseMenuPresented(true)
            state.updateDisplayedElapsedTime(33)
        }

        XCTAssertEqual(viewModel.activePenaltyBanner, event, "ペナルティバナーが公開 state に同期されていません")
        XCTAssertEqual(viewModel.pendingMenuAction, .returnToTitle, "pendingMenuAction が公開 state に同期されていません")
        XCTAssertTrue(viewModel.isPauseMenuPresented, "ポーズメニュー表示状態が公開 state に同期されていません")
        XCTAssertEqual(viewModel.displayedElapsedSeconds, 33, "経過秒数が公開 state に同期されていません")
    }

    /// SessionUIState が確認ダイアログや一時 UI 状態の更新をまとめて扱えることを確認
    func testSessionUIStateTracksTransientUIChanges() {
        var state = SessionUIState()
        let event = PenaltyEvent(penaltyAmount: 3, trigger: .automaticDeadlock)

        state.requestManualPenalty(cost: 5)
        state.setActivePenaltyBanner(event)
        state.presentPauseMenu()
        state.updateDisplayedElapsedTime(77)

        XCTAssertEqual(state.pendingMenuAction, .manualPenalty(penaltyCost: 5), "手動ペナルティ要求が保持されていません")
        XCTAssertEqual(state.activePenaltyBanner, event, "ペナルティバナー情報が保持されていません")
        XCTAssertTrue(state.isPauseMenuPresented, "ポーズメニュー表示状態が保持されていません")
        XCTAssertEqual(state.displayedElapsedSeconds, 77, "経過秒数の表示状態が更新されていません")

        state.resetTransientUIForTitleReturn()

        XCTAssertNil(state.pendingMenuAction, "タイトル復帰準備後も確認ダイアログが残っています")
        XCTAssertNil(state.activePenaltyBanner, "タイトル復帰準備後もペナルティバナーが残っています")
        XCTAssertFalse(state.isPauseMenuPresented, "タイトル復帰準備後はポーズメニューが閉じている必要があります")
        XCTAssertEqual(state.displayedElapsedSeconds, 77, "恒常表示値まで巻き戻してはいけません")
    }

    /// SessionResetCoordinator がタイトル復帰時に UI 後始末だけを実行することを確認
    func testSessionResetCoordinatorPrepareForReturnToTitleClearsUIOnly() {
        let coordinator = GameSessionResetCoordinator()
        var calledSteps: [String] = []

        coordinator.prepareForReturnToTitle(
            clearSelectedCardSelection: { calledSteps.append("clearSelection") },
            cancelPenaltyBannerDisplay: { calledSteps.append("cancelBanner") },
            hideResult: { calledSteps.append("hideResult") },
            resetTransientUI: { calledSteps.append("resetTransientUI") },
            clearBoardTapSelectionWarning: { calledSteps.append("clearWarning") },
            resetAdsPlayFlag: { calledSteps.append("resetAds") },
            resetPauseController: { calledSteps.append("resetPause") }
        )

        XCTAssertEqual(
            calledSteps,
            ["clearSelection", "cancelBanner", "hideResult", "resetTransientUI", "clearWarning", "resetAds", "resetPause"],
            "タイトル復帰時の UI 後始末が想定順に実行されていません"
        )
    }

    /// SessionResetCoordinator が新規プレイ開始時に title return 準備と core.reset() を両方実行することを確認
    func testSessionResetCoordinatorResetSessionForNewPlayRunsCoreReset() {
        let coordinator = GameSessionResetCoordinator()
        var calledSteps: [String] = []

        coordinator.resetSessionForNewPlay(
            prepareForReturnToTitle: { calledSteps.append("prepareForReturnToTitle") },
            resetCore: { calledSteps.append("resetCore") },
            resetPauseController: { calledSteps.append("resetPause") }
        )

        XCTAssertEqual(
            calledSteps,
            ["prepareForReturnToTitle", "resetCore", "resetPause"],
            "新規プレイ開始時の初期化順序が想定と異なります"
        )
    }

    /// prepareForAppear が guide / haptics / elapsed time / overlay 連動を既存どおり反映することを確認
    func testPrepareForAppearSynchronizesInitialSettings() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let dateProvider = MutableDateProvider(now: Date(timeIntervalSince1970: 90_000))
        let (viewModel, core) = makeViewModel(
            mode: .dungeonPlaceholder,
            dateProvider: dateProvider
        )
        core.setStartDateForTesting(dateProvider.now.addingTimeInterval(-45))

        viewModel.prepareForAppear(
            colorScheme: .dark,
            guideModeEnabled: false,
            hapticsEnabled: false,
            handOrderingStrategy: .directionSorted,
            isPreparationOverlayVisible: true
        )

        XCTAssertFalse(viewModel.boardBridge.guideModeEnabled, "初期表示準備後に guide mode が反映されていません")
        XCTAssertFalse(viewModel.boardBridge.hapticsEnabled, "初期表示準備後に haptics 設定が反映されていません")
        XCTAssertGreaterThanOrEqual(viewModel.displayedElapsedSeconds, 45, "初期表示準備時に経過秒数が同期されていません")

        dateProvider.now = dateProvider.now.addingTimeInterval(30)
        XCTAssertEqual(core.liveElapsedSecondsForTesting(asOf: dateProvider.now), 45, "準備オーバーレイ表示中にもタイマーが進行しています")
    }

    /// Game Center 認証状態の同期が冪等で、変化時のみ反映されることを確認
    func testUpdateGameCenterAuthenticationStatusIsIdempotent() {
        let (viewModel, _) = makeViewModel(mode: .dungeonPlaceholder)

        XCTAssertFalse(viewModel.isGameCenterAuthenticated, "初期状態では未認証である想定です")

        viewModel.updateGameCenterAuthenticationStatus(true)
        XCTAssertTrue(viewModel.isGameCenterAuthenticated, "認証状態の更新が反映されていません")

        viewModel.updateGameCenterAuthenticationStatus(true)
        XCTAssertTrue(viewModel.isGameCenterAuthenticated, "同値更新で認証状態が崩れてはいけません")
    }

    func testDungeonFailedProgressShowsResultWithFailureReason() throws {
        let mode = GameMode(
            identifier: .dungeonFloor,
            displayName: "手数切れテスト",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingOnly,
                spawnRule: .fixed(GridPoint(x: 0, y: 0)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 0,
                    revisitPenaltyCost: 0
                ),
                completionRule: .dungeonExit(exitPoint: GridPoint(x: 4, y: 4)),
                dungeonRules: DungeonRules(
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 1)
                )
            ),
            leaderboardEligible: false,
            dungeonMetadata: .init(dungeonID: "test-tower", floorID: "turn-limit")
        )
        let (viewModel, core) = makeViewModel(mode: mode)
        let move = try XCTUnwrap(core.availableMoves().first { $0.destination != mode.dungeonExitPoint })

        core.playCard(using: move)
        viewModel.handleProgressChangeForTesting(core.progress)

        XCTAssertEqual(core.progress, .failed)
        XCTAssertTrue(viewModel.showingResult)
        XCTAssertTrue(viewModel.isResultFailed)
        XCTAssertEqual(viewModel.failureReasonText, "残り手数が0になりました")

        let failedPosition = core.current
        viewModel.finalizeResultDismissal()

        XCTAssertFalse(viewModel.showingResult)
        XCTAssertTrue(viewModel.isInspectingFailedBoard)
        XCTAssertEqual(core.progress, .failed)
        XCTAssertEqual(core.current, failedPosition)

        viewModel.showFailedResultFromBoardInspection()

        XCTAssertTrue(viewModel.showingResult)
        XCTAssertEqual(core.progress, .failed)
    }

    func testPendingDungeonPickupDiscardNewCardResolvesThroughViewModel() throws {
        let pickupPoint = GridPoint(x: 1, y: 0)
        let existingCards = Array(MoveCard.allCases.prefix(9))
        let newCard = try XCTUnwrap(MoveCard.allCases.dropFirst(9).first)
        let pickup = DungeonCardPickupDefinition(id: "view_model_discard_new", point: pickupPoint, card: newCard)
        let (viewModel, core) = makeViewModel(mode: makePickupChoiceMode(pickup: pickup))
        for card in existingCards {
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(card, pickupUses: 1))
        }
        let move = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == pickupPoint })

        core.playBasicOrthogonalMove(using: move)
        XCTAssertEqual(viewModel.pendingDungeonPickupChoice?.pickup, pickup)

        viewModel.discardPendingDungeonPickupCard()

        XCTAssertNil(viewModel.pendingDungeonPickupChoice)
        XCTAssertFalse(core.activeDungeonCardPickups.contains { $0.id == pickup.id })
        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.moveCard == newCard })
        XCTAssertEqual(core.dungeonInventoryEntries.count, 9)
    }

    func testPendingDungeonPickupReplaceExistingCardResolvesThroughViewModel() throws {
        let pickupPoint = GridPoint(x: 1, y: 0)
        let existingCards = Array(MoveCard.allCases.prefix(9))
        let newCard = try XCTUnwrap(MoveCard.allCases.dropFirst(9).first)
        let pickup = DungeonCardPickupDefinition(id: "view_model_replace", point: pickupPoint, card: newCard)
        let (viewModel, core) = makeViewModel(mode: makePickupChoiceMode(pickup: pickup))
        for card in existingCards {
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(card, pickupUses: 1))
        }
        let move = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == pickupPoint })

        core.playBasicOrthogonalMove(using: move)
        XCTAssertNotNil(viewModel.pendingDungeonPickupChoice)

        viewModel.replaceDungeonInventoryEntryForPendingPickup(discarding: .move(existingCards[0]))

        XCTAssertNil(viewModel.pendingDungeonPickupChoice)
        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.moveCard == existingCards[0] })
        XCTAssertTrue(core.dungeonInventoryEntries.contains { $0.moveCard == newCard && $0.rewardUses == 1 && $0.pickupUses == 0 })
        XCTAssertFalse(core.activeDungeonCardPickups.contains { $0.id == pickup.id })
        XCTAssertEqual(core.dungeonInventoryEntries.count, 9)
    }

    func testPendingDungeonPickupReplacementResolvesFromDisplayedHandTap() throws {
        let pickupPoint = GridPoint(x: 1, y: 0)
        let existingCards = Array(MoveCard.allCases.prefix(9))
        let newCard = try XCTUnwrap(MoveCard.allCases.dropFirst(9).first)
        let pickup = DungeonCardPickupDefinition(id: "view_model_hand_tap_replace", point: pickupPoint, card: newCard)
        let (viewModel, core) = makeViewModel(mode: makePickupChoiceMode(pickup: pickup))
        for card in existingCards {
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(card, pickupUses: 1))
        }
        let move = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == pickupPoint })
        core.playBasicOrthogonalMove(using: move)
        XCTAssertNotNil(viewModel.pendingDungeonPickupChoice)

        viewModel.handleHandSlotTap(at: 0)

        XCTAssertNil(viewModel.pendingDungeonPickupChoice)
        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.moveCard == existingCards[0] })
        XCTAssertTrue(core.dungeonInventoryEntries.contains { $0.moveCard == newCard && $0.rewardUses == 1 && $0.pickupUses == 0 })
        XCTAssertFalse(core.activeDungeonCardPickups.contains { $0.id == pickup.id })
        XCTAssertEqual(core.dungeonInventoryEntries.count, 9)
    }

    func testPendingDungeonPickupIgnoresBasicMoveSlotTap() throws {
        let pickupPoint = GridPoint(x: 1, y: 0)
        let existingCards = Array(MoveCard.allCases.prefix(9))
        let newCard = try XCTUnwrap(MoveCard.allCases.dropFirst(9).first)
        let pickup = DungeonCardPickupDefinition(id: "view_model_basic_slot_ignored", point: pickupPoint, card: newCard)
        let (viewModel, core) = makeViewModel(mode: makePickupChoiceMode(pickup: pickup))
        for card in existingCards {
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(card, pickupUses: 1))
        }
        let inventoryBefore = core.dungeonInventoryEntries
        let move = try XCTUnwrap(core.availableBasicOrthogonalMoves().first { $0.destination == pickupPoint })
        core.playBasicOrthogonalMove(using: move)
        XCTAssertNotNil(viewModel.pendingDungeonPickupChoice)

        viewModel.handleHandSlotTap(at: GameViewModel.dungeonBasicMoveSlotIndex)

        XCTAssertNotNil(viewModel.pendingDungeonPickupChoice)
        XCTAssertEqual(core.dungeonInventoryEntries, inventoryBefore)
        XCTAssertTrue(core.activeDungeonCardPickups.contains { $0.id == pickup.id })
    }

    func testDungeonRunNextFloorCarriesHPAndResetsFloorState() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        var requestedMode: GameMode?
        let (viewModel, core) = makeViewModel(
            mode: mode,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )
        core.overrideMetricsForTesting(moveCount: 5, penaltyCount: 0, elapsedSeconds: 30)
        core.overrideDungeonHPForTesting(2)

        let nextMode = try XCTUnwrap(viewModel.makeNextDungeonFloorMode())
        let nextRunState = try XCTUnwrap(nextMode.dungeonMetadataSnapshot?.runState)

        XCTAssertEqual(nextMode.dungeonMetadataSnapshot?.floorID, tower.floors[1].id)
        XCTAssertEqual(nextMode.dungeonRules?.failureRule.initialHP, 2)
        XCTAssertEqual(nextRunState.currentFloorIndex, 1)
        XCTAssertEqual(nextRunState.clearedFloorCount, 1)
        XCTAssertEqual(nextRunState.totalMoveCount, 5)
        XCTAssertEqual(nextMode.dungeonRules?.failureRule.turnLimit, tower.floors[1].failureRule.turnLimit)

        viewModel.showingResult = true
        viewModel.handleNextDungeonFloorAdvance()

        XCTAssertEqual(requestedMode?.dungeonMetadataSnapshot?.floorID, tower.floors[1].id)
        XCTAssertFalse(viewModel.showingResult)
    }

    func testDungeonHPDropPlaysDamageEffectOnlyAfterBaselineIsKnown() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let (viewModel, _) = makeViewModel(mode: mode)

        viewModel.handleDungeonHPChange(3)
        XCTAssertEqual(viewModel.boardBridge.damageEffectPlayCountForTesting, 0)

        viewModel.handleDungeonHPChange(3)
        XCTAssertEqual(viewModel.boardBridge.damageEffectPlayCountForTesting, 0)

        viewModel.handleDungeonHPChange(2)
        XCTAssertEqual(viewModel.boardBridge.damageEffectPlayCountForTesting, 1)
    }

    func testRayMovementPresentationUpdatesHPAndDamageEffectPerTrapStep() throws {
        let mode = makeRayTrapPresentationMode()
        let core = GameCore.makeTestInstance(
            deck: Deck.makeTestDeck(
                cards: [.rayRight, .kingUpRight, .straightRight2, .straightLeft2, .straightDown2],
                configuration: mode.deckConfiguration
            ),
            current: GridPoint(x: 0, y: 0),
            mode: mode
        )
        let move = try XCTUnwrap(core.availableMoves().first { $0.destination == GridPoint(x: 4, y: 0) })

        core.playCard(using: move)
        let resolution = try XCTUnwrap(core.lastMovementResolution)
        let viewModel = makeViewModel(mode: mode, core: core)

        viewModel.beginMovementPresentation(using: resolution)
        XCTAssertEqual(viewModel.dungeonHP, 3)

        viewModel.applyMovementPresentationStep(resolution.presentationSteps[0])
        XCTAssertEqual(viewModel.dungeonHP, 2)
        viewModel.applyMovementPresentationStep(resolution.presentationSteps[1])
        XCTAssertEqual(viewModel.dungeonHP, 1)
        XCTAssertEqual(viewModel.boardBridge.damageEffectPlayCountForTesting, 2)

        viewModel.finishMovementPresentation()
        viewModel.handleDungeonHPChange(core.dungeonHP)
        XCTAssertEqual(viewModel.boardBridge.damageEffectPlayCountForTesting, 2)
    }

    func testDungeonHPIncreaseDoesNotPlayDamageEffect() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let (viewModel, _) = makeViewModel(mode: mode)

        viewModel.handleDungeonHPChange(2)
        viewModel.handleDungeonHPChange(3)

        XCTAssertEqual(viewModel.boardBridge.damageEffectPlayCountForTesting, 0)
    }

    func testDungeonFallRequestsNextFloorWithoutResultPresentation() async throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let fallPoint = GridPoint(x: 3, y: 4)
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 13,
            carriedHP: 2,
            clearedFloorCount: 13,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)]
        )
        let mode = tower.floors[13].makeGameMode(
            dungeonID: tower.id,
            difficulty: tower.difficulty,
            carriedHP: runState.carriedHP,
            runState: runState
        )
        var requestedMode: GameMode?
        let (viewModel, core) = makeViewModel(
            mode: mode,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )
        core.overrideDungeonHPForTesting(1)
        core.overrideDungeonFloorStateForTesting(cracked: [], collapsed: [fallPoint])
        core.overrideMetricsForTesting(moveCount: 7, penaltyCount: 0, elapsedSeconds: 20)

        viewModel.handleDungeonFallEvent(
            DungeonFallEvent(
                point: fallPoint,
                sourceFloorIndex: 13,
                destinationFloorIndex: 12,
                hpAfterDamage: 1
            )
        )

        for _ in 0..<20 where requestedMode == nil {
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        let nextMode = try XCTUnwrap(requestedMode)
        let nextRunState = try XCTUnwrap(nextMode.dungeonMetadataSnapshot?.runState)
        XCTAssertFalse(viewModel.showingResult)
        XCTAssertEqual(nextMode.dungeonMetadataSnapshot?.floorID, tower.floors[12].id)
        XCTAssertEqual(nextMode.initialSpawnPoint, fallPoint)
        XCTAssertEqual(nextRunState.currentFloorIndex, 12)
        XCTAssertEqual(nextRunState.clearedFloorCount, 13)
        XCTAssertEqual(nextRunState.totalMoveCount, 7)
        XCTAssertEqual(nextRunState.pendingFallLandingPoint, fallPoint)
        XCTAssertEqual(nextRunState.rewardInventoryEntries, [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)])
    }

    func testDungeonRewardSelectionAddsCardAndStartsNextFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        var requestedMode: GameMode?
        let (viewModel, core) = makeViewModel(
            mode: mode,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )
        core.overrideMetricsForTesting(moveCount: 4, penaltyCount: 0, elapsedSeconds: 20)
        core.overrideDungeonHPForTesting(2)

        let reward = try XCTUnwrap(viewModel.availableDungeonRewardMoveCards.first)
        viewModel.showingResult = true
        viewModel.handleDungeonRewardSelection(reward)

        let nextMode = try XCTUnwrap(requestedMode)
        XCTAssertEqual(nextMode.dungeonMetadataSnapshot?.floorID, tower.floors[1].id)
        XCTAssertEqual(
            nextMode.dungeonMetadataSnapshot?.runState?.rewardInventoryEntries,
            [DungeonInventoryEntry(card: reward, rewardUses: 2)]
        )
        XCTAssertTrue(nextMode.bonusMoveCards.isEmpty)
        XCTAssertFalse(viewModel.showingResult)
    }

    func testDungeonRewardSelectionDoesNotAdvanceWhenNewCardWouldExceedFullHand() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        var requestedMode: GameMode?
        let (viewModel, core) = makeViewModel(
            mode: mode,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )
        let reward = try XCTUnwrap(viewModel.availableDungeonRewardMoveCards.first)
        let existingCards = Array(MoveCard.allCases.filter { $0 != reward }.prefix(9))
        XCTAssertEqual(existingCards.count, 9)
        for card in existingCards {
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(card, rewardUses: 1))
        }

        viewModel.showingResult = true
        XCTAssertFalse(viewModel.canAddDungeonRewardMoveCard(reward))
        viewModel.handleDungeonRewardSelection(reward)

        XCTAssertNil(requestedMode)
        XCTAssertTrue(viewModel.showingResult)
        XCTAssertFalse(core.dungeonInventoryEntries.contains { $0.moveCard == reward })
    }

    func testDungeonRewardSelectionAllowsExistingCardWhenHandIsFull() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        var requestedMode: GameMode?
        let (viewModel, core) = makeViewModel(
            mode: mode,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )
        let reward = try XCTUnwrap(viewModel.availableDungeonRewardMoveCards.first)
        let fillerCards = Array(MoveCard.allCases.filter { $0 != reward }.prefix(8))
        XCTAssertEqual(fillerCards.count, 8)
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(reward, rewardUses: 1))
        for card in fillerCards {
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(card, rewardUses: 1))
        }

        viewModel.showingResult = true
        XCTAssertTrue(viewModel.canAddDungeonRewardMoveCard(reward))
        viewModel.handleDungeonRewardSelection(reward)

        let nextRunState = try XCTUnwrap(requestedMode?.dungeonMetadataSnapshot?.runState)
        XCTAssertTrue(nextRunState.rewardInventoryEntries.contains { $0.moveCard == reward && $0.rewardUses == 3 })
        XCTAssertFalse(viewModel.showingResult)
    }

    func testDungeonRewardSelectionCanAddNewCardAfterRemovingHandCard() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        var requestedMode: GameMode?
        let (viewModel, core) = makeViewModel(
            mode: mode,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )
        let reward = try XCTUnwrap(viewModel.availableDungeonRewardMoveCards.first)
        let existingCards = Array(MoveCard.allCases.filter { $0 != reward }.prefix(9))
        XCTAssertEqual(existingCards.count, 9)
        for card in existingCards {
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(card, rewardUses: 1))
        }

        viewModel.showingResult = true
        XCTAssertFalse(viewModel.canAddDungeonRewardMoveCard(reward))
        viewModel.handleDungeonRewardCardRemoval(existingCards[0])
        XCTAssertTrue(viewModel.showingResult)
        XCTAssertTrue(viewModel.canAddDungeonRewardMoveCard(reward))
        viewModel.handleDungeonRewardSelection(reward)

        let nextRunState = try XCTUnwrap(requestedMode?.dungeonMetadataSnapshot?.runState)
        XCTAssertFalse(nextRunState.rewardInventoryEntries.contains { $0.moveCard == existingCards[0] })
        XCTAssertTrue(nextRunState.rewardInventoryEntries.contains(DungeonInventoryEntry(card: reward, rewardUses: 2)))
        XCTAssertFalse(viewModel.showingResult)
    }

    func testGrowthTowerTenthFloorOffersRewardAndStartsEleventhFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 9,
            carriedHP: 2,
            totalMoveCount: 40,
            clearedFloorCount: 9,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)]
        )
        let mode = tower.floors[9].makeGameMode(
            dungeonID: tower.id,
            difficulty: tower.difficulty,
            carriedHP: runState.carriedHP,
            runState: runState
        )
        var requestedMode: GameMode?
        let (viewModel, _) = makeViewModel(
            mode: mode,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )

        XCTAssertEqual(viewModel.availableDungeonRewardMoveCards, tower.floors[9].rewardMoveCardsAfterClear)
        XCTAssertEqual(viewModel.adjustableDungeonRewardEntries, [
            DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)
        ])
        XCTAssertEqual(viewModel.nextDungeonFloorTitle, tower.floors[10].makeGameMode(
            dungeonID: tower.id,
            difficulty: tower.difficulty,
            carriedHP: runState.carriedHP,
            runState: runState.advancedToNextFloor(
                carryoverHP: runState.carriedHP,
                currentFloorMoveCount: 0,
                currentInventoryEntries: runState.rewardInventoryEntries
            )
        ).displayName)

        viewModel.handleDungeonRewardSelection(.straightUp2)

        let nextMode = try XCTUnwrap(requestedMode)
        XCTAssertEqual(nextMode.dungeonMetadataSnapshot?.floorID, tower.floors[10].id)
        XCTAssertEqual(nextMode.dungeonMetadataSnapshot?.runState?.currentFloorIndex, 10)
        XCTAssertEqual(nextMode.dungeonMetadataSnapshot?.runState?.rewardInventoryEntries, [
            DungeonInventoryEntry(card: .straightRight2, rewardUses: 2),
            DungeonInventoryEntry(card: .straightUp2, rewardUses: 2)
        ])
    }

    func testGrowthRewardUsesBoostAddsThreeUsesWhenUnlocked() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let fifthFloor = DungeonRunState(dungeonID: tower.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        let tenthFloor = DungeonRunState(dungeonID: tower.id, currentFloorIndex: 9, carriedHP: 3, clearedFloorCount: 9)
        _ = growthStore.registerDungeonClear(dungeon: tower, runState: fifthFloor, hasNextFloor: true)
        _ = growthStore.registerDungeonClear(dungeon: tower, runState: tenthFloor, hasNextFloor: true)
        XCTAssertTrue(growthStore.unlock(.rewardScout))
        XCTAssertTrue(growthStore.unlock(.cardPreservation))

        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        var requestedMode: GameMode?
        let (viewModel, core) = makeViewModel(
            mode: mode,
            dungeonGrowthStore: growthStore,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )
        core.overrideMetricsForTesting(moveCount: 4, penaltyCount: 0, elapsedSeconds: 20)
        core.overrideDungeonHPForTesting(3)

        let reward = try XCTUnwrap(viewModel.availableDungeonRewardMoveCards.first)
        viewModel.showingResult = true
        viewModel.handleDungeonRewardSelection(reward)

        XCTAssertEqual(
            requestedMode?.dungeonMetadataSnapshot?.runState?.rewardInventoryEntries,
            [DungeonInventoryEntry(card: reward, rewardUses: 3)]
        )
    }

    func testDungeonRewardUpgradeIncreasesCarriedRewardUsesAndStartsNextFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 2,
            totalMoveCount: 4,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)]
        )
        let mode = tower.floors[1].makeGameMode(
            dungeonID: tower.id,
            carriedHP: runState.carriedHP,
            runState: runState
        )
        var requestedMode: GameMode?
        let (viewModel, core) = makeViewModel(
            mode: mode,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )
        core.overrideMetricsForTesting(moveCount: 3, penaltyCount: 0, elapsedSeconds: 12)
        core.overrideDungeonHPForTesting(2)

        viewModel.showingResult = true
        viewModel.handleDungeonRewardSelection(.upgrade(.straightRight2))

        let nextRunState = try XCTUnwrap(requestedMode?.dungeonMetadataSnapshot?.runState)
        XCTAssertEqual(nextRunState.currentFloorIndex, 2)
        XCTAssertEqual(
            nextRunState.rewardInventoryEntries,
            [DungeonInventoryEntry(card: .straightRight2, rewardUses: 3)]
        )
        XCTAssertFalse(viewModel.showingResult)
    }

    func testDungeonRewardRemoveDropsCarriedRewardAndStartsNextFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 2,
            totalMoveCount: 4,
            clearedFloorCount: 1,
            rewardInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1)
            ]
        )
        let mode = tower.floors[1].makeGameMode(
            dungeonID: tower.id,
            carriedHP: runState.carriedHP,
            runState: runState
        )
        var requestedMode: GameMode?
        let (viewModel, core) = makeViewModel(
            mode: mode,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )
        core.overrideMetricsForTesting(moveCount: 3, penaltyCount: 0, elapsedSeconds: 12)
        core.overrideDungeonHPForTesting(2)

        viewModel.showingResult = true
        viewModel.handleDungeonRewardSelection(.remove(.straightUp2))

        let nextRunState = try XCTUnwrap(requestedMode?.dungeonMetadataSnapshot?.runState)
        XCTAssertEqual(
            nextRunState.rewardInventoryEntries,
            [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)]
        )
        XCTAssertFalse(viewModel.showingResult)
    }

    func testDungeonRewardCardRemovalStaysOnResultAndCanRemoveMultipleCards() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 2,
            totalMoveCount: 4,
            clearedFloorCount: 1,
            rewardInventoryEntries: [
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 2),
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1),
                DungeonInventoryEntry(card: .diagonalUpRight2, rewardUses: 1)
            ]
        )
        let mode = tower.floors[1].makeGameMode(
            dungeonID: tower.id,
            carriedHP: runState.carriedHP,
            runState: runState
        )
        var requestedMode: GameMode?
        let (viewModel, core) = makeViewModel(
            mode: mode,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )
        core.overrideMetricsForTesting(moveCount: 3, penaltyCount: 0, elapsedSeconds: 12)
        core.overrideDungeonHPForTesting(2)

        viewModel.showingResult = true
        viewModel.handleDungeonRewardCardRemoval(.straightUp2)
        viewModel.handleDungeonRewardCardRemoval(.diagonalUpRight2)

        XCTAssertNil(requestedMode)
        XCTAssertTrue(viewModel.showingResult)
        XCTAssertEqual(
            viewModel.dungeonRewardInventoryEntries,
            [DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)]
        )

        let reward = try XCTUnwrap(viewModel.availableDungeonRewardMoveCards.first)
        viewModel.handleDungeonRewardSelection(reward)

        let nextRunState = try XCTUnwrap(requestedMode?.dungeonMetadataSnapshot?.runState)
        XCTAssertEqual(nextRunState.currentFloorIndex, 2)
        XCTAssertFalse(nextRunState.rewardInventoryEntries.contains { $0.card == .straightUp2 })
        XCTAssertFalse(nextRunState.rewardInventoryEntries.contains { $0.card == .diagonalUpRight2 })
        XCTAssertTrue(nextRunState.rewardInventoryEntries.contains(DungeonInventoryEntry(card: .straightRight2, rewardUses: 2)))
        XCTAssertTrue(nextRunState.rewardInventoryEntries.contains(DungeonInventoryEntry(card: reward, rewardUses: 2)))
        XCTAssertFalse(viewModel.showingResult)
    }

    func testDungeonPickupCarryoverCandidatesAreHiddenBecausePickupsCarryAutomatically() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let (viewModel, core) = makeViewModel(mode: mode)

        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, rewardUses: 2))
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightUp2, pickupUses: 1))

        XCTAssertTrue(viewModel.carryoverCandidateDungeonPickupEntries.isEmpty)
    }

    func testDungeonPickupUsesCarryAutomaticallyWhenSelectingClearReward() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let fifthFloor = DungeonRunState(dungeonID: tower.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        let tenthFloor = DungeonRunState(dungeonID: tower.id, currentFloorIndex: 9, carriedHP: 3, clearedFloorCount: 9)
        _ = growthStore.registerDungeonClear(dungeon: tower, runState: fifthFloor, hasNextFloor: true)
        _ = growthStore.registerDungeonClear(dungeon: tower, runState: tenthFloor, hasNextFloor: true)
        XCTAssertTrue(growthStore.unlock(.rewardScout))
        XCTAssertTrue(growthStore.unlock(.cardPreservation))

        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        var requestedMode: GameMode?
        let (viewModel, core) = makeViewModel(
            mode: mode,
            dungeonGrowthStore: growthStore,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )
        core.overrideMetricsForTesting(moveCount: 4, penaltyCount: 0, elapsedSeconds: 20)
        core.overrideDungeonHPForTesting(3)
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightUp2, pickupUses: 1))

        let reward = try XCTUnwrap(viewModel.availableDungeonRewardMoveCards.first)
        viewModel.showingResult = true
        viewModel.handleDungeonRewardSelection(reward)

        let nextRunState = try XCTUnwrap(requestedMode?.dungeonMetadataSnapshot?.runState)
        XCTAssertTrue(nextRunState.rewardInventoryEntries.contains(DungeonInventoryEntry(card: .straightUp2, rewardUses: 1)))
        XCTAssertTrue(nextRunState.rewardInventoryEntries.contains(DungeonInventoryEntry(card: reward, rewardUses: 3)))
        XCTAssertFalse(viewModel.showingResult)
    }

    func testDungeonRewardAdjustmentEntriesAreHiddenWithoutCarriedRewards() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let (viewModel, _) = makeViewModel(mode: mode)

        XCTAssertFalse(viewModel.availableDungeonRewardMoveCards.isEmpty)
        XCTAssertTrue(viewModel.adjustableDungeonRewardEntries.isEmpty)
    }

    func testSelectedDungeonRewardAppearsInDisplayedHandOnStartedNextFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let firstMode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        var requestedMode: GameMode?
        let (firstViewModel, firstCore) = makeViewModel(
            mode: firstMode,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )
        firstCore.overrideMetricsForTesting(moveCount: 4, penaltyCount: 0, elapsedSeconds: 20)
        firstCore.overrideDungeonHPForTesting(2)

        let reward = try XCTUnwrap(firstViewModel.availableDungeonRewardMoveCards.first)
        firstViewModel.showingResult = true
        firstViewModel.handleDungeonRewardSelection(reward)

        let nextMode = try XCTUnwrap(requestedMode)
        let (nextViewModel, nextCore) = makeViewModel(mode: nextMode)
        let rewardStack = try XCTUnwrap(nextCore.handStacks.first { $0.representativeMove == reward })

        XCTAssertEqual(nextMode.dungeonMetadataSnapshot?.floorID, tower.floors[1].id)
        XCTAssertEqual(nextCore.dungeonInventoryEntries, [DungeonInventoryEntry(card: reward, rewardUses: 2)])
        XCTAssertTrue(nextViewModel.displayedHandStacks.contains { $0.representativeMove == reward })
        XCTAssertTrue(nextViewModel.isCardUsable(rewardStack))
        XCTAssertTrue(
            nextCore.availableMoves().contains { $0.stackID == rewardStack.id },
            "報酬カードは次階開始直後から使用候補へ含める必要があります"
        )

        let rewardIndex = try XCTUnwrap(nextCore.handStacks.firstIndex { $0.id == rewardStack.id })
        nextViewModel.handleHandSlotTap(at: rewardIndex)

        XCTAssertEqual(nextViewModel.boardBridge.animatingCard?.moveCard, reward)
    }

    func testDungeonResumeStoreSavesCurrentPlayingSnapshot() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let resumeStore = DungeonRunResumeStore(userDefaults: defaults)
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let (viewModel, core) = makeViewModel(mode: mode, dungeonRunResumeStore: resumeStore)

        core.overrideMetricsForTesting(moveCount: 3, penaltyCount: 0, elapsedSeconds: 18)
        core.overrideDungeonHPForTesting(2)
        viewModel.saveCurrentDungeonResumeIfPossible()

        let snapshot = try XCTUnwrap(resumeStore.snapshot)
        XCTAssertEqual(snapshot.dungeonID, tower.id)
        XCTAssertEqual(snapshot.floorIndex, 0)
        XCTAssertEqual(snapshot.moveCount, 3)
        XCTAssertEqual(snapshot.elapsedSeconds, 18)
        XCTAssertEqual(snapshot.dungeonHP, 2)
    }

    func testDungeonResumeStoreKeepsSnapshotOnTitleReturnAndClearsOnFailure() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let resumeStore = DungeonRunResumeStore(userDefaults: defaults)
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let (viewModel, _) = makeViewModel(mode: mode, dungeonRunResumeStore: resumeStore)

        viewModel.saveCurrentDungeonResumeIfPossible()
        XCTAssertNotNil(resumeStore.snapshot)

        viewModel.prepareForReturnToTitle()
        XCTAssertNotNil(resumeStore.snapshot)

        viewModel.handleProgressChangeForTesting(.failed)
        XCTAssertNil(resumeStore.snapshot)
    }

    func testDungeonResumeStoreSavesBeforeMenuReturnToTitle() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let resumeStore = DungeonRunResumeStore(userDefaults: defaults)
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let (viewModel, core) = makeViewModel(mode: mode, dungeonRunResumeStore: resumeStore)

        core.overrideMetricsForTesting(moveCount: 5, penaltyCount: 0, elapsedSeconds: 24)
        core.overrideDungeonHPForTesting(2)
        viewModel.performMenuAction(.returnToTitle)

        let snapshot = try XCTUnwrap(resumeStore.snapshot)
        XCTAssertEqual(snapshot.dungeonID, tower.id)
        XCTAssertEqual(snapshot.moveCount, 5)
        XCTAssertEqual(snapshot.elapsedSeconds, 24)
        XCTAssertEqual(snapshot.dungeonHP, 2)
    }

    func testDungeonResumeStoreKeepsExistingSnapshotOnResultReturnToTitle() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let resumeStore = DungeonRunResumeStore(userDefaults: defaults)
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let (viewModel, core) = makeViewModel(mode: mode, dungeonRunResumeStore: resumeStore)

        core.overrideMetricsForTesting(moveCount: 4, penaltyCount: 0, elapsedSeconds: 20)
        viewModel.saveCurrentDungeonResumeIfPossible()
        core.overrideMetricsForTesting(moveCount: 7, penaltyCount: 0, elapsedSeconds: 40)
        viewModel.showingResult = true
        viewModel.handleResultReturnToTitle()

        let snapshot = try XCTUnwrap(resumeStore.snapshot)
        XCTAssertEqual(snapshot.moveCount, 4)
        XCTAssertEqual(snapshot.elapsedSeconds, 20)
    }

    func testDungeonResumeStoreClearsOnReset() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let resumeStore = DungeonRunResumeStore(userDefaults: defaults)
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let (viewModel, _) = makeViewModel(mode: mode, dungeonRunResumeStore: resumeStore)

        viewModel.saveCurrentDungeonResumeIfPossible()
        XCTAssertNotNil(resumeStore.snapshot)

        viewModel.performMenuAction(.reset)
        XCTAssertNil(resumeStore.snapshot)
    }

    func testDungeonResumeStoreSavesStartedNextFloorAfterRewardSelection() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let resumeStore = DungeonRunResumeStore(userDefaults: defaults)
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let firstMode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        var requestedMode: GameMode?
        let (viewModel, core) = makeViewModel(
            mode: firstMode,
            dungeonRunResumeStore: resumeStore,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )
        core.overrideMetricsForTesting(moveCount: 4, penaltyCount: 0, elapsedSeconds: 20)
        core.overrideDungeonHPForTesting(2)

        let reward = try XCTUnwrap(viewModel.availableDungeonRewardMoveCards.first)
        viewModel.showingResult = true
        viewModel.handleDungeonRewardSelection(reward)

        let nextMode = try XCTUnwrap(requestedMode)
        let snapshot = try XCTUnwrap(resumeStore.snapshot)
        XCTAssertEqual(nextMode.dungeonMetadataSnapshot?.runState?.currentFloorIndex, 1)
        XCTAssertEqual(snapshot.floorIndex, 1)
        XCTAssertEqual(snapshot.runState.rewardInventoryEntries, [DungeonInventoryEntry(card: reward, rewardUses: 2)])
    }

    func testWarpTowerRewardAppearsUsableOnStartedNextFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "warp-tower"))
        let firstMode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        var requestedMode: GameMode?
        let (firstViewModel, firstCore) = makeViewModel(
            mode: firstMode,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )
        firstCore.overrideMetricsForTesting(moveCount: 6, penaltyCount: 0, elapsedSeconds: 20)
        firstCore.overrideDungeonHPForTesting(3)

        firstViewModel.showingResult = true
        firstViewModel.handleDungeonRewardSelection(.rayRight)

        let nextMode = try XCTUnwrap(requestedMode)
        let (nextViewModel, nextCore) = makeViewModel(mode: nextMode)
        let rewardStack = try XCTUnwrap(nextCore.handStacks.first { $0.representativeMove == .rayRight })

        XCTAssertEqual(nextMode.dungeonMetadataSnapshot?.floorID, "warp-2")
        XCTAssertEqual(nextCore.dungeonInventoryEntries, [DungeonInventoryEntry(card: .rayRight, rewardUses: 2)])
        XCTAssertTrue(nextViewModel.displayedHandStacks.contains { $0.representativeMove == .rayRight })
        XCTAssertTrue(nextViewModel.isCardUsable(rewardStack))
        XCTAssertTrue(
            nextCore.availableMoves().contains { $0.stackID == rewardStack.id && $0.destination == GridPoint(x: 8, y: 4) },
            "ワープ塔 1F 報酬のレイ型カードは 2F 開始直後から短縮に使える必要があります"
        )
    }

    func testCarriedDungeonRewardCardIsUsableImmediatelyOnNextFloorStart() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 1,
            carriedHP: 2,
            totalMoveCount: 4,
            clearedFloorCount: 1,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .straightRight2, rewardUses: 3)]
        )
        let mode = tower.floors[1].makeGameMode(
            dungeonID: tower.id,
            carriedHP: runState.carriedHP,
            runState: runState
        )
        let (viewModel, core) = makeViewModel(mode: mode)
        let rewardIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.representativeMove == .straightRight2 })
        let rewardStack = core.handStacks[rewardIndex]

        XCTAssertEqual(core.dungeonInventoryEntries, runState.rewardInventoryEntries)
        XCTAssertEqual(viewModel.displayedHandStacks, core.handStacks)
        XCTAssertTrue(viewModel.displayedHandStacks.contains { $0.representativeMove == .straightRight2 })
        XCTAssertTrue(viewModel.isCardUsable(rewardStack))
        XCTAssertTrue(core.availableMoves().contains { $0.stackID == rewardStack.id && $0.destination == GridPoint(x: 2, y: 0) })
        XCTAssertTrue(viewModel.boardBridge.scene.latestHighlightPoints(for: .guideSingleCandidate).contains(GridPoint(x: 2, y: 0)))

        viewModel.handleHandSlotTap(at: rewardIndex)

        XCTAssertEqual(viewModel.boardBridge.animatingCard?.moveCard, .straightRight2)
        XCTAssertEqual(viewModel.boardBridge.animationTargetGridPoint, GridPoint(x: 2, y: 0))
    }

    func testCarriedDungeonRewardCardIsUsableImmediatelyOnThirdFloorStart() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 2,
            carriedHP: 2,
            totalMoveCount: 10,
            clearedFloorCount: 2,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .rayRight, rewardUses: 3)]
        )
        let mode = tower.floors[2].makeGameMode(
            dungeonID: tower.id,
            carriedHP: runState.carriedHP,
            runState: runState
        )
        let (viewModel, core) = makeViewModel(mode: mode)
        let rewardStack = try XCTUnwrap(core.handStacks.first { $0.representativeMove == .rayRight })

        XCTAssertEqual(viewModel.displayedHandStacks, core.handStacks)
        XCTAssertTrue(viewModel.displayedHandStacks.contains { $0.representativeMove == .rayRight })
        XCTAssertTrue(viewModel.isCardUsable(rewardStack))
        XCTAssertTrue(core.availableMoves().contains { $0.stackID == rewardStack.id && $0.destination == GridPoint(x: 4, y: 2) })
        XCTAssertTrue(viewModel.boardBridge.scene.latestHighlightPoints(for: .guideMultiStepCandidate).contains(GridPoint(x: 4, y: 2)))
    }

    func testGrowthTowerLateFloorInventoryCardsSurviveInitialHandOrderingRestore() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let awardRunState = DungeonRunState(dungeonID: tower.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = growthStore.registerDungeonClear(dungeon: tower, runState: awardRunState, hasNextFloor: true)
        XCTAssertTrue(growthStore.unlock(.toolPouch))

        let startingRewardEntries =
            [DungeonInventoryEntry(card: .straightUp2, rewardUses: 1)] +
            growthStore.startingRewardEntries(for: tower, startingFloorIndex: 19)
        let mode = try XCTUnwrap(
            DungeonLibrary.shared.floorMode(
                for: tower,
                floorIndex: 19,
                startingRewardEntries: startingRewardEntries,
                cardVariationSeed: 42
            )
        )
        let (viewModel, core) = makeViewModel(
            mode: mode,
            dungeonGrowthStore: growthStore,
            initialHandOrderingRawValue: HandOrderingStrategy.directionSorted.rawValue
        )
        let starterStack = try XCTUnwrap(core.handStacks.first { $0.representativeMove == .straightRight2 })
        let carryoverStack = try XCTUnwrap(core.handStacks.first { $0.representativeMove == .straightUp2 })

        XCTAssertEqual(mode.dungeonMetadataSnapshot?.floorID, "growth-20")
        XCTAssertEqual(
            core.dungeonInventoryEntries,
            [
                DungeonInventoryEntry(card: .straightUp2, rewardUses: 1),
                DungeonInventoryEntry(card: .straightRight2, rewardUses: 1)
            ]
        )
        XCTAssertEqual(viewModel.displayedHandStacks, core.handStacks)
        XCTAssertTrue(viewModel.displayedHandStacks.contains { $0.id == starterStack.id })
        XCTAssertTrue(viewModel.displayedHandStacks.contains { $0.id == carryoverStack.id })
        XCTAssertTrue(viewModel.isCardUsable(starterStack))
        XCTAssertTrue(core.availableMoves().contains { $0.stackID == starterStack.id })

        let starterIndex = try XCTUnwrap(core.handStacks.firstIndex { $0.id == starterStack.id })
        viewModel.handleHandSlotTap(at: starterIndex)

        XCTAssertEqual(viewModel.boardBridge.animatingCard?.moveCard, .straightRight2)
    }

    func testFirstDungeonFloorStartsWithNoDisplayedCards() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let (viewModel, core) = makeViewModel(mode: mode)

        XCTAssertTrue(core.handStacks.isEmpty)
        XCTAssertTrue(viewModel.displayedHandStacks.isEmpty)
        XCTAssertTrue(core.availableBasicOrthogonalMoves().isEmpty == false)
    }

    func testFinalDungeonFloorDoesNotOfferRewardCards() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 2,
            carriedHP: 2,
            totalMoveCount: 10,
            clearedFloorCount: 2,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .kingRightDiagonalChoice, rewardUses: 2)]
        )
        let mode = tower.floors[2].makeGameMode(
            dungeonID: tower.id,
            carriedHP: runState.carriedHP,
            runState: runState
        )
        let (viewModel, _) = makeViewModel(mode: mode)

        XCTAssertTrue(viewModel.availableDungeonRewardMoveCards.isEmpty)
        XCTAssertTrue(viewModel.carryoverCandidateDungeonPickupEntries.isEmpty)
        XCTAssertNil(viewModel.nextDungeonFloorTitle)
    }

    func testDungeonRunRetryRestartsFromFirstFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 2,
            carriedHP: 1,
            totalMoveCount: 12,
            clearedFloorCount: 2,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .kingRightDiagonalChoice, rewardUses: 2)]
        )
        let mode = tower.floors[2].makeGameMode(
            dungeonID: tower.id,
            carriedHP: runState.carriedHP,
            runState: runState
        )
        var requestedMode: GameMode?
        let (viewModel, _) = makeViewModel(
            mode: mode,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )

        viewModel.showingResult = true
        viewModel.handleResultRetry()

        XCTAssertEqual(requestedMode?.dungeonMetadataSnapshot?.floorID, tower.floors[0].id)
        XCTAssertEqual(requestedMode?.dungeonMetadataSnapshot?.runState?.currentFloorIndex, 0)
        XCTAssertEqual(requestedMode?.dungeonMetadataSnapshot?.runState?.totalMoveCount, 0)
        XCTAssertEqual(requestedMode?.dungeonMetadataSnapshot?.runState?.rewardInventoryEntries, [])
        XCTAssertFalse(viewModel.showingResult)
    }

    func testDungeonRetryButtonTitleShowsGrowthTowerFirstSectionStartFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 4,
            carriedHP: 1,
            totalMoveCount: 18,
            clearedFloorCount: 4
        )
        let mode = tower.floors[4].makeGameMode(
            dungeonID: tower.id,
            carriedHP: runState.carriedHP,
            runState: runState
        )
        let (viewModel, _) = makeViewModel(mode: mode)

        XCTAssertEqual(viewModel.dungeonRetryStartFloorText, "1F")
        XCTAssertEqual(viewModel.resultRetryButtonTitle, "1Fから再挑戦")
    }

    func testDungeonRetryButtonTitleShowsGrowthTowerSecondSectionStartFloor() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(
            dungeonID: tower.id,
            currentFloorIndex: 13,
            carriedHP: 1,
            totalMoveCount: 42,
            clearedFloorCount: 13
        )
        let mode = tower.floors[13].makeGameMode(
            dungeonID: tower.id,
            carriedHP: runState.carriedHP,
            runState: runState
        )
        var requestedMode: GameMode?
        let (viewModel, _) = makeViewModel(
            mode: mode,
            onRequestStartDungeonFloor: { requestedMode = $0 }
        )

        XCTAssertEqual(viewModel.dungeonRetryStartFloorText, "11F")
        XCTAssertEqual(viewModel.resultRetryButtonTitle, "11Fから再挑戦")

        viewModel.showingResult = true
        viewModel.handleResultRetry()

        XCTAssertEqual(requestedMode?.dungeonMetadataSnapshot?.floorID, tower.floors[10].id)
        XCTAssertEqual(requestedMode?.dungeonMetadataSnapshot?.runState?.currentFloorIndex, 10)
    }

    /// メニュー経由でタイトルへ戻る際に GameCore.reset() を呼び出さず、広告フラグのみ初期化されることを確認
    func testPerformMenuActionReturnToTitleSkipsCoreResetButResetsAdsFlag() {
        // タイトル遷移コールバックの呼び出し回数と広告リセットを検証するため、専用のスパイを注入する
        let adsService = SpyAdsService()
        var returnToTitleCallCount = 0
        let (viewModel, core) = makeViewModel(
            mode: .dungeonPlaceholder,
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
            mode: .dungeonPlaceholder,
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

    /// reset 操作時は core.reset() を含む初期化が行われ、警告状態も残留しないことを確認
    func testPerformMenuActionResetClearsWarningAndResetsCore() {
        let (viewModel, core) = makeViewModel(mode: .dungeonPlaceholder)
        core.overrideMetricsForTesting(moveCount: 18, penaltyCount: 2, elapsedSeconds: 70)
        viewModel.boardTapSelectionWarning = GameViewModel.BoardTapSelectionWarning(
            message: "warning",
            destination: GridPoint(x: 1, y: 1)
        )
        viewModel.pendingMenuAction = .reset
        viewModel.showingResult = true

        viewModel.performMenuAction(.reset)

        XCTAssertEqual(core.moveCount, 0, "reset 操作後は GameCore が初期化される必要があります")
        XCTAssertNil(viewModel.boardTapSelectionWarning, "reset 操作後も盤面タップ警告が残っています")
        XCTAssertNil(viewModel.pendingMenuAction, "reset 操作後も確認ダイアログが残っています")
        XCTAssertFalse(viewModel.showingResult, "reset 操作後は結果画面表示フラグが閉じている必要があります")
    }

    func testParalysisTrapEnemyTurnShowsRestToast() {
        let paralysisTrap = GridPoint(x: 1, y: 0)
        let mode = GameMode(
            identifier: .dungeonFloor,
            displayName: "麻痺罠トーストテスト",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: .standard,
                spawnRule: .fixed(GridPoint(x: 0, y: 0)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 0,
                    revisitPenaltyCost: 0
                ),
                tileEffectOverrides: [paralysisTrap: .slow],
                completionRule: .dungeonExit(exitPoint: GridPoint(x: 4, y: 4)),
                dungeonRules: DungeonRules(
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 8),
                    enemies: []
                )
            ),
            leaderboardEligible: false
        )
        let core = GameCore.makeTestInstance(
            deck: Deck.makeTestDeck(cards: [.rayRight, .kingUpRight, .straightRight2], configuration: mode.deckConfiguration),
            current: GridPoint(x: 0, y: 0),
            mode: mode
        )
        let viewModel = makeViewModel(mode: mode, core: core)
        let move = try! XCTUnwrap(core.availableMoves().first { $0.destination == paralysisTrap })

        core.playCard(using: move)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(viewModel.boardTapSelectionWarning?.destination, paralysisTrap)
        XCTAssertEqual(
            viewModel.boardTapSelectionWarning?.message,
            "麻痺罠で1回休み。敵が続けて動きます。"
        )
    }

    private func makePickupChoiceMode(pickup: DungeonCardPickupDefinition) -> GameMode {
        GameMode(
            identifier: .dungeonFloor,
            displayName: "満杯拾得テスト",
            regulation: GameMode.Regulation(
                boardSize: BoardGeometry.standardSize,
                handSize: 10,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: .standard,
                spawnRule: .fixed(GridPoint(x: 0, y: 0)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 0,
                    revisitPenaltyCost: 0
                ),
                completionRule: .dungeonExit(exitPoint: GridPoint(x: 4, y: 4)),
                dungeonRules: DungeonRules(
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: 3, turnLimit: nil),
                    allowsBasicOrthogonalMove: true,
                    cardAcquisitionMode: .inventoryOnly,
                    cardPickups: [pickup]
                )
            ),
            leaderboardEligible: false,
            dungeonMetadata: GameMode.DungeonMetadata(
                dungeonID: "view-model-pickup-test",
                floorID: "pickup-choice",
                runState: DungeonRunState(dungeonID: "view-model-pickup-test", carriedHP: 3)
            )
        )
    }

    private func makeRayTrapPresentationMode() -> GameMode {
        GameMode(
            identifier: .dungeonFloor,
            displayName: "レイ表示テスト",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: .standard,
                spawnRule: .fixed(GridPoint(x: 0, y: 0)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 0,
                    revisitPenaltyCost: 0
                ),
                completionRule: .dungeonExit(exitPoint: GridPoint(x: 4, y: 4)),
                dungeonRules: DungeonRules(
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: 3, turnLimit: 8),
                    hazards: [.damageTrap(points: [GridPoint(x: 1, y: 0), GridPoint(x: 2, y: 0)], damage: 1)]
                )
            ),
            leaderboardEligible: false
        )
    }

    /// テストで使い回す ViewModel と GameCore の組み合わせを生成するヘルパー
    private func makeViewModel(
        mode: GameMode,
        adsService: AdsServiceProtocol? = nil,
        onRequestReturnToTitle: (() -> Void)? = nil,
        dungeonGrowthStore: DungeonGrowthStore? = nil,
        dungeonRunResumeStore: DungeonRunResumeStore? = nil,
        onRequestStartDungeonFloor: ((GameMode) -> Void)? = nil,
        dateProvider: MutableDateProvider? = nil,
        initialHandOrderingRawValue: String? = nil,
        resolvesSpawnSelection: Bool = true
    ) -> (GameViewModel, GameCore) {
        let core = GameCore(mode: mode)
        if mode.requiresSpawnSelection && resolvesSpawnSelection {
            // テストがスポーン選択待機で停止しないように、盤面中央へスポーンを確定させる
            let spawnPoint = mode.initialSpawnPoint ?? GridPoint(x: mode.boardSize / 2, y: mode.boardSize / 2)
            core.simulateSpawnSelection(forTesting: spawnPoint)
        }

        let interfaces = GameModuleInterfaces { _ in core }
        let resolvedDateProvider = dateProvider ?? MutableDateProvider(now: Date())
        let resolvedAdsService = adsService ?? DummyAdsService()
        let resolvedDungeonGrowthStore = dungeonGrowthStore ?? DungeonGrowthStore()
        let resolvedDungeonRunResumeStore = dungeonRunResumeStore ?? makeIsolatedDungeonRunResumeStore()
        let viewModel = GameViewModel(
            mode: mode,
            gameInterfaces: interfaces,
            gameCenterService: DummyGameCenterService(),
            adsService: resolvedAdsService,
            dungeonGrowthStore: resolvedDungeonGrowthStore,
            dungeonRunResumeStore: resolvedDungeonRunResumeStore,
            onRequestGameCenterSignIn: nil,
            onRequestReturnToTitle: onRequestReturnToTitle,
            onRequestStartDungeonFloor: onRequestStartDungeonFloor,
            initialHandOrderingRawValue: initialHandOrderingRawValue,
            currentDateProvider: { resolvedDateProvider.now }
        )
        return (viewModel, core)
    }

    private func makeViewModel(mode: GameMode, core: GameCore) -> GameViewModel {
        let interfaces = GameModuleInterfaces { _ in core }
        return GameViewModel(
            mode: mode,
            gameInterfaces: interfaces,
            gameCenterService: DummyGameCenterService(),
            adsService: DummyAdsService(),
            dungeonGrowthStore: DungeonGrowthStore(),
            dungeonRunResumeStore: makeIsolatedDungeonRunResumeStore(),
            onRequestGameCenterSignIn: nil,
            onRequestReturnToTitle: nil,
            onRequestStartDungeonFloor: nil
        )
    }

    private func makeIsolatedDungeonRunResumeStore() -> DungeonRunResumeStore {
        let suiteName = "MonoKnightAppTests.resume.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return DungeonRunResumeStore(userDefaults: defaults)
    }

    private var legacyControlTestMode: GameMode {
        GameMode(
            identifier: .dungeonFloor,
            displayName: "テスト用標準モード",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standard,
                spawnRule: .chooseAnyAfterPreview,
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 5,
                    manualRedrawPenaltyCost: 3,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 0
                ),
                completionRule: .boardClear
            )
        )
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
