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
        let core = GameCore(mode: .standard)
        core.setStartDateForTesting(Date().addingTimeInterval(-targetElapsedSeconds))

        // GameModuleInterfaces 経由で上記 GameCore を注入し、サービスは最小限のダミーを渡す。
        let interfaces = GameModuleInterfaces { _ in core }
        let viewModel = GameViewModel(
            mode: .standard,
            gameInterfaces: interfaces,
            gameCenterService: DummyGameCenterService(),
            adsService: DummyAdsService(),
            onRequestGameCenterSignIn: nil,
            onRequestReturnToTitle: nil,
            onRequestStartCampaignStage: nil
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

    /// 補助カードは盤面候補なしでも手札から使用できることを確認
    func testSupportCardCanBeTappedWithoutBoardMoveCandidates() {
        let deck = Deck.makeTestDeck(playableCards: [
            .support(.nextRefresh),
            .move(.kingRight),
            .move(.kingUp),
            .move(.kingLeft),
            .move(.kingDown),
            .move(.straightRight2),
            .move(.straightUp2),
            .move(.straightLeft2)
        ], configuration: .supportToolkit)
        let core = GameCore.makeTestInstance(deck: deck, current: GridPoint(x: 2, y: 2))
        let viewModel = makeViewModel(mode: .standard, core: core)

        guard let supportIndex = core.handStacks.firstIndex(where: { $0.topCard?.supportCard == .nextRefresh }) else {
            return XCTFail("NEXT更新補助カードが手札にありません")
        }

        XCTAssertTrue(viewModel.isCardUsable(core.handStacks[supportIndex]))
        XCTAssertFalse(core.availableMoves().contains { $0.stackID == core.handStacks[supportIndex].id }, "補助カードは盤面移動候補を出さない想定です")

        viewModel.handleHandSlotTap(at: supportIndex)

        XCTAssertEqual(core.moveCount, 1, "補助カードタップで 1 手消費する想定です")
    }

    /// 入替補助カードは対象選択モードへ入り、キャンセルできることを確認
    func testSupportSwapTapStartsSelectionAndCanCancel() {
        let deck = Deck.makeTestDeck(playableCards: [
            .support(.swapOne),
            .move(.kingRight),
            .move(.kingUp),
            .move(.kingLeft),
            .move(.kingDown)
        ], configuration: .supportToolkit)
        let core = GameCore.makeTestInstance(deck: deck, current: GridPoint(x: 2, y: 2))
        let viewModel = makeViewModel(mode: .standard, core: core)

        guard let supportIndex = core.handStacks.firstIndex(where: { $0.topCard?.supportCard == .swapOne }) else {
            return XCTFail("入替補助カードが手札にありません")
        }

        viewModel.handleHandSlotTap(at: supportIndex)
        XCTAssertTrue(core.isAwaitingSupportSwapSelection)

        core.cancelSupportSwapSelection()
        XCTAssertFalse(core.isAwaitingSupportSwapSelection)
        XCTAssertEqual(core.moveCount, 0)
    }

    /// 手動ペナルティが進行中のみで発火し、ペナルティ量が一致することを確認
    func testRequestManualPenaltySetsPendingActionWhenPlayable() {
        let (viewModel, core) = makeViewModel(mode: .standard)
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
        let (viewModel, _) = makeViewModel(mode: .standard)

        viewModel.requestReturnToTitle()

        XCTAssertEqual(
            viewModel.pendingMenuAction,
            .returnToTitle,
            "タイトル復帰要求が確認ダイアログ用の pending action に反映されていません"
        )
    }

    /// プレイ待機中は手動ペナルティの確認がセットされないことを確認
    func testRequestManualPenaltyIgnoredWhenNotPlaying() {
        let (viewModel, core) = makeViewModel(mode: .classicalChallenge, resolvesSpawnSelection: false)
        XCTAssertEqual(core.progress, .awaitingSpawn, "クラシカルモードではスポーン待機が初期状態です")

        viewModel.requestManualPenalty()

        XCTAssertNil(viewModel.pendingMenuAction, "プレイ開始前にペナルティ確認が設定されてはいけません")
    }

    /// ResultPresentationState がクリア結果を UI 表示用の状態へ正しく反映することを確認
    func testResultPresentationStateAppliesClearOutcome() {
        let library = CampaignLibrary.shared
        guard let stage = library.stage(with: CampaignStageID(chapter: 1, index: 1)) else {
            XCTFail("キャンペーンステージの取得に失敗しました")
            return
        }

        let progress = CampaignStageProgress(
            earnedStars: 1,
            achievedSecondaryObjective: false,
            achievedScoreGoal: false,
            bestScore: 120,
            bestMoveCount: 12,
            bestTotalMoveCount: 12,
            bestPenaltyCount: 0,
            bestElapsedSeconds: 80
        )
        let record = CampaignStageClearRecord(
            stage: stage,
            evaluation: CampaignStageEvaluation(
                stageID: stage.id,
                earnedStars: 1,
                achievedSecondaryObjective: false,
                achievedScoreGoal: false
            ),
            previousProgress: CampaignStageProgress(),
            progress: progress
        )
        let outcome = GameFlowCoordinator.ClearOutcome(
            latestCampaignClearRecord: record,
            nextCampaignStage: stage,
            shouldShowResult: true
        )

        var state = ResultPresentationState()
        state.applyClearOutcome(outcome)

        XCTAssertTrue(state.showingResult, "クリア後は結果画面表示フラグが立つ必要があります")
        XCTAssertEqual(state.latestCampaignClearRecord?.stage.id, stage.id, "クリア記録が保持されていません")
        XCTAssertEqual(state.nextCampaignStage?.id, stage.id, "次ステージが保持されていません")

        state.hideResult()

        XCTAssertFalse(state.showingResult, "結果画面非表示化が helper から行えません")
    }

    func testDungeonResultPresentationSeparatesRewardAndPickupCards() {
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
            elapsedSeconds: 20,
            bestPoints: .max,
            isNewBest: false,
            previousBest: nil
        )

        XCTAssertEqual(presentation.dungeonRewardInventoryText, "右2×2")
        XCTAssertEqual(presentation.dungeonPickupInventoryText, "右2×1、上2×1")
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
            elapsedSeconds: 35,
            bestPoints: .max,
            isNewBest: false,
            previousBest: nil
        )

        XCTAssertEqual(presentation.resultTitle, "巡回塔クリア")
    }

    func testGrowthTowerPointIsAwardedAtFifthFloorMilestoneOnlyOnce() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let progressStore = CampaignProgressStore(userDefaults: defaults)
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
            campaignProgressStore: progressStore,
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

        let progressStore = CampaignProgressStore(userDefaults: defaults)
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
            campaignProgressStore: progressStore,
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

        let progressStore = CampaignProgressStore(userDefaults: defaults)
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
            campaignProgressStore: progressStore,
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

        let progressStore = CampaignProgressStore(userDefaults: defaults)
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
            campaignProgressStore: progressStore,
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

        let progressStore = CampaignProgressStore(userDefaults: defaults)
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let growthDungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let rogueDungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let growthRunState = DungeonRunState(dungeonID: growthDungeon.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = growthStore.registerDungeonClear(dungeon: growthDungeon, runState: growthRunState, hasNextFloor: true)
        XCTAssertTrue(growthStore.unlock(.rewardCandidateBoost))

        let runState = DungeonRunState(
            dungeonID: rogueDungeon.id,
            currentFloorIndex: 0,
            carriedHP: 3,
            rewardInventoryEntries: [DungeonInventoryEntry(card: .fixedWarp, rewardUses: 2)]
        )
        let mode = rogueDungeon.floors[0].makeGameMode(
            dungeonID: rogueDungeon.id,
            difficulty: rogueDungeon.difficulty,
            runState: runState
        )
        let (viewModel, _) = makeViewModel(
            mode: mode,
            campaignProgressStore: progressStore,
            dungeonGrowthStore: growthStore
        )

        XCTAssertEqual(viewModel.availableDungeonRewardMoveCards, rogueDungeon.floors[0].rewardMoveCardsAfterClear)
        XCTAssertTrue(viewModel.adjustableDungeonRewardEntries.isEmpty)
    }

    func testDungeonGrowthPointIsNotAwardedBeforeFinalFloor() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let progressStore = CampaignProgressStore(userDefaults: defaults)
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
            campaignProgressStore: progressStore,
            dungeonGrowthStore: growthStore
        )

        viewModel.handleProgressChange(.cleared)

        XCTAssertEqual(growthStore.points, 0)
        XCTAssertNil(viewModel.latestDungeonGrowthAward)
    }

    func testDungeonRewardCandidatesUseGrowthBoostWhenUnlocked() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let progressStore = CampaignProgressStore(userDefaults: defaults)
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let dungeon = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let runState = DungeonRunState(dungeonID: dungeon.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = growthStore.registerDungeonClear(dungeon: dungeon, runState: runState, hasNextFloor: true)
        XCTAssertTrue(growthStore.unlock(.rewardCandidateBoost))

        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: dungeon))
        let (viewModel, _) = makeViewModel(
            mode: mode,
            campaignProgressStore: progressStore,
            dungeonGrowthStore: growthStore
        )

        XCTAssertEqual(viewModel.availableDungeonRewardMoveCards.count, 3)
        XCTAssertEqual(Array(viewModel.availableDungeonRewardMoveCards.prefix(2)), Array(dungeon.floors[0].rewardMoveCardsAfterClear.prefix(2)))
        XCTAssertNotEqual(viewModel.availableDungeonRewardMoveCards, dungeon.floors[0].rewardMoveCardsAfterClear)
    }

    /// finalizeResultDismissal が結果表示フラグのみを閉じることを確認
    func testFinalizeResultDismissalClosesResultFlag() {
        let (viewModel, _) = makeViewModel(mode: .standard)
        viewModel.showingResult = true

        viewModel.finalizeResultDismissal()

        XCTAssertFalse(viewModel.showingResult, "結果画面の明示クローズ後も showingResult が残っています")
    }

    /// リザルト状態 mutation helper が公開 state へ同期されることを確認
    func testApplyResultPresentationMutationSynchronizesPublishedState() {
        let (viewModel, _) = makeViewModel(mode: .standard)
        let stage = CampaignLibrary.shared.stage(with: CampaignStageID(chapter: 1, index: 1))

        viewModel.applyResultPresentationMutation { state in
            state.showingResult = true
            state.latestCampaignClearRecord = nil
            state.nextCampaignStage = stage
        }

        XCTAssertTrue(viewModel.showingResult, "リザルト同期 helper 経由で showingResult が更新されていません")
        XCTAssertEqual(viewModel.nextCampaignStage?.id, stage?.id, "次ステージが公開 state に同期されていません")
    }

    /// セッション UI mutation helper が公開 state へ同期されることを確認
    func testApplySessionUIMutationSynchronizesPublishedState() {
        let (viewModel, _) = makeViewModel(mode: .standard)
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

        guard let campaignMode = CampaignLibrary.shared.stage(with: CampaignStageID(chapter: 1, index: 1))?.makeGameMode() else {
            XCTFail("キャンペーンモードの取得に失敗しました")
            return
        }

        let dateProvider = MutableDateProvider(now: Date(timeIntervalSince1970: 90_000))
        let (viewModel, core) = makeViewModel(
            mode: campaignMode,
            campaignProgressStore: CampaignProgressStore(userDefaults: defaults),
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
        let (viewModel, _) = makeViewModel(mode: .standard)

        XCTAssertFalse(viewModel.isGameCenterAuthenticated, "初期状態では未認証である想定です")

        viewModel.updateGameCenterAuthenticationStatus(true)
        XCTAssertTrue(viewModel.isGameCenterAuthenticated, "認証状態の更新が反映されていません")

        viewModel.updateGameCenterAuthenticationStatus(true)
        XCTAssertTrue(viewModel.isGameCenterAuthenticated, "同値更新で認証状態が崩れてはいけません")
    }

    func testDungeonFailedProgressShowsResultWithFailureReason() throws {
        let mode = GameMode(
            identifier: .campaignStage,
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
            [DungeonInventoryEntry(card: reward, rewardUses: 3)]
        )
        XCTAssertTrue(nextMode.bonusMoveCards.isEmpty)
        XCTAssertFalse(viewModel.showingResult)
    }

    func testGrowthTowerCheckpointFloorEndsCurrentRunSection() throws {
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
        let (viewModel, _) = makeViewModel(mode: mode)

        XCTAssertTrue(viewModel.availableDungeonRewardMoveCards.isEmpty)
        XCTAssertTrue(viewModel.adjustableDungeonRewardEntries.isEmpty)
        XCTAssertNil(viewModel.nextDungeonFloorTitle)
    }

    func testGrowthRewardUsesBoostAddsFourUsesWhenUnlocked() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let awardRunState = DungeonRunState(dungeonID: tower.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = growthStore.registerDungeonClear(dungeon: tower, runState: awardRunState, hasNextFloor: true)
        XCTAssertTrue(growthStore.unlock(.rewardUsesBoost))

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
            [DungeonInventoryEntry(card: reward, rewardUses: 4)]
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

    func testDungeonPickupCarryoverCandidatesExposeOnlyUnusedPickupCards() throws {
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let mode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: tower))
        let (viewModel, core) = makeViewModel(mode: mode)

        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, rewardUses: 2))
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightUp2, pickupUses: 1))

        XCTAssertEqual(
            viewModel.carryoverCandidateDungeonPickupEntries,
            [DungeonInventoryEntry(card: .straightUp2, pickupUses: 1)]
        )
    }

    func testDungeonPickupCarryoverSelectionAddsRewardCardAndStartsNextFloor() throws {
        let (defaults, suiteName) = try makeIsolatedDefaults()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let tower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let awardRunState = DungeonRunState(dungeonID: tower.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = growthStore.registerDungeonClear(dungeon: tower, runState: awardRunState, hasNextFloor: true)
        XCTAssertTrue(growthStore.unlock(.rewardUsesBoost))

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

        viewModel.showingResult = true
        viewModel.handleDungeonRewardSelection(.carryOverPickup(.straightUp2))

        let nextRunState = try XCTUnwrap(requestedMode?.dungeonMetadataSnapshot?.runState)
        XCTAssertEqual(
            nextRunState.rewardInventoryEntries,
            [DungeonInventoryEntry(card: .straightUp2, rewardUses: 4)]
        )
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
        XCTAssertEqual(nextCore.dungeonInventoryEntries, [DungeonInventoryEntry(card: reward, rewardUses: 3)])
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

    func testWarpTowerFixedWarpRewardAppearsUsableOnStartedNextFloor() throws {
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
        firstViewModel.handleDungeonRewardSelection(.fixedWarp)

        let nextMode = try XCTUnwrap(requestedMode)
        let (nextViewModel, nextCore) = makeViewModel(mode: nextMode)
        let rewardStack = try XCTUnwrap(nextCore.handStacks.first { $0.representativeMove == .fixedWarp })

        XCTAssertEqual(nextMode.dungeonMetadataSnapshot?.floorID, "warp-2")
        XCTAssertEqual(nextCore.dungeonInventoryEntries, [DungeonInventoryEntry(card: .fixedWarp, rewardUses: 3)])
        XCTAssertTrue(nextViewModel.displayedHandStacks.contains { $0.representativeMove == .fixedWarp })
        XCTAssertTrue(nextViewModel.isCardUsable(rewardStack))
        XCTAssertTrue(
            nextCore.availableMoves().contains { $0.stackID == rewardStack.id && $0.destination == GridPoint(x: 6, y: 4) },
            "固定ワープ報酬は次階開始直後からワープ塔の短縮先へ使える必要があります"
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
            rewardInventoryEntries: [DungeonInventoryEntry(card: .kingLeftOrRight, rewardUses: 2)]
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
            rewardInventoryEntries: [DungeonInventoryEntry(card: .kingLeftOrRight, rewardUses: 2)]
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

    /// reset 操作時は core.reset() を含む初期化が行われ、警告状態も残留しないことを確認
    func testPerformMenuActionResetClearsWarningAndResetsCore() {
        let (viewModel, core) = makeViewModel(mode: .standard)
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

    /// テストで使い回す ViewModel と GameCore の組み合わせを生成するヘルパー
    private func makeViewModel(
        mode: GameMode,
        adsService: AdsServiceProtocol? = nil,
        onRequestReturnToTitle: (() -> Void)? = nil,
        campaignProgressStore: CampaignProgressStore? = nil,
        dungeonGrowthStore: DungeonGrowthStore? = nil,
        onRequestStartCampaignStage: ((CampaignStage) -> Void)? = nil,
        onRequestStartDungeonFloor: ((GameMode) -> Void)? = nil,
        campaignTutorialStore: CampaignTutorialStore = CampaignTutorialStore(),
        dateProvider: MutableDateProvider? = nil,
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
        let resolvedCampaignProgressStore = campaignProgressStore ?? CampaignProgressStore()
        let resolvedDungeonGrowthStore = dungeonGrowthStore ?? DungeonGrowthStore()
        let viewModel = GameViewModel(
            mode: mode,
            gameInterfaces: interfaces,
            gameCenterService: DummyGameCenterService(),
            adsService: resolvedAdsService,
            campaignProgressStore: resolvedCampaignProgressStore,
            dungeonGrowthStore: resolvedDungeonGrowthStore,
            onRequestGameCenterSignIn: nil,
            onRequestReturnToTitle: onRequestReturnToTitle,
            onRequestStartCampaignStage: onRequestStartCampaignStage,
            onRequestStartDungeonFloor: onRequestStartDungeonFloor,
            campaignTutorialStore: campaignTutorialStore,
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
            onRequestGameCenterSignIn: nil,
            onRequestReturnToTitle: nil,
            onRequestStartCampaignStage: nil,
            onRequestStartDungeonFloor: nil
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
