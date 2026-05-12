import Combine
import SwiftUI
import XCTest
@testable import MonoKnightApp
@testable import Game
#if canImport(SpriteKit)
import SpriteKit
#endif

/// GameViewModel と GameBoardBridgeViewModel の連携挙動を網羅的に検証するテスト群
/// - Note: ViewModel 側のメソッドは MainActor を前提としているため、テストケースにも `@MainActor` を付与して実行環境を合わせる。
@MainActor
final class GameViewIntegrationTests: XCTestCase {

    /// Combine で監視しているペナルティイベントに反応してバナーが表示され、手動ペナルティ操作でキャンセルされることを確認する
    func testPenaltyEventSchedulesBannerAndCancelsOnManualPenalty() {
        let scheduler = PenaltyBannerSchedulerSpy()
        let gameCenter = GameCenterServiceSpy()
        let adsService = AdsServiceSpy()
        let interfaces = GameModuleInterfaces { _ in GameCore(mode: .dungeonPlaceholder) }

        let viewModel = GameViewModel(
            mode: .dungeonPlaceholder,
            gameInterfaces: interfaces,
            gameCenterService: gameCenter,
            adsService: adsService,
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: scheduler
        )

        // Combine 経由の購読が動作するかを確認するため、GameCore 側でペナルティイベントを発火させる
        let testEvent = PenaltyEvent(penaltyAmount: viewModel.core.mode.deadlockPenaltyCost, trigger: .automaticDeadlock)
        viewModel.core.publishPenaltyEvent(testEvent)
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        XCTAssertEqual(viewModel.activePenaltyBanner?.penaltyAmount, testEvent.penaltyAmount, "ペナルティバナーへ金額が伝搬されていません")
        XCTAssertEqual(viewModel.activePenaltyBanner?.trigger, testEvent.trigger, "ペナルティイベントのトリガーが反映されていません")
        XCTAssertEqual(scheduler.scheduleCallCount, 1, "自動クローズのスケジュールが登録されていません")
        XCTAssertEqual(scheduler.lastScheduledDelay ?? 0, 2.6, accuracy: 0.001, "バナー自動クローズの遅延秒数が仕様と一致しません")

        // メニュー操作で手動ペナルティを適用すると、バナー表示がキャンセルされる想定
        viewModel.performMenuAction(.manualPenalty(penaltyCost: viewModel.core.mode.manualRedrawPenaltyCost))

        XCTAssertEqual(scheduler.cancelCallCount, 1, "手動ペナルティ適用時にバナーのキャンセルが呼ばれていません")
        XCTAssertNil(viewModel.activePenaltyBanner, "キャンセル直後にバナー情報が残存しています")
    }

    /// 連続手詰まり時に最初は加算ペナルティ、続く再抽選では無料扱いになることを検証する
    func testConsecutiveDeadlockPublishesPaidThenFreePenaltyEvents() {
        let scheduler = PenaltyBannerSchedulerSpy()
        let gameCenter = GameCenterServiceSpy()
        let adsService = AdsServiceSpy()

        // 角からはみ出すカードを優先的に並べ、初回と 2 回目までは完全に手詰まりとなるデッキを用意
        let deadlockCards: [MoveCard] = [
            .straightLeft2,
            .straightDown2,
            .diagonalDownLeft2,
            .knightDown1Left2,
            .knightDown1Right2,
            .straightLeft2,
            .straightDown2,
            .diagonalDownLeft2,
            .knightDown2Left1,
            .knightDown2Right1,
            // 3 回目以降に脱出できるよう、盤内へ進めるカードも混ぜて無限ループを防止
            .kingUpRight,
            .straightRight2,
            .kingUpRight,
            .knightUp2Right1,
            .knightUp1Right2
        ]
        let deck = Deck.makeTestDeck(cards: deadlockCards)
        let interfaces = GameModuleInterfaces { mode in
            GameCore.makeTestInstance(
                deck: deck,
                current: GridPoint(x: 0, y: 0),
                mode: mode
            )
        }

        let viewModel = GameViewModel(
            mode: .dungeonPlaceholder,
            gameInterfaces: interfaces,
            gameCenterService: gameCenter,
            adsService: adsService,
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: scheduler
        )

        var cancellables = Set<AnyCancellable>()
        var receivedEvents: [PenaltyEvent] = []

        // ペナルティイベントが 2 連続で流れてくるため、両方の内容を時系列で記録する
        viewModel.$activePenaltyBanner
            .compactMap { $0 }
            .sink { event in
                receivedEvents.append(event)
            }
            .store(in: &cancellables)

        // Combine の発火と手札再構成が完了するまで短時間待機
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertGreaterThanOrEqual(receivedEvents.count, 2, "連続手詰まりのイベント数が不足しています")

        let firstEvent = receivedEvents[0]
        XCTAssertEqual(firstEvent.trigger, .automaticDeadlock, "初回イベントのトリガーが自動検出になっていません")
        XCTAssertEqual(firstEvent.penaltyAmount, viewModel.core.mode.deadlockPenaltyCost, "初回イベントでペナルティ加算量が反映されていません")

        let secondEvent = receivedEvents[1]
        XCTAssertEqual(secondEvent.trigger, .automaticFreeRedraw, "2 回目のイベントが無料再抽選扱いになっていません")
        XCTAssertEqual(secondEvent.penaltyAmount, firstEvent.penaltyAmount, "無料再抽選時に直前の加算手数が維持されていません")

        // 文字列生成も確認するため、アクセシビリティラベルを取得して文言を検証
        let firstBannerController = UIHostingController(rootView: PenaltyBannerView(event: firstEvent))
        XCTAssertTrue(firstBannerController.view.accessibilityLabel?.contains("+\(firstEvent.penaltyAmount)") ?? false, "初回イベントで加算手数が表記されていません")

        let secondBannerController = UIHostingController(rootView: PenaltyBannerView(event: secondEvent))
        XCTAssertTrue(secondBannerController.view.accessibilityLabel?.contains("+\(secondEvent.penaltyAmount)") ?? false, "無料再抽選時のアクセシビリティ案内へ直前の手数が含まれていません")

        // テスト終了時に購読を破棄してメモリリークを防ぐ
        cancellables.forEach { $0.cancel() }
    }

    /// ゲームクリア時にスコア送信と結果画面表示が自動的に実施されることを確認する
    func testProgressClearedSubmitsScoreAndPresentsResult() {
        let scheduler = PenaltyBannerSchedulerSpy()
        let gameCenter = GameCenterServiceSpy()
        let adsService = AdsServiceSpy()
        let interfaces = GameModuleInterfaces { _ in GameCore(mode: .dungeonPlaceholder) }

        let viewModel = GameViewModel(
            mode: .dungeonPlaceholder,
            gameInterfaces: interfaces,
            gameCenterService: gameCenter,
            adsService: adsService,
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: scheduler
        )

        // スコア計算の前提となる指標をテスト用に固定し、期待値を明確にする
        viewModel.core.overrideMetricsForTesting(moveCount: 12, penaltyCount: 3, elapsedSeconds: 45)

        // Combine で監視している progress が .cleared へ変化した際の副作用を検証する
        viewModel.core.updateProgressForPenaltyFlow(.cleared)
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        XCTAssertTrue(viewModel.showingResult, "クリア後に結果画面表示フラグが立っていません")
        XCTAssertEqual(gameCenter.submittedScores.count, 1, "スコア送信が 1 回も行われていません")
        XCTAssertEqual(gameCenter.submittedScores.first?.value, viewModel.core.score, "送信されたスコア値が想定と異なります")
        XCTAssertEqual(gameCenter.submittedScores.first?.identifier, viewModel.mode.identifier, "スコア送信先のモード ID が一致していません")
    }

    /// 盤面タップで複数候補のあるカードを指定したマスへ確実にプレイできることを確認する
    func testBoardTapPlaysCardAtTappedDestinationWhenMultipleCandidatesExist() {
        let scheduler = PenaltyBannerSchedulerSpy()
        let gameCenter = GameCenterServiceSpy()
        let adsService = AdsServiceSpy()

        let mode = makeInventoryDungeonMode()
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.kingUpRight, pickupUses: 1))
        let interfaces = GameModuleInterfaces { _ in core }

        let viewModel = GameViewModel(
            mode: mode,
            gameInterfaces: interfaces,
            gameCenterService: gameCenter,
            adsService: adsService,
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: scheduler
        )

        // テスト中の余計なハプティクスを抑制する
        viewModel.boardBridge.updateHapticsSetting(isEnabled: false)

        guard
            let stack = core.handStacks.first,
            let topCard = stack.topCard
        else {
            XCTFail("初期手札の取得に失敗しました")
            return
        }

        let overrideVectors = [
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0)
        ]
        MoveCard.setTestMovementVectors(overrideVectors, for: topCard.move)
        defer { MoveCard.setTestMovementVectors(nil, for: topCard.move) }

        let candidateMoves = core.availableMoves().filter { candidate in
            candidate.stackID == stack.id && candidate.card.id == topCard.id
        }
        XCTAssertEqual(candidateMoves.count, 2, "複数候補が検出されませんでした")

        guard let stackIndex = core.handStacks.firstIndex(where: { $0.id == stack.id }) else {
            XCTFail("選択対象の手札スタックを特定できませんでした")
            return
        }

        viewModel.handleHandSlotTap(at: stackIndex)

        XCTAssertEqual(
            viewModel.selectedHandStackID,
            stack.id,
            "カード選択状態が更新されていません"
        )

        let expectedHighlights = Set(candidateMoves.map(\.destination))
        XCTAssertEqual(
            viewModel.boardBridge.forcedSelectionHighlightPoints,
            expectedHighlights,
            "カードタップ時のハイライト候補が想定と異なります"
        )
        XCTAssertTrue(
            viewModel.boardBridge.scene.latestHighlightPoints(for: .guideSingleCandidate).isEmpty,
            "カード選択中は他カード由来の単一候補ガイドを消す想定です"
        )
        XCTAssertTrue(
            viewModel.boardBridge.scene.latestHighlightPoints(for: .guideMultipleCandidate).isEmpty,
            "カード選択中は他カード由来の複数候補ガイドを消す想定です"
        )
        XCTAssertEqual(
            viewModel.boardBridge.scene.latestHighlightPoints(for: .forcedSelection),
            expectedHighlights,
            "カード選択中は選択カードの候補だけを Scene へ送る想定です"
        )
        XCTAssertNil(viewModel.boardBridge.animatingCard, "盤面タップ前にアニメーションが開始されています")

        let chosenMove = candidateMoves[1]

        core.handleTap(at: chosenMove.destination)

        guard let pendingRequest = core.boardTapPlayRequest else {
            XCTFail("BoardTapPlayRequest が設定されていません")
            return
        }

        XCTAssertEqual(pendingRequest.destination, chosenMove.destination, "BoardTapPlayRequest.destination が想定と異なります")
        XCTAssertEqual(pendingRequest.moveVector, chosenMove.moveVector, "BoardTapPlayRequest.moveVector が想定と異なります")

        // Combine の購読とアニメーション完了を待機する
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        XCTAssertEqual(core.current, chosenMove.destination, "盤面タップで指定したマスへ駒が移動していません")
        XCTAssertEqual(core.moveCount, 1, "カード使用回数が加算されていません")
        XCTAssertNil(core.boardTapPlayRequest, "処理後も BoardTapPlayRequest が残っています")
        XCTAssertNil(viewModel.selectedHandStackID, "カードプレイ後も選択状態が残っています")
        XCTAssertTrue(
            viewModel.boardBridge.forcedSelectionHighlightPoints.isEmpty,
            "カードプレイ後に強制ハイライトが解除されていません"
        )
        XCTAssertEqual(
            viewModel.boardBridge.scene.latestHighlightPoints(for: .guideSingleCandidate),
            viewModel.boardBridge.guideHighlightBuckets.singleVectorDestinations,
            "カードプレイ後は通常ガイドの単一候補が Scene へ戻る想定です"
        )
        XCTAssertEqual(
            viewModel.boardBridge.scene.latestHighlightPoints(for: .guideMultipleCandidate),
            viewModel.boardBridge.guideHighlightBuckets.multipleVectorDestinations,
            "カードプレイ後は通常ガイドの複数候補が Scene へ戻る想定です"
        )
    }

    /// カード未選択時の盤面タップは、単独候補なら移動し、複数カード競合なら選択を促す
    func testBoardTapWithoutSelectionTriggersPlayOrPromptsForCardConflicts() {
        XCTContext.runActivity(named: "複数候補カードのみでも移動が開始される") { _ in
            let scheduler = PenaltyBannerSchedulerSpy()
            let gameCenter = GameCenterServiceSpy()
            let adsService = AdsServiceSpy()

            let mode = makeInventoryDungeonMode()
            let core = GameCore(mode: mode)
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))
            let interfaces = GameModuleInterfaces { _ in core }

            let viewModel = GameViewModel(
                mode: mode,
                gameInterfaces: interfaces,
                gameCenterService: gameCenter,
                adsService: adsService,
                onRequestReturnToTitle: nil,
                penaltyBannerScheduler: scheduler
            )

            viewModel.boardBridge.updateHapticsSetting(isEnabled: false)

            guard
                let stack = core.handStacks.first,
                let topCard = stack.topCard
            else {
                XCTFail("初期手札の取得に失敗しました")
                return
            }

            // テスト用に左右 1 マス移動できる複数候補カードへ差し替える
            let overrideVectors = [
                MoveVector(dx: 1, dy: 0),
                MoveVector(dx: -1, dy: 0)
            ]
            MoveCard.setTestMovementVectors(overrideVectors, for: topCard.move)
            defer { MoveCard.setTestMovementVectors(nil, for: topCard.move) }

            let candidateMoves = core.availableMoves().filter { candidate in
                candidate.stackID == stack.id && candidate.card.id == topCard.id
            }
            XCTAssertEqual(candidateMoves.count, 2, "複数候補が検出されませんでした")

            // 右方向へのベクトルを指定し、BoardTapPlayRequest.resolvedMove が正しく再利用されるか検証する
            guard let chosenMove = candidateMoves.first(where: { $0.moveVector == MoveVector(dx: 1, dy: 0) }) else {
                XCTFail("右方向の候補を特定できませんでした")
                return
            }

            core.handleTap(at: chosenMove.destination)

            guard let pendingRequest = core.boardTapPlayRequest else {
                XCTFail("BoardTapPlayRequest が生成されていません")
                return
            }

            XCTAssertEqual(pendingRequest.stackID, stack.id, "BoardTapPlayRequest.stackID が想定と異なります")
            XCTAssertEqual(pendingRequest.destination, chosenMove.destination, "BoardTapPlayRequest.destination が想定と異なります")
            XCTAssertEqual(pendingRequest.moveVector, chosenMove.moveVector, "BoardTapPlayRequest.moveVector が想定と異なります")

            // Combine の購読と演出完了を待機する（0.7 秒でカード移動→盤面更新まで完了する）
            RunLoop.main.run(until: Date().addingTimeInterval(0.7))

            XCTAssertEqual(core.current, chosenMove.destination, "盤面タップ後に駒が目的地へ移動していません")
            XCTAssertEqual(core.moveCount, 1, "カード使用回数が加算されていません")
            XCTAssertNil(core.boardTapPlayRequest, "処理後に BoardTapPlayRequest が残っています")
            XCTAssertNil(viewModel.selectedHandStackID, "カードプレイ後も選択状態が残っています")
            XCTAssertTrue(viewModel.boardBridge.forcedSelectionHighlightPoints.isEmpty, "カードプレイ後に強制ハイライトが解除されていません")
            XCTAssertNil(viewModel.boardBridge.animatingCard, "演出完了後も animatingCard が解放されていません")
        }

        XCTContext.runActivity(named: "通常カードが混ざる競合でも選択を促す") { _ in
            let scheduler = PenaltyBannerSchedulerSpy()
            let gameCenter = GameCenterServiceSpy()
            let adsService = AdsServiceSpy()

            let mode = makeInventoryDungeonMode()
            let core = GameCore(mode: mode)
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))
            XCTAssertTrue(core.addDungeonInventoryCardForTesting(.kingUpRight, pickupUses: 1))
            let interfaces = GameModuleInterfaces { _ in core }

            let viewModel = GameViewModel(
                mode: mode,
                gameInterfaces: interfaces,
                gameCenterService: gameCenter,
                adsService: adsService,
                onRequestReturnToTitle: nil,
                penaltyBannerScheduler: scheduler
            )

            viewModel.boardBridge.updateHapticsSetting(isEnabled: false)

            guard
                let current = core.current,
                let multiCandidateStack = core.handStacks.first(where: { $0.topCard != nil }),
                let multiTopCard = multiCandidateStack.topCard,
                let singleCandidateStack = core.handStacks.first(where: { stack in
                    guard let card = stack.topCard else { return false }
                    return stack.id != multiCandidateStack.id && card.move != multiTopCard.move
                }),
                let singleTopCard = singleCandidateStack.topCard
            else {
                XCTFail("テスト前提となる手札を準備できませんでした")
                return
            }

            // 複数候補カードは左右 1 マス、通常カードは右 1 マスのみ移動できるように差し替える
            let multiOverride = [
                MoveVector(dx: 1, dy: 0),
                MoveVector(dx: -1, dy: 0)
            ]
            let singleOverride = [MoveVector(dx: 1, dy: 0)]
            MoveCard.setTestMovementVectors(multiOverride, for: multiTopCard.move)
            MoveCard.setTestMovementVectors(singleOverride, for: singleTopCard.move)
            defer {
                MoveCard.setTestMovementVectors(nil, for: multiTopCard.move)
                MoveCard.setTestMovementVectors(nil, for: singleTopCard.move)
            }

            let destination = current.offset(dx: 1, dy: 0)
            XCTAssertTrue(core.board.contains(destination), "目的地が盤外になっています")

            let relevantMoves = core.availableMoves().filter { $0.destination == destination }
            XCTAssertGreaterThanOrEqual(relevantMoves.count, 2, "想定した候補が揃っていません")
            XCTAssertNotNil(relevantMoves.first(where: { $0.stackID == multiCandidateStack.id }), "複数候補カードの移動が見つかりません")
            let singleVectorMove = relevantMoves.first(where: { $0.stackID == singleCandidateStack.id })
            XCTAssertNotNil(singleVectorMove, "通常カードの移動が見つかりません")

            core.handleTap(at: destination)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))

            XCTAssertEqual(core.current, current, "競合警告にもかかわらず駒が移動しています")
            XCTAssertEqual(core.moveCount, 0, "競合警告ではカードを消費しない想定です")
            XCTAssertNil(core.boardTapPlayRequest, "警告処理後に BoardTapPlayRequest が残っています")
            XCTAssertNil(viewModel.boardBridge.animatingCard, "警告表示中にもかかわらずアニメーションが開始されています")
            XCTAssertEqual(viewModel.boardTapSelectionWarning?.destination, destination, "警告に記録された目的地が一致していません")
            XCTAssertEqual(
                viewModel.boardTapSelectionWarning?.message,
                "複数のカードが同じマスを指定しています。手札から使いたいカードを選んでからマスをタップしてください。",
                "警告メッセージが仕様と一致していません"
            )
        }
    }

    /// 基本移動とカード候補が重なる場合でも、ViewModel 経由ではカードを消費せず基本移動を実行する
    func testBoardTapExecutesBasicMoveBeforeMatchingCardMove() {
        let scheduler = PenaltyBannerSchedulerSpy()
        let gameCenter = GameCenterServiceSpy()
        let adsService = AdsServiceSpy()
        let origin = GridPoint(x: 0, y: 0)
        let destination = GridPoint(x: 1, y: 0)
        let blocker = GridPoint(x: 2, y: 0)
        let regulation = GameMode.Regulation(
            boardSize: BoardGeometry.standardSize,
            handSize: 1,
            nextPreviewCount: 0,
            allowsStacking: true,
            deckPreset: .standardLight,
            spawnRule: .fixed(origin),
            penalties: GameMode.PenaltySettings(
                deadlockPenaltyCost: 0,
                manualRedrawPenaltyCost: 0,
                manualDiscardPenaltyCost: 0,
                revisitPenaltyCost: 0
            ),
            impassableTilePoints: [blocker],
            completionRule: .dungeonExit(exitPoint: GridPoint(x: 4, y: 4)),
            dungeonRules: DungeonRules(
                difficulty: .growth,
                failureRule: DungeonFailureRule(initialHP: 3, turnLimit: nil),
                allowsBasicOrthogonalMove: true
            )
        )
        let mode = GameMode(
            identifier: .dungeonFloor,
            displayName: "基本移動優先テスト",
            regulation: regulation,
            leaderboardEligible: false
        )
        let deck = Deck.makeTestDeck(cards: [.rayRight], configuration: regulation.deckPreset.configuration)
        let core = GameCore.makeTestInstance(deck: deck, current: origin, mode: mode)
        let initialCardID = core.handStacks.first?.topCard?.id
        let interfaces = GameModuleInterfaces { _ in core }
        let viewModel = GameViewModel(
            mode: mode,
            gameInterfaces: interfaces,
            gameCenterService: gameCenter,
            adsService: adsService,
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: scheduler
        )

        viewModel.boardBridge.updateHapticsSetting(isEnabled: false)
        core.handleTap(at: destination)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(core.current, destination, "基本移動リクエストが ViewModel 経由で実行されていません")
        XCTAssertEqual(core.moveCount, 1, "基本移動は1手として数える想定です")
        XCTAssertEqual(core.handStacks.first?.topCard?.id, initialCardID, "基本移動ではカードを消費しない想定です")
        XCTAssertNil(core.boardTapPlayRequest, "基本移動で届くマスではカード使用リクエストを残さない想定です")
        XCTAssertNil(core.boardTapBasicMoveRequest, "基本移動リクエストは処理後にクリアされる想定です")
        XCTAssertNil(viewModel.boardBridge.animatingCard, "基本移動ではカード演出を開始しない想定です")
    }

    /// 複数の複数候補カードが同一マスへ移動可能な状態で盤面をタップした場合、警告が表示されることを確認する
    func testBoardTapWithoutSelectionPresentsWarningWhenConflictingMultiCandidateCardsExist() {
        let scheduler = PenaltyBannerSchedulerSpy()
        let gameCenter = GameCenterServiceSpy()
        let adsService = AdsServiceSpy()

        let mode = makeInventoryDungeonMode()
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.kingUpRight, pickupUses: 1))
        let interfaces = GameModuleInterfaces { _ in core }

        let viewModel = GameViewModel(
            mode: mode,
            gameInterfaces: interfaces,
            gameCenterService: gameCenter,
            adsService: adsService,
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: scheduler
        )

        // テスト環境ではハプティクスを無効化し、物理デバイス固有の挙動へ依存しないようにする
        viewModel.updateHapticsSetting(isEnabled: false)

        guard
            let current = core.current,
            let firstStack = core.handStacks.first(where: { $0.topCard != nil }),
            let secondStack = core.handStacks.first(where: { stack in
                stack.id != firstStack.id && stack.topCard != nil
            }),
            let firstCard = firstStack.topCard,
            let secondCard = secondStack.topCard
        else {
            XCTFail("テスト前提となる複数の手札スタックを準備できませんでした")
            return
        }

        // 双方のカードで左右 1 マス移動できる複数候補カードへ差し替え、同一目的地へ到達できるようにする
        let overrideVectors = [
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0)
        ]
        MoveCard.setTestMovementVectors(overrideVectors, for: firstCard.move)
        MoveCard.setTestMovementVectors(overrideVectors, for: secondCard.move)
        defer {
            MoveCard.setTestMovementVectors(nil, for: firstCard.move)
            MoveCard.setTestMovementVectors(nil, for: secondCard.move)
        }

        let destination = current.offset(dx: 1, dy: 0)
        XCTAssertTrue(core.board.contains(destination), "目的地が盤外になっています")

        let availableMoves = core.availableMoves()
        let destinationMoves = availableMoves.filter { $0.destination == destination }
        XCTAssertGreaterThanOrEqual(destinationMoves.count, 2, "同一マスへ移動できる候補が不足しています")

        let destinationStackIDs = Set(destinationMoves.map(\.stackID))
        XCTAssertGreaterThanOrEqual(destinationStackIDs.count, 2, "異なるスタックからの候補が揃っていません")

        for stackID in destinationStackIDs {
            let count = availableMoves.filter { $0.stackID == stackID }.count
            XCTAssertGreaterThan(count, 1, "単一候補カードが含まれており、テスト条件を満たしていません")
        }

        core.handleTap(at: destination)

        // Combine の購読を通じて ViewModel 側の警告状態が更新されるまで待機する
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(core.current, current, "警告表示にもかかわらず駒が移動しています")
        XCTAssertNil(core.boardTapPlayRequest, "処理後に BoardTapPlayRequest が残存しています")
        XCTAssertNil(viewModel.boardBridge.animatingCard, "警告表示中にもかかわらずアニメーションが開始されています")
        XCTAssertEqual(
            viewModel.boardTapSelectionWarning?.destination,
            destination,
            "警告に記録された目的地がタップ座標と一致していません"
        )
        XCTAssertEqual(
            viewModel.boardTapSelectionWarning?.message,
            "複数のカードが同じマスを指定しています。手札から使いたいカードを選んでからマスをタップしてください。",
            "警告メッセージが仕様と一致していません"
        )
        XCTAssertEqual(
            viewModel.boardTapSelectionWarning?.highlightedStackIDs,
            destinationStackIDs,
            "警告中に光らせる手札が、同じマスへ到達できる候補と一致していません"
        )
        XCTAssertTrue(viewModel.isBoardTapSelectionWarningHighlighting(firstStack), "競合対象の先頭スタックがハイライト対象になっていません")
        XCTAssertTrue(viewModel.isBoardTapSelectionWarningHighlighting(secondStack), "競合対象の2枚目スタックがハイライト対象になっていません")

        if let firstIndex = core.handStacks.firstIndex(where: { $0.id == firstStack.id }) {
            viewModel.handleHandSlotTap(at: firstIndex)
            XCTAssertNil(viewModel.boardTapSelectionWarning, "手札を選んだ後も競合ハイライト警告が残っています")
        } else {
            XCTFail("競合対象スタックの手札位置を取得できませんでした")
        }
    }

    /// 単一ベクトルカードが競合に含まれる場合でも、警告を表示して消費カードを選ばせる
    func testBoardTapWithoutSelectionPresentsWarningWhenSingleVectorCandidateExists() {
        let scheduler = PenaltyBannerSchedulerSpy()
        let gameCenter = GameCenterServiceSpy()
        let adsService = AdsServiceSpy()

        let mode = makeInventoryDungeonMode()
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.kingUpRight, pickupUses: 1))
        let interfaces = GameModuleInterfaces { _ in core }

        let viewModel = GameViewModel(
            mode: mode,
            gameInterfaces: interfaces,
            gameCenterService: gameCenter,
            adsService: adsService,
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: scheduler
        )

        // テスト実行中は不要なハプティクスを抑止し、環境差異に左右されないようにする
        viewModel.updateHapticsSetting(isEnabled: false)

        guard
            let current = core.current,
            let multiStack = core.handStacks.first(where: { $0.topCard != nil }),
            let singleStack = core.handStacks.first(where: { stack in
                guard let card = stack.topCard else { return false }
                return stack.id != multiStack.id && card.move != multiStack.topCard?.move
            }),
            let multiCard = multiStack.topCard,
            let singleCard = singleStack.topCard
        else {
            XCTFail("テスト前提となる手札スタックを準備できませんでした")
            return
        }

        // 複数候補カードには左右 1 マス、単一カードには右 1 マスのみ移動できるベクトルを割り当てて競合状況を再現する
        let multiOverride = [
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0)
        ]
        let singleOverride = [MoveVector(dx: 1, dy: 0)]
        MoveCard.setTestMovementVectors(multiOverride, for: multiCard.move)
        MoveCard.setTestMovementVectors(singleOverride, for: singleCard.move)
        defer {
            MoveCard.setTestMovementVectors(nil, for: multiCard.move)
            MoveCard.setTestMovementVectors(nil, for: singleCard.move)
        }

        let destination = current.offset(dx: 1, dy: 0)
        XCTAssertTrue(core.board.contains(destination), "目的地が盤外になっています")

        let destinationCandidates = core.availableMoves().filter { $0.destination == destination }
        XCTAssertGreaterThanOrEqual(destinationCandidates.count, 2, "同一マスへ移動できる候補が不足しています")
        XCTAssertNotNil(
            destinationCandidates.first(where: { $0.stackID == multiStack.id && $0.card.move.movementVectors.count > 1 }),
            "複数ベクトルカードの候補が揃っていません"
        )
        XCTAssertNotNil(
            destinationCandidates.first(where: { $0.stackID == singleStack.id && $0.card.move.movementVectors.count == 1 }),
            "単一ベクトルカードの候補が揃っていません"
        )

        core.handleTap(at: destination)

        // Combine の購読を通じて ViewModel 側の警告状態が更新されるまで待機する
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(core.current, current, "警告表示にもかかわらず駒が移動しています")
        XCTAssertEqual(core.moveCount, 0, "警告表示ではカード使用回数を加算しない想定です")
        XCTAssertNil(core.boardTapPlayRequest, "警告処理後に BoardTapPlayRequest が残っています")
        XCTAssertNil(viewModel.boardBridge.animatingCard, "警告表示中にもかかわらずアニメーションが開始されています")
        XCTAssertEqual(viewModel.boardTapSelectionWarning?.destination, destination, "警告に記録された目的地が一致していません")
        XCTAssertEqual(
            viewModel.boardTapSelectionWarning?.message,
            "複数のカードが同じマスを指定しています。手札から使いたいカードを選んでからマスをタップしてください。",
            "警告メッセージが仕様と一致していません"
        )
        XCTAssertEqual(
            viewModel.boardTapSelectionWarning?.highlightedStackIDs,
            Set(destinationCandidates.map(\.stackID)),
            "単一方向カードを含む競合でも、対象手札だけをハイライトする想定です"
        )
        XCTAssertTrue(viewModel.isBoardTapSelectionWarningHighlighting(multiStack), "複数候補カードがハイライト対象になっていません")
        XCTAssertTrue(viewModel.isBoardTapSelectionWarningHighlighting(singleStack), "単一方向カードがハイライト対象になっていません")
    }

    /// 斜め選択カード同士が同一点を指す場合も警告表示が行われることを確認する（キャンペーン 3-2 相当）
    func testBoardTapWithoutSelectionPresentsWarningWhenDiagonalChoiceStacksConflict() {
        let scheduler = PenaltyBannerSchedulerSpy()
        let gameCenter = GameCenterServiceSpy()
        let adsService = AdsServiceSpy()

        // 標準モードのレギュレーションを基に、斜め選択カードを含む山札構成へ差し替えて再現性を高める
        var diagonalRegulation = GameMode.dungeonPlaceholder.regulationSnapshot
        diagonalRegulation.deckPreset = .standardLight
        let diagonalMode = GameMode(
            identifier: .dungeonFloor,
            displayName: "斜め選択警告テスト",
            regulation: diagonalRegulation,
            leaderboardEligible: false
        )

        let core = GameCore(mode: diagonalMode)
        let interfaces = GameModuleInterfaces { _ in core }

        let viewModel = GameViewModel(
            mode: diagonalMode,
            gameInterfaces: interfaces,
            gameCenterService: gameCenter,
            adsService: adsService,
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: scheduler
        )

        // 実機依存のフィードバックはテスト結果へ影響しないように無効化する
        viewModel.updateHapticsSetting(isEnabled: false)

        guard
            let current = core.current,
            let firstStack = core.handStacks.first(where: { $0.topCard != nil }),
            let secondStack = core.handStacks.first(where: { stack in
                stack.id != firstStack.id && stack.topCard != nil
            }),
            let firstCard = firstStack.topCard,
            let secondCard = secondStack.topCard
        else {
            XCTFail("斜め選択カードの競合テストに必要な手札を準備できませんでした")
            return
        }

        // 双方のカードへ斜め方向の移動ベクトルを付与し、右上マスで競合させる
        let diagonalOverride = [
            MoveVector(dx: 1, dy: 1),
            MoveVector(dx: -1, dy: -1)
        ]
        MoveCard.setTestMovementVectors(diagonalOverride, for: firstCard.move)
        MoveCard.setTestMovementVectors(diagonalOverride, for: secondCard.move)
        defer {
            MoveCard.setTestMovementVectors(nil, for: firstCard.move)
            MoveCard.setTestMovementVectors(nil, for: secondCard.move)
        }

        let destination = current.offset(dx: 1, dy: 1)
        XCTAssertTrue(core.board.contains(destination), "目的地が盤外になっており、競合を再現できません")

        let destinationMoves = core.availableMoves().filter { $0.destination == destination }
        XCTAssertGreaterThanOrEqual(destinationMoves.count, 2, "同一点へ到達できる候補が揃っていません")
        XCTAssertEqual(Set(destinationMoves.map(\.stackID)).count, 2, "異なるスタック同士で競合する条件を満たしていません")

        core.handleTap(at: destination)

        // Combine の通知を経由して警告状態が更新されるまで待機する
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(core.current, current, "警告表示にもかかわらず駒が移動しています")
        XCTAssertNil(core.boardTapPlayRequest, "警告処理後に BoardTapPlayRequest が残っています")
        XCTAssertNil(viewModel.boardBridge.animatingCard, "警告表示中にもかかわらずアニメーションが開始されています")
        XCTAssertNotNil(viewModel.boardTapSelectionWarning, "斜め選択カードの競合にも関わらず警告が表示されていません")
        XCTAssertEqual(viewModel.boardTapSelectionWarning?.destination, destination, "警告に記録された目的地が一致していません")
        XCTAssertEqual(
            viewModel.boardTapSelectionWarning?.message,
            "複数のカードが同じマスを指定しています。手札から使いたいカードを選んでからマスをタップしてください。",
            "警告メッセージが仕様と一致していません"
        )
    }

    /// 盤外制約で候補数が片側だけになっても複数候補カード同士の競合警告が発生することを確認する
    func testBoardTapWithoutSelectionPresentsWarningWhenOutOfBoundsShrinksMultiCandidateOptions() {
        let scheduler = PenaltyBannerSchedulerSpy()
        let gameCenter = GameCenterServiceSpy()
        let adsService = AdsServiceSpy()

        // 左下隅スタートのモードを構築し、盤外判定によって候補が欠ける状況を明示的に再現する
        var edgeRegulation = GameMode.dungeonPlaceholder.regulationSnapshot
        edgeRegulation.spawnRule = .fixed(GridPoint(x: 0, y: 0))
        let edgeMode = GameMode(
            identifier: .dungeonFloor,
            displayName: "端テスト",
            regulation: edgeRegulation,
            leaderboardEligible: false
        )

        let core = GameCore(mode: edgeMode)
        let interfaces = GameModuleInterfaces { _ in core }

        let viewModel = GameViewModel(
            mode: edgeMode,
            gameInterfaces: interfaces,
            gameCenterService: gameCenter,
            adsService: adsService,
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: scheduler
        )

        // テスト環境ではハプティクスを無効化し、実機依存の副作用を排除する
        viewModel.updateHapticsSetting(isEnabled: false)

        guard
            let current = core.current,
            current == GridPoint(x: 0, y: 0),
            let firstStack = core.handStacks.first(where: { $0.topCard != nil }),
            let secondStack = core.handStacks.first(where: { stack in
                stack.id != firstStack.id && stack.topCard != nil
            }),
            let firstCard = firstStack.topCard,
            let secondCard = secondStack.topCard
        else {
            XCTFail("盤外テスト用の初期手札や現在地を取得できませんでした")
            return
        }

        // 左端にいるため、斜め選択カードのうち左方向だけが盤外となり、候補数が片側に縮む状況を再現する
        let overrideVectors = [
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0)
        ]
        MoveCard.setTestMovementVectors(overrideVectors, for: firstCard.move)
        MoveCard.setTestMovementVectors(overrideVectors, for: secondCard.move)
        defer {
            MoveCard.setTestMovementVectors(nil, for: firstCard.move)
            MoveCard.setTestMovementVectors(nil, for: secondCard.move)
        }

        let destination = current.offset(dx: 1, dy: 0)
        XCTAssertTrue(core.board.contains(destination), "右隣のマスが盤外になっています")

        let availableMoves = core.availableMoves()
        let destinationMoves = availableMoves.filter { $0.destination == destination }
        XCTAssertGreaterThanOrEqual(destinationMoves.count, 2, "同一マスへ到達できる候補が不足しています")

        let destinationStackIDs = Set(destinationMoves.map(\.stackID))
        XCTAssertGreaterThanOrEqual(destinationStackIDs.count, 2, "異なるスタックからの候補が揃っていません")

        for stackID in destinationStackIDs {
            let stackMoves = availableMoves.filter { $0.stackID == stackID }
            XCTAssertEqual(stackMoves.count, 1, "盤外制約で片側のみになる前提が崩れています")
        }

        XCTAssertTrue(destinationMoves.allSatisfy { $0.card.move.movementVectors.count > 1 }, "複数候補カードのみで競合する前提が崩れています")

        core.handleTap(at: destination)

        // Combine の通知が伝搬するまで少し待機し、警告表示の有無を検証する
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))

        XCTAssertEqual(core.current, current, "警告が出たにもかかわらず駒が移動しています")
        XCTAssertNil(core.boardTapPlayRequest, "警告処理後に BoardTapPlayRequest が残っています")
        XCTAssertNil(viewModel.boardBridge.animatingCard, "警告表示中にもかかわらずアニメーションが開始されています")
        XCTAssertEqual(viewModel.boardTapSelectionWarning?.destination, destination, "警告に記録された目的地が一致していません")
        XCTAssertEqual(
            viewModel.boardTapSelectionWarning?.message,
            "複数のカードが同じマスを指定しています。手札から使いたいカードを選んでからマスをタップしてください。",
            "警告メッセージが仕様と一致していません"
        )
    }

    /// 単一方向カードをタップした際は盤面タップを挟まずに即時移動することを確認する
    func testHandleHandSlotTapImmediatelyPlaysSingleCandidateCard() {
        let scheduler = PenaltyBannerSchedulerSpy()
        let gameCenter = GameCenterServiceSpy()
        let adsService = AdsServiceSpy()

        let core = GameCore(mode: .dungeonPlaceholder)
        let interfaces = GameModuleInterfaces { _ in core }

        let viewModel = GameViewModel(
            mode: .dungeonPlaceholder,
            gameInterfaces: interfaces,
            gameCenterService: gameCenter,
            adsService: adsService,
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: scheduler
        )

        // ハプティクスが不要なテスト環境では無効化しておく
        viewModel.updateHapticsSetting(isEnabled: false)

        // 実際に使用可能なスタックを探索し、単一候補であることを確かめてから検証する
        guard let usableIndex = core.handStacks.firstIndex(where: { viewModel.isCardUsable($0) }) else {
            XCTFail("使用可能な手札スタックを検出できませんでした")
            return
        }

        let stack = core.handStacks[usableIndex]
        guard let topCard = stack.topCard else {
            XCTFail("手札スタックのトップカードが取得できませんでした")
            return
        }

        let candidateMoves = core.availableMoves().filter { candidate in
            candidate.stackID == stack.id && candidate.card.id == topCard.id
        }

        XCTAssertEqual(candidateMoves.count, 1, "単一候補カードでない場合はテスト前提が満たせません")
        guard let expectedMove = candidateMoves.first else {
            XCTFail("単一候補の ResolvedCardMove を特定できませんでした")
            return
        }

        viewModel.handleHandSlotTap(at: usableIndex)

        // 盤面タップを挟まずに移動が開始された場合、選択状態やハイライトは直ちにクリアされる想定
        XCTAssertNil(viewModel.selectedHandStackID, "単一候補カード実行後に選択状態が残っています")
        XCTAssertTrue(
            viewModel.boardBridge.forcedSelectionHighlightPoints.isEmpty,
            "単一候補カード実行後に強制ハイライトが残存しています"
        )
        XCTAssertEqual(
            viewModel.boardBridge.animatingCard?.id,
            topCard.id,
            "単一候補カードのアニメーションが開始されていません"
        )

        // アニメーション完了と GameCore への結果反映を待機する
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        XCTAssertEqual(core.current, expectedMove.destination, "単一候補カードの移動先が一致しません")
        XCTAssertEqual(core.moveCount, 1, "単一候補カード実行後の移動回数が加算されていません")
        XCTAssertNil(core.boardTapPlayRequest, "盤面タップ要求が不要に残っています")
    }

    func testGuideOffBoardTapWithoutSelectionDoesNotMoveByBasicCandidate() {
        let mode = makeInventoryDungeonMode(allowsBasicOrthogonalMove: true)
        let core = GameCore(mode: mode)
        let interfaces = GameModuleInterfaces { _ in core }
        let viewModel = GameViewModel(
            mode: mode,
            gameInterfaces: interfaces,
            gameCenterService: GameCenterServiceSpy(),
            adsService: AdsServiceSpy(),
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: PenaltyBannerSchedulerSpy()
        )
        viewModel.updateHapticsSetting(isEnabled: false)
        viewModel.updateGuideMode(enabled: false)

        let start = core.current
        let destination = GridPoint(x: 3, y: 2)
        core.handleTap(at: destination)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(core.current, start, "ガイドOFFでは未選択の盤面タップで基本移動しない想定です")
        XCTAssertNil(core.boardTapBasicMoveRequest, "無視した基本移動リクエストは残さない想定です")
        XCTAssertTrue(viewModel.boardBridge.forcedSelectionHighlightPoints.isEmpty)
    }

    func testGuideOffBasicMoveCardSelectionEnablesCandidateTap() {
        let mode = makeInventoryDungeonMode(allowsBasicOrthogonalMove: true)
        let core = GameCore(mode: mode)
        let interfaces = GameModuleInterfaces { _ in core }
        let viewModel = GameViewModel(
            mode: mode,
            gameInterfaces: interfaces,
            gameCenterService: GameCenterServiceSpy(),
            adsService: AdsServiceSpy(),
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: PenaltyBannerSchedulerSpy()
        )
        viewModel.updateHapticsSetting(isEnabled: false)
        viewModel.updateGuideMode(enabled: false)

        let destination = GridPoint(x: 3, y: 2)
        viewModel.handleHandSlotTap(at: GameViewModel.dungeonBasicMoveSlotIndex)

        XCTAssertTrue(viewModel.isBasicMoveCardSelected, "10枠目の基本移動カードが選択状態になる想定です")
        XCTAssertEqual(
            viewModel.boardBridge.forcedSelectionHighlightPoints,
            Set(core.availableBasicOrthogonalMoves().map(\.destination)),
            "基本移動カード選択時は上下左右候補を強制ハイライトする想定です"
        )

        core.handleTap(at: destination)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        XCTAssertEqual(core.current, destination, "基本移動カード選択後は候補タップで移動する想定です")
        XCTAssertFalse(viewModel.isBasicMoveCardSelected, "移動確定後は基本移動選択を解除します")
        XCTAssertTrue(core.dungeonInventoryEntries.isEmpty, "基本移動カードはインベントリへ混ざらない想定です")
    }

    func testGuideOffSingleCandidateCardRequiresBoardConfirmation() {
        let mode = makeInventoryDungeonMode()
        let core = GameCore(mode: mode)
        XCTAssertTrue(core.addDungeonInventoryCardForTesting(.straightRight2, pickupUses: 1))
        let interfaces = GameModuleInterfaces { _ in core }
        let viewModel = GameViewModel(
            mode: mode,
            gameInterfaces: interfaces,
            gameCenterService: GameCenterServiceSpy(),
            adsService: AdsServiceSpy(),
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: PenaltyBannerSchedulerSpy()
        )
        viewModel.updateHapticsSetting(isEnabled: false)
        viewModel.updateGuideMode(enabled: false)

        let start = core.current
        let stackIndex = try! XCTUnwrap(core.handStacks.firstIndex { $0.representativeMove == .straightRight2 })
        let destination = GridPoint(x: 3, y: 2)

        viewModel.handleHandSlotTap(at: stackIndex)

        XCTAssertEqual(core.current, start, "ガイドOFFでは単一候補カードも手札タップだけでは動かない想定です")
        XCTAssertNil(viewModel.boardBridge.animatingCard)
        XCTAssertEqual(viewModel.selectedHandStackID, core.handStacks[stackIndex].id)
        XCTAssertEqual(viewModel.boardBridge.forcedSelectionHighlightPoints, [destination])

        core.handleTap(at: destination)
        RunLoop.main.run(until: Date().addingTimeInterval(0.35))

        XCTAssertEqual(core.current, destination, "カード選択後の候補タップで移動する想定です")
        XCTAssertNil(viewModel.selectedHandStackID)
        XCTAssertEqual(core.dungeonInventoryEntries.first { $0.card == .straightRight2 }?.pickupUses, nil)
    }

    private func makeInventoryDungeonMode(
        spawn: GridPoint = GridPoint(x: 2, y: 2),
        exit: GridPoint = GridPoint(x: 4, y: 4),
        allowsBasicOrthogonalMove: Bool = false
    ) -> GameMode {
        GameMode(
            identifier: .dungeonFloor,
            displayName: "塔攻略入力テスト",
            regulation: GameMode.Regulation(
                boardSize: BoardGeometry.standardSize,
                handSize: 5,
                nextPreviewCount: 0,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: .fixed(spawn),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 0,
                    manualRedrawPenaltyCost: 0,
                    manualDiscardPenaltyCost: 0,
                    revisitPenaltyCost: 0
                ),
                completionRule: .dungeonExit(exitPoint: exit),
                dungeonRules: DungeonRules(
                    difficulty: .growth,
                    failureRule: DungeonFailureRule(initialHP: 3, turnLimit: nil),
                    allowsBasicOrthogonalMove: allowsBasicOrthogonalMove,
                    cardAcquisitionMode: .inventoryOnly
                )
            ),
            leaderboardEligible: false
        )
    }

    #if canImport(SpriteKit)
    /// SpriteKit シーンのサイズ同期と GameCore の紐付けが正しく行われるかを確認する
    func testSceneSizeSyncOnAppear() {
        let interfaces = GameModuleInterfaces { _ in GameCore(mode: .dungeonPlaceholder) }
        let viewModel = GameViewModel(
            mode: .dungeonPlaceholder,
            gameInterfaces: interfaces,
            gameCenterService: GameCenterServiceSpy(),
            adsService: AdsServiceSpy(),
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: PenaltyBannerSchedulerSpy()
        )

        // onAppear 相当のメソッドを呼び出し、SpriteKit シーンのサイズ更新を検証する
        viewModel.boardBridge.configureSceneOnAppear(width: 160)

        XCTAssertEqual(viewModel.boardBridge.scene.size.width, 160, accuracy: 0.001, "SpriteKit シーンの幅が同期されていません")
        XCTAssertIdentical(viewModel.boardBridge.scene.gameCore as AnyObject?, viewModel.core, "GameScene.gameCore が GameCore と一致していません")
    }
    #endif
}

// MARK: - テスト用スパイ実装

/// バナー表示スケジューラの呼び出し状況を記録するスパイ
private final class PenaltyBannerSchedulerSpy: PenaltyBannerScheduling {
    /// scheduleAutoDismiss が呼ばれた回数
    private(set) var scheduleCallCount = 0
    /// 直近の遅延秒数
    private(set) var lastScheduledDelay: TimeInterval?
    /// cancel が呼び出された回数
    private(set) var cancelCallCount = 0

    func scheduleAutoDismiss(after delay: TimeInterval, handler: @escaping () -> Void) {
        scheduleCallCount += 1
        lastScheduledDelay = delay
        // 即座に handler を実行せず、ViewModel の状態をテストで観測できるようにする
    }

    func cancel() {
        cancelCallCount += 1
    }
}

/// GameCenterServiceProtocol の呼び出し内容を記録するスパイ
private final class GameCenterServiceSpy: GameCenterServiceProtocol {
    /// 送信されたスコアとモード ID の履歴
    private(set) var submittedScores: [(identifier: GameMode.Identifier, value: Int)] = []
    var isAuthenticated: Bool = true

    func authenticateLocalPlayer(completion: ((Bool) -> Void)?) {
        completion?(true)
    }

    func submitScore(_ score: Int, for modeIdentifier: GameMode.Identifier) {
        submittedScores.append((identifier: modeIdentifier, value: score))
    }

    func showLeaderboard(for modeIdentifier: GameMode.Identifier) {}
}

/// AdsServiceProtocol を最小限に満たすスパイ
private final class AdsServiceSpy: AdsServiceProtocol {
    func showInterstitial() {}
    func resetPlayFlag() {}
    func disableAds() {}
    func showRewardedAd() async -> Bool { true }
    func requestTrackingAuthorization() async {}
    func requestConsentIfNeeded() async {}
    func refreshConsentStatus() async {}
}
