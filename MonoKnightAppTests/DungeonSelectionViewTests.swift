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
        let view = NavigationStack {
            DungeonSelectionView(
                dungeonLibrary: .shared,
                dungeonGrowthStore: DungeonGrowthStore(userDefaults: defaults),
                onStartDungeon: {
                    startedDungeon = $0
                    startedFloorIndex = $1
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

    func testDungeonSelectionShowsGrowthRewardStatusForGrowthTowers() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let rogueTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))
        let fifthFloor = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        _ = growthStore.registerDungeonClear(dungeon: growthTower, runState: fifthFloor, hasNextFloor: true)

        let growthStatuses = DungeonGrowthRewardStatusPresentation.make(dungeon: growthTower, growthStore: growthStore)

        XCTAssertEqual(growthStatuses.map(\.text), ["5F 獲得済", "10F 未獲得", "15F 未獲得", "20F 未獲得"])
        XCTAssertEqual(growthStatuses.map(\.isRewarded), [true, false, false, false])
        XCTAssertEqual(growthStatuses.map(\.accessibilityIdentifier), [
            "dungeon_growth_reward_status_growth-tower-5f",
            "dungeon_growth_reward_status_growth-tower-10f",
            "dungeon_growth_reward_status_growth-tower-15f",
            "dungeon_growth_reward_status_growth-tower-20f"
        ])
        XCTAssertTrue(DungeonGrowthRewardStatusPresentation.make(dungeon: rogueTower, growthStore: growthStore).isEmpty)
    }

    func testDungeonSelectionPlacesGrowthTreeOnlyInsideGrowthTowerCard() throws {
        let tutorialTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "tutorial-tower"))
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let rogueTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "rogue-tower"))

        XCTAssertNil(DungeonGrowthTreeCardPresentation.make(dungeon: tutorialTower, points: 2))
        XCTAssertNil(DungeonGrowthTreeCardPresentation.make(dungeon: rogueTower, points: 2))

        let presentation = try XCTUnwrap(DungeonGrowthTreeCardPresentation.make(dungeon: growthTower, points: 2))
        XCTAssertEqual(presentation.title, "成長")
        XCTAssertEqual(presentation.pointsText, "ポイント 2")
        XCTAssertEqual(presentation.sectionAccessibilityIdentifier, "dungeon_growth_section")
        XCTAssertEqual(presentation.toggleAccessibilityIdentifier, "dungeon_growth_toggle")
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

    func testDungeonSelectionGrowthTreeLockStateChangesAfterMilestones() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)
        let growthTower = try XCTUnwrap(DungeonLibrary.shared.dungeon(with: "growth-tower"))
        let fifthFloor = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 4, carriedHP: 3, clearedFloorCount: 4)
        let tenthFloor = DungeonRunState(dungeonID: growthTower.id, currentFloorIndex: 9, carriedHP: 3, clearedFloorCount: 9)

        _ = growthStore.registerDungeonClear(dungeon: growthTower, runState: fifthFloor, hasNextFloor: true)

        XCTAssertTrue(growthStore.canUnlock(.toolPouch))
        XCTAssertEqual(growthStore.lockReason(for: .climbingKit), "前提: 道具袋")
        XCTAssertTrue(growthStore.unlock(.toolPouch))
        XCTAssertEqual(growthStore.lockReason(for: .climbingKit), "10F到達後")

        _ = growthStore.registerDungeonClear(dungeon: growthTower, runState: tenthFloor, hasNextFloor: true)

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
                "区間開始時の持ち込み",
                "クリア後候補とカード運用",
                "罠・敵・落下ダメージの保険",
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
        XCTAssertEqual(presentation.tierFloors, [5, 10, 15, 20, 25, 30, 35, 40, 45, 50])
        XCTAssertEqual(presentation.tierCount, 10)
        XCTAssertEqual(presentation.tierFloors.map { presentation.gateText(forTierFloor: $0) }, ["5F", "10F", "15F", "20F", "25F", "30F", "35F", "40F", "45F", "50F"])
        XCTAssertEqual(presentation.lanes[0].nodes.map(\.upgrade), [.toolPouch, .climbingKit, .shortcutKit, .refillCharm, .deepStartKit, .routeKit, .deepSupplyCraft, .finalPreparation])
        XCTAssertEqual(presentation.lanes[1].nodes.map(\.upgrade), [.rewardScout, .cardPreservation, .widerRewardRead, .supportScout, .relicScout, .rewardUpgradeScout, .rewardRerollRead, .supportMastery, .rewardCompletion])
        XCTAssertEqual(presentation.lanes[2].nodes.map(\.upgrade), [.footingRead, .enemyRead, .secondStep, .meteorRead, .lastStand, .enemyReadPlus, .fallInsurance, .dangerForecast, .finalGuard])
        XCTAssertEqual(presentation.lanes[3].nodes.map(\.upgrade), [.floorSense, .rewardSense, .enemySense, .pathPreview, .deepForecast, .routeForecast])
        XCTAssertEqual(presentation.lanes[4].nodes.map(\.upgrade), [.retryPreparation, .deepCheckpointRead, .sectionRecovery, .checkpointExpansion, .comebackRoute, .finalRecovery])
        XCTAssertEqual(presentation.node(for: .deepSupplyCraft)?.tierFloor, 45)
        XCTAssertEqual(presentation.node(for: .dangerForecast)?.tierFloor, 45)
        XCTAssertEqual(presentation.lane(for: .reward)?.branchSummary, "クリア後候補とカード運用")
        XCTAssertEqual(presentation.lane(for: .reward)?.defaultSelectedUpgrade, .rewardScout)
        XCTAssertEqual(presentation.node(for: .rewardCompletion)?.tierFloor, 50)
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
        XCTAssertEqual(presentation.node(for: .climbingKit)?.lockReason, "10F到達後")
        XCTAssertEqual(presentation.node(for: .climbingKit)?.lockDetailTexts, ["到達条件: 10F到達後", "必要ポイント: 1pt"])
    }

    func testDungeonGrowthTreePresentationSeparatesPrerequisiteAndMilestoneLocks() throws {
        let suiteName = "DungeonSelectionViewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let growthStore = DungeonGrowthStore(userDefaults: defaults)

        let presentation = DungeonGrowthTreePresentation.make(growthStore: growthStore)
        let node = try XCTUnwrap(presentation.node(for: .climbingKit))

        XCTAssertEqual(node.lockReason, "前提: 道具袋")
        XCTAssertEqual(node.lockDetailTexts, [
            "前提スキル: 道具袋",
            "到達条件: 10F到達後",
            "必要ポイント: 1pt"
        ])
        XCTAssertEqual(node.branchFocusText, "この系統: 区間開始時の手札を厚くします")
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
}
