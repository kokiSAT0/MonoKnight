import Game
import SwiftUI
import UIKit
import XCTest
@testable import MonoKnightApp

@MainActor
final class DungeonSelectionViewTests: XCTestCase {
    func testDungeonSelectionCanShowThreeTowerCardsAndStartGrowthTower() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var startedDungeon: DungeonDefinition?
        var startedFloorIndex: Int?
        var startedMovementStyle: DungeonMovementStyle?
        let view = NavigationStack {
            DungeonSelectionView(
                dungeonLibrary: .shared,
                dungeonGrowthStore: DungeonGrowthStore(userDefaults: defaults),
                gameSettingsStore: GameSettingsStore(userDefaults: defaults),
                tutorialTowerProgressStore: TutorialTowerProgressStore(userDefaults: defaults),
                onStartDungeon: { dungeon, floorIndex, _, movementStyle in
                    startedDungeon = dungeon
                    startedFloorIndex = floorIndex
                    startedMovementStyle = movementStyle
                }
            )
        }
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let window = UIWindow(frame: controller.view.frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        XCTAssertEqual(
            DungeonLibrary.shared.dungeons.map(\.id),
            ["tutorial-tower", "growth-tower", "rogue-tower"]
        )
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let firstMode = try XCTUnwrap(DungeonLibrary.shared.firstFloorMode(for: growthTower))

        XCTAssertEqual(firstMode.dungeonMetadataSnapshot?.dungeonID, growthTower.id)
        XCTAssertEqual(firstMode.dungeonMetadataSnapshot?.floorID, "patrol-1")
        XCTAssertEqual(firstMode.dungeonMetadataSnapshot?.runState?.currentFloorIndex, 0)
        XCTAssertEqual(firstMode.boardSize, 9)
        XCTAssertNil(startedDungeon)
        XCTAssertNil(startedFloorIndex)
        XCTAssertNil(startedMovementStyle)
    }

    func testDungeonSelectionShowsOnlyTowerCardsWithoutFloorInfoRows() throws {
        XCTAssertEqual(
            DungeonLibrary.shared.dungeons.map { "dungeon_card_\($0.id)" },
            [
                "dungeon_card_tutorial-tower",
                "dungeon_card_growth-tower",
                "dungeon_card_rogue-tower"
            ]
        )
        XCTAssertFalse(
            DungeonLibrary.shared.allFloors
                .map { "dungeon_floor_info_\($0.id)" }
                .contains("dungeon_card_growth-tower")
        )
    }

    func testDungeonSelectionResumePresentationAppearsOnlyForSavedTower() throws {
        let tutorialTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let snapshot = makeResumeSnapshot(dungeonID: growthTower.id, floorIndex: 2)

        XCTAssertNil(DungeonResumePresentation.make(dungeon: tutorialTower, snapshot: snapshot))

        let presentation = try XCTUnwrap(DungeonResumePresentation.make(dungeon: growthTower, snapshot: snapshot))
        XCTAssertEqual(presentation.buttonTitle, "続きから 3F")
        XCTAssertEqual(presentation.accessibilityIdentifier, "dungeon_resume_button_growth-tower")
        XCTAssertEqual(presentation.accessibilityHint, "成長塔 3階の続きから再開します")
    }

    func testDungeonSelectionResumeModeUsesSavedSnapshot() throws {
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let snapshot = makeResumeSnapshot(dungeonID: growthTower.id, floorIndex: 1, cardVariationSeed: 777)

        let mode = try XCTUnwrap(DungeonLibrary.shared.resumeMode(from: snapshot))

        XCTAssertEqual(mode.dungeonMetadataSnapshot?.dungeonID, growthTower.id)
        XCTAssertEqual(mode.dungeonMetadataSnapshot?.runState?.currentFloorIndex, 1)
        XCTAssertEqual(mode.dungeonMetadataSnapshot?.runState?.cardVariationSeed, 777)
        XCTAssertEqual(mode.dungeonRules?.failureRule.initialHP, snapshot.dungeonHP)
    }

    func testDungeonSelectionShowsCompactGrowthSummaryForGrowthTowers() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let rogueTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let fifthFloor = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = growthStore.registerDungeonClear(dungeon: growthTower, runState: fifthFloor, hasNextFloor: true)

        let presentation = try XCTUnwrap(DungeonGrowthTreeCardPresentation.make(dungeon: growthTower, growthStore: growthStore))

        XCTAssertEqual(presentation.title, "成長")
        XCTAssertEqual(presentation.progressText, "1/10獲得")
        XCTAssertEqual(presentation.pointsText, "ポイント 1")
        XCTAssertEqual(presentation.summaryText, "1/10獲得 · ポイント 1")
        XCTAssertNil(DungeonGrowthTreeCardPresentation.make(dungeon: rogueTower, growthStore: growthStore))
    }

    func testDungeonGrowthForecastAppearsOnlyForActiveScoutingSkills() throws {
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let emptyStore = makeGrowthStore(unlocked: [])

        XCTAssertNil(
            DungeonGrowthForecastPresentation.make(
                dungeon: growthTower,
                startFloorNumber: 1,
                growthStore: emptyStore
            )
        )

        let inactiveStore = makeGrowthStore(unlocked: [.floorSense], active: [])
        XCTAssertNil(
            DungeonGrowthForecastPresentation.make(
                dungeon: growthTower,
                startFloorNumber: 1,
                growthStore: inactiveStore
            )
        )

        let activeStore = makeGrowthStore(unlocked: [.floorSense])
        let presentation = try XCTUnwrap(
            DungeonGrowthForecastPresentation.make(
                dungeon: growthTower,
                startFloorNumber: 1,
                growthStore: activeStore
            )
        )

        XCTAssertEqual(presentation.title, "次区間の見通し")
        XCTAssertEqual(presentation.floorRangeText, "1F-10F")
        XCTAssertEqual(presentation.rows.map(\.category), [.floor])
        XCTAssertTrue(presentation.rows[0].text.contains("床"))
    }

    func testDungeonGrowthForecastSeparatesRewardAndEnemyCategories() throws {
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let growthStore = makeGrowthStore(unlocked: [.rewardSense, .enemySense])

        let presentation = try XCTUnwrap(
            DungeonGrowthForecastPresentation.make(
                dungeon: growthTower,
                startFloorNumber: 11,
                growthStore: growthStore
            )
        )

        XCTAssertEqual(presentation.floorRangeText, "11F-20F")
        XCTAssertEqual(presentation.rows.map(\.category), [.reward, .enemy])
        XCTAssertTrue(presentation.rows[0].text.contains("報酬"))
        XCTAssertTrue(presentation.rows[0].text.contains("拾得カード"))
        XCTAssertTrue(presentation.rows[1].text.contains("敵"))
    }

    func testDungeonGrowthForecastStaysOutOfNonGrowthTowers() throws {
        let tutorialTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let rogueTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let growthStore = makeGrowthStore(unlocked: [.floorSense, .rewardSense, .enemySense])

        XCTAssertNil(
            DungeonGrowthForecastPresentation.make(
                dungeon: tutorialTower,
                startFloorNumber: 1,
                growthStore: growthStore
            )
        )
        XCTAssertNil(
            DungeonGrowthForecastPresentation.make(
                dungeon: rogueTower,
                startFloorNumber: 1,
                growthStore: growthStore
            )
        )
    }

    func testDungeonGrowthForecastAddsFinalRowForFinalSection() throws {
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let growthStore = makeGrowthStore(unlocked: [.routeForecast])

        XCTAssertNil(
            DungeonGrowthForecastPresentation.make(
                dungeon: growthTower,
                startFloorNumber: 31,
                growthStore: growthStore
            )
        )

        let finalPresentation = try XCTUnwrap(
            DungeonGrowthForecastPresentation.make(
                dungeon: growthTower,
                startFloorNumber: 41,
                growthStore: growthStore
            )
        )
        XCTAssertEqual(finalPresentation.floorRangeText, "41F-50F")
        XCTAssertEqual(finalPresentation.rows.map(\.category), [.final])
    }

    func testDungeonSelectionDoesNotRenderMilestoneBadgesAtPhoneWidth() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let fifthFloor = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = growthStore.registerDungeonClear(dungeon: growthTower, runState: fifthFloor, hasNextFloor: true)

        let view = NavigationStack {
            DungeonSelectionView(
                dungeonLibrary: .shared,
                dungeonGrowthStore: growthStore,
                gameSettingsStore: GameSettingsStore(userDefaults: defaults),
                tutorialTowerProgressStore: TutorialTowerProgressStore(userDefaults: defaults),
                onStartDungeon: { _, _, _, _ in }
            )
        }
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let window = UIWindow(frame: controller.view.frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let identifiers = accessibilityIdentifiers(in: controller.view)
        XCTAssertFalse(identifiers.contains { $0.hasPrefix("dungeon_growth_reward_status_") })
    }

    func testDungeonSelectionPlacesGrowthTreeOnlyInsideGrowthTowerCard() throws {
        let tutorialTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let rogueTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))

        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)

        XCTAssertNil(DungeonGrowthTreeCardPresentation.make(dungeon: tutorialTower, growthStore: growthStore))
        XCTAssertNil(DungeonGrowthTreeCardPresentation.make(dungeon: rogueTower, growthStore: growthStore))

        let presentation = try XCTUnwrap(DungeonGrowthTreeCardPresentation.make(dungeon: growthTower, growthStore: growthStore))
        XCTAssertEqual(presentation.title, "成長")
        XCTAssertEqual(presentation.progressText, "0/10獲得")
        XCTAssertEqual(presentation.pointsText, "ポイント 0")
        XCTAssertEqual(presentation.summaryText, "0/10獲得 · ポイント 0")
        XCTAssertEqual(presentation.sectionAccessibilityIdentifier, "dungeon_growth_section")
        XCTAssertEqual(presentation.toggleAccessibilityIdentifier, "dungeon_growth_toggle")
    }

    func testTutorialTowerProgressPresentationChangesAfterCompletion() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let progressStore = TutorialTowerProgressStore(userDefaults: defaults)
        let tutorialTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))

        let initialPresentation = try XCTUnwrap(
            TutorialTowerStatusPresentation.make(dungeon: tutorialTower, progressStore: progressStore)
        )
        XCTAssertEqual(initialPresentation.text, "おすすめ")
        XCTAssertEqual(initialPresentation.accessibilityIdentifier, "dungeon_tutorial_status_tutorial-tower")
        XCTAssertFalse(initialPresentation.isCompleted)
        XCTAssertNil(TutorialTowerStatusPresentation.make(dungeon: growthTower, progressStore: progressStore))
        XCTAssertTrue(progressStore.shouldPresentGrowthTowerIntroPrompt(for: growthTower))

        let finalRunState = DungeonRunState(
            dungeonID: tutorialTower.id,
            currentFloorIndex: tutorialTower.floors.count - 1,
            carriedHP: 3
        )
        progressStore.registerTutorialTowerClear(dungeon: tutorialTower, runState: finalRunState)

        let completedPresentation = try XCTUnwrap(
            TutorialTowerStatusPresentation.make(dungeon: tutorialTower, progressStore: progressStore)
        )
        XCTAssertEqual(completedPresentation.text, "完了済")
        XCTAssertTrue(completedPresentation.isCompleted)
        XCTAssertFalse(progressStore.shouldPresentGrowthTowerIntroPrompt(for: growthTower))
    }

    func testGrowthTowerIntroPromptIsSeenOnlyOnceAndDoesNotLockGrowthTower() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let progressStore = TutorialTowerProgressStore(userDefaults: defaults)
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))

        XCTAssertTrue(progressStore.shouldPresentGrowthTowerIntroPrompt(for: growthTower))
        XCTAssertNotNil(DungeonLibrary.shared.firstFloorMode(for: growthTower))

        progressStore.markGrowthTowerIntroPromptSeen()

        XCTAssertFalse(progressStore.shouldPresentGrowthTowerIntroPrompt(for: growthTower))
        XCTAssertNotNil(DungeonLibrary.shared.firstFloorMode(for: growthTower))
    }

    func testDungeonSelectionShowsRogueTowerHighestFloorFromStoredRecord() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let recordStore = RogueTowerRecordStore(userDefaults: defaults)
        let tutorialTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let rogueTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))

        XCTAssertNil(recordStore.highestFloorText(for: rogueTower))

        XCTAssertTrue(recordStore.registerReachedFloor(27, for: rogueTower))

        XCTAssertEqual(recordStore.highestFloorText(for: rogueTower), "最高到達 27F")
        XCTAssertNil(recordStore.highestFloorText(for: tutorialTower))
        XCTAssertNil(recordStore.highestFloorText(for: growthTower))
    }

    func testDungeonSelectionExposesSecondSectionAfterCheckpointUnlock() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let tenthFloor = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 9, carriedHP: 3, clearedFloorCount: 9)

        XCTAssertEqual(growthStore.availableGrowthStartFloorNumbers(for: growthTower), [1])
        _ = growthStore.registerDungeonClear(dungeon: growthTower, runState: tenthFloor, hasNextFloor: true)

        XCTAssertEqual(growthStore.availableGrowthStartFloorNumbers(for: growthTower), [1, 11])
    }

    func testDungeonSelectionStartButtonsStayAvailableForUnlockedFloors() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let tenthFloor = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 9, carriedHP: 3, clearedFloorCount: 9)

        XCTAssertEqual(
            growthStore.availableGrowthStartFloorNumbers(for: growthTower)
                .map { "dungeon_start_button_\(growthTower.id)_\($0)f" },
            ["dungeon_start_button_growth-tower_1f"]
        )

        _ = growthStore.registerDungeonClear(dungeon: growthTower, runState: tenthFloor, hasNextFloor: true)

        XCTAssertEqual(
            growthStore.availableGrowthStartFloorNumbers(for: growthTower)
                .map { "dungeon_start_button_\(growthTower.id)_\($0)f" },
            [
                "dungeon_start_button_growth-tower_1f",
                "dungeon_start_button_growth-tower_11f"
            ]
        )
    }

    func testDungeonSelectionGrowthTreeLockStateFollowsPrerequisites() throws {
        let growthStore = makeGrowthStore(unlocked: [], active: [], points: 2)

        XCTAssertTrue(growthStore.canUnlock(.toolPouch))
        XCTAssertEqual(growthStore.lockReason(for: .climbingKit), "前提: 道具袋")
        XCTAssertTrue(growthStore.unlock(.toolPouch))
        XCTAssertTrue(growthStore.canUnlock(.climbingKit))
    }

    func testDungeonGrowthTreePresentationBuildsTowerLanes() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)

        let presentation = DungeonGrowthTreePresentation.make(growthStore: growthStore)

        XCTAssertEqual(presentation.lanes.map(\.branch), [.preparation, .reward, .hazard, .scouting, .recovery])
        XCTAssertEqual(presentation.lanes.map(\.branchTitle), ["準備", "報酬", "危険回避", "索敵", "復帰"])
        XCTAssertEqual(
            presentation.branchRoles.map(\.summary),
            [
                "区間開始前の支度候補",
                "クリア後候補とカード運用",
                "危険に合わせた対策支度",
                "次階層帯の見通し",
                "深層チェックポイントと再挑戦支援"
            ]
        )
        XCTAssertEqual(
            presentation.branchRoles.map(\.accessibilityIdentifier),
            [
                "dungeon_growth_branch_role_preparation",
                "dungeon_growth_branch_role_reward",
                "dungeon_growth_branch_role_hazard",
                "dungeon_growth_branch_role_scouting",
                "dungeon_growth_branch_role_recovery"
            ]
        )
        XCTAssertEqual(presentation.stageIndices, Array(0..<5))
        XCTAssertEqual(presentation.tierCount, 5)
        XCTAssertEqual(presentation.lanes[0].nodes.map(\.upgrade), [.toolPouch, .climbingKit, .refillCharm, .deepStartKit, .finalPreparation])
        XCTAssertEqual(presentation.lanes[1].nodes.map(\.upgrade), [.rewardScout, .cardPreservation, .widerRewardRead, .relicScout, .rewardCompletion])
        XCTAssertEqual(presentation.lanes[2].nodes.map(\.upgrade), [.footingRead, .enemyRead, .meteorRead, .lastStand, .finalGuard])
        XCTAssertEqual(presentation.lanes[3].nodes.map(\.upgrade), [.floorSense, .rewardSense, .enemySense, .pathPreview, .routeForecast])
        XCTAssertEqual(presentation.lanes[4].nodes.map(\.upgrade), [.retryPreparation, .deepCheckpointRead, .checkpointExpansion, .finalRecovery])
        XCTAssertEqual(presentation.node(for: .deepStartKit)?.tierFloor, 25)
        XCTAssertEqual(presentation.node(for: .finalGuard)?.tierFloor, 50)
        XCTAssertEqual(presentation.lane(for: .reward)?.branchSummary, "クリア後候補とカード運用")
        XCTAssertEqual(presentation.lane(for: .reward)?.defaultSelectedUpgrade, .rewardScout)
        XCTAssertEqual(presentation.node(for: .rewardCompletion)?.tierFloor, 35)
        XCTAssertEqual(presentation.node(for: .retryPreparation)?.summary, "21F以降の再挑戦時に補給支度を優先します")
        XCTAssertEqual(presentation.node(for: .deepCheckpointRead)?.summary, "21F以降の再挑戦時に障壁支度を出します")
        XCTAssertEqual(presentation.node(for: .checkpointExpansion)?.summary, "31F以降の再挑戦時に万能薬支度を出します")
        XCTAssertEqual(presentation.node(for: .finalRecovery)?.summary, "41F以降の再挑戦時に長距離移動と凍結を出します")
        XCTAssertEqual(presentation.node(for: .cardPreservation)?.effectDetailTexts, [
            "対象: 移動カード報酬",
            "変更: 追加時の使用回数 2回 -> 3回"
        ])
        XCTAssertEqual(presentation.node(for: .deepStartKit)?.effectDetailTexts, [
            "対象: 成長塔のみ",
            "発動: 21F以降は障壁 1回",
            "発動: 31F以降は長距離移動 1回"
        ])
        XCTAssertEqual(presentation.node(for: .finalGuard)?.effectDetailTexts, [
            "対象: 成長塔のみ",
            "防御: 罠・床割れをさらに1回無効化",
            "防御: 敵と予告マーカーもそれぞれさらに1回無効化"
        ])
        XCTAssertEqual(presentation.node(for: .finalRecovery)?.effectDetailTexts, [
            "対象: 成長塔の再挑戦",
            "発動: 41F以降",
            "追加: 凍結 1回、長距離移動 1回"
        ])
    }

    func testGrowthForecastAndPreparationChoicesUseMatchingScoutingSurface() throws {
        let growthStore = makeGrowthStore(
            unlocked: [.floorSense, .enemySense, .pathPreview],
            points: 0
        )
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))

        let forecast = try XCTUnwrap(
            DungeonGrowthForecastPresentation.make(
                dungeon: growthTower,
                startFloorNumber: 41,
                growthStore: growthStore
            )
        )
        let choices = growthStore.preparationChoices(for: growthTower, startingFloorIndex: 40)

        XCTAssertTrue(forecast.rows.contains { $0.category == .floor })
        XCTAssertTrue(forecast.rows.contains { $0.category == .enemy })
        XCTAssertTrue(forecast.rows.contains { $0.category == .path })
        XCTAssertEqual(choices.map(\.category), [.floor, .enemy, .path])
        XCTAssertEqual(choices.count, 3)
    }

    func testDungeonGrowthTreePresentationDerivesNodeStates() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let fifthFloor = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)

        var presentation = DungeonGrowthTreePresentation.make(growthStore: growthStore)
        XCTAssertEqual(presentation.node(for: .toolPouch)?.state, .locked)
        XCTAssertEqual(presentation.node(for: .toolPouch)?.lockReason, "ポイント不足")
        XCTAssertEqual(presentation.node(for: .toolPouch)?.lockDetailTexts, ["必要ポイント: 1pt"])

        _ = growthStore.registerDungeonClear(dungeon: growthTower, runState: fifthFloor, hasNextFloor: true)
        presentation = DungeonGrowthTreePresentation.make(growthStore: growthStore)
        XCTAssertEqual(presentation.node(for: .toolPouch)?.state, .unlockable)
        XCTAssertEqual(presentation.node(for: .toolPouch)?.badgeText, "1pt")
        XCTAssertEqual(presentation.defaultSelectedUpgrade, .toolPouch)

        XCTAssertTrue(growthStore.unlock(.toolPouch))
        presentation = DungeonGrowthTreePresentation.make(growthStore: growthStore)
        XCTAssertEqual(presentation.node(for: .toolPouch)?.state, .active)
        XCTAssertTrue(presentation.node(for: .toolPouch)?.isUnlocked == true)

        XCTAssertTrue(growthStore.setActive(.toolPouch, isActive: false))
        presentation = DungeonGrowthTreePresentation.make(growthStore: growthStore)
        XCTAssertEqual(presentation.node(for: .toolPouch)?.state, .inactive)
        XCTAssertEqual(presentation.node(for: .climbingKit)?.state, .locked)
        XCTAssertEqual(presentation.node(for: .climbingKit)?.lockReason, "ポイント不足")
        XCTAssertEqual(presentation.node(for: .climbingKit)?.lockDetailTexts, ["必要ポイント: 1pt"])
    }

    func testDungeonGrowthTreePresentationSeparatesPrerequisiteAndPointLocks() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)

        let presentation = DungeonGrowthTreePresentation.make(growthStore: growthStore)
        let node = try XCTUnwrap(presentation.node(for: .climbingKit))

        XCTAssertEqual(node.lockReason, "前提: 道具袋")
        XCTAssertEqual(node.lockDetailTexts, [
            "前提スキル: 道具袋",
            "必要ポイント: 1pt"
        ])
        XCTAssertEqual(node.branchFocusText, "この系統: 区間開始前の支度候補を増やします")
    }

    func testDungeonGrowthTreePresentationKeepsStableActionIdentifiers() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let fifthFloor = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = growthStore.registerDungeonClear(dungeon: growthTower, runState: fifthFloor, hasNextFloor: true)

        let presentation = DungeonGrowthTreePresentation.make(growthStore: growthStore)
        let node = try XCTUnwrap(presentation.node(for: .toolPouch))

        XCTAssertEqual(node.accessibilityIdentifier, "dungeon_growth_node_toolPouch")
        XCTAssertTrue(node.accessibilityLabel.contains("準備"))
        XCTAssertTrue(node.accessibilityLabel.contains("道具袋"))
        XCTAssertTrue(node.canUnlock)
        XCTAssertFalse(node.isUnlocked)
    }

    private func makeResumeSnapshot(
        dungeonID: String,
        floorIndex: Int,
        cardVariationSeed: UInt64? = nil
    ) -> DungeonRunResumeSnapshot {
        let runState = DungeonRunState(
            dungeonID: dungeonID,
            currentFloorIndex: floorIndex,
            carriedHP: 3,
            clearedFloorCount: floorIndex,
            cardVariationSeed: cardVariationSeed
        )
        return DungeonRunResumeSnapshot(
            dungeonID: dungeonID,
            floorIndex: floorIndex,
            runState: runState,
            currentPoint: GridPoint(x: 4, y: 4),
            visitedPoints: [GridPoint(x: 4, y: 4)],
            moveCount: 2,
            elapsedSeconds: 12,
            dungeonHP: 2,
            hazardDamageMitigationsRemaining: 0,
            enemyStates: [],
            crackedFloorPoints: [],
            collapsedFloorPoints: [],
            dungeonInventoryEntries: [],
            collectedDungeonCardPickupIDs: [],
            isDungeonExitUnlocked: true
        )
    }

    private func makeGrowthStore(
        unlocked: Set<DungeonGrowthUpgrade>,
        active: Set<DungeonGrowthUpgrade>? = nil,
        points: Int = 0
    ) -> DungeonGrowthStore {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let snapshot = DungeonGrowthSnapshot(
            points: points,
            unlockedUpgrades: unlocked,
            activeUpgrades: active ?? unlocked
        )
        let data = try? JSONEncoder().encode(snapshot)
        defaults.set(data, forKey: StorageKey.UserDefaults.dungeonGrowth)
        return DungeonGrowthStore(userDefaults: defaults)
    }

    private func accessibilityIdentifiers(in view: UIView) -> [String] {
        let ownIdentifier = view.accessibilityIdentifier.map { [$0] } ?? []
        return ownIdentifier + view.subviews.flatMap { accessibilityIdentifiers(in: $0) }
    }
}
