#if canImport(UIKit)
import XCTest
import SwiftUI
import Game
@testable import MonoKnightApp

/// GameHandSectionView のアクセシビリティ表示を検証するテスト
/// - Note: 実際の SwiftUI ビューをホストして VoiceOver 用テキストを取得する
@MainActor
final class GameHandSectionViewAccessibilityTests: XCTestCase {

    /// 複数候補カードの手札ヒントに方向選択の案内が含まれることを確認する
    func testHandSlotHintAnnouncesMultipleDirectionChoice() {
        let core = GameCore(mode: .standard)
        guard let stack = core.handStacks.first, let topCard = stack.topCard else {
            XCTFail("初期手札の取得に失敗しました")
            return
        }

        let overrideVectors = [
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0)
        ]
        MoveCard.setTestMovementVectors(overrideVectors, for: topCard.move)
        defer { MoveCard.setTestMovementVectors(nil, for: topCard.move) }

        let interfaces = GameModuleInterfaces { _ in core }
        let viewModel = GameViewModel(
            mode: .standard,
            gameInterfaces: interfaces,
            gameCenterService: NoopGameCenterService(),
            adsService: NoopAdsService(),
            onRequestGameCenterSignIn: nil,
            onRequestReturnToTitle: nil,
            onRequestStartCampaignStage: nil
        )

        // テスト中は不要なハプティクスやアニメーション効果を抑制しておく
        viewModel.boardBridge.updateHapticsSetting(isEnabled: false)

        // 先に availableMoves を取得し、期待するハイライト座標を把握する
        let candidateMoves = core.availableMoves().filter { candidate in
            candidate.stackID == stack.id && candidate.card.id == topCard.id
        }
        XCTAssertEqual(candidateMoves.count, overrideVectors.count, "複数候補カードの availableMoves 数が想定と異なります")

        guard let stackIndex = core.handStacks.firstIndex(where: { $0.id == stack.id }) else {
            XCTFail("対象スタックの添字を取得できませんでした")
            return
        }

        viewModel.handleHandSlotTap(at: stackIndex)

        let expectedHighlights = Set(candidateMoves.map(\.destination))
        XCTAssertEqual(viewModel.boardBridge.forcedSelectionHighlightPoints, expectedHighlights, "ハイライトされた目的地集合が一致しません")

        let displayedStack = viewModel.displayedHandStacks[stackIndex]
        XCTAssertEqual(displayedStack.representativeVectors?.count, overrideVectors.count)
        XCTAssertEqual(viewModel.selectedHandStackID, displayedStack.id)
    }

    func testDungeonRewardCardIsRenderedInInitialHandSection() throws {
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
        let core = GameCore(mode: mode)
        let interfaces = GameModuleInterfaces { _ in core }
        let viewModel = GameViewModel(
            mode: mode,
            gameInterfaces: interfaces,
            gameCenterService: NoopGameCenterService(),
            adsService: NoopAdsService(),
            onRequestGameCenterSignIn: nil,
            onRequestReturnToTitle: nil,
            onRequestStartCampaignStage: nil
        )

        XCTAssertTrue(viewModel.displayedHandStacks.contains { $0.representativeMove == .straightRight2 })

        let firstDisplayedStack = try XCTUnwrap(viewModel.displayedHandStacks.first)
        XCTAssertEqual(firstDisplayedStack.representativeMove, .straightRight2)
        XCTAssertEqual(firstDisplayedStack.count, 3)
        XCTAssertEqual(viewModel.displayedHandStacks, core.handStacks)
    }
}

// MARK: - テスト用ホストビュー
private struct GameHandSectionHost: View {
    @ObservedObject var viewModel: GameViewModel
    @ObservedObject var boardBridge: GameBoardBridgeViewModel
    var handSlotCount: Int = 5
    let theme = AppTheme()
    @Namespace private var namespace

    var body: some View {
        GameHandSectionView(
            theme: theme,
            viewModel: viewModel,
            boardBridge: boardBridge,
            cardAnimationNamespace: namespace,
            handSlotCount: handSlotCount,
            bottomInset: 0,
            bottomPadding: GameViewLayoutMetrics.handSectionBasePadding
        )
        .environment(\.horizontalSizeClass, .compact)
    }
}

// MARK: - テスト用ユーティリティ
@MainActor
private final class NoopGameCenterService: GameCenterServiceProtocol {
    var isAuthenticated: Bool = true
    func authenticateLocalPlayer(completion: ((Bool) -> Void)?) { completion?(true) }
    func submitScore(_ score: Int, for modeIdentifier: GameMode.Identifier) {}
    func showLeaderboard(for modeIdentifier: GameMode.Identifier) {}
}

@MainActor
private final class NoopAdsService: AdsServiceProtocol {
    func showInterstitial() {}
    func resetPlayFlag() {}
    func disableAds() {}
    func showRewardedAd() async -> Bool { true }
    func requestTrackingAuthorization() async {}
    func requestConsentIfNeeded() async {}
    func refreshConsentStatus() async {}
}
#endif
