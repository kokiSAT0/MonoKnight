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
        let interfaces = GameModuleInterfaces { _ in GameCore(mode: .standard) }

        let viewModel = GameViewModel(
            mode: .standard,
            gameInterfaces: interfaces,
            gameCenterService: gameCenter,
            adsService: adsService,
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: scheduler
        )

        // Combine 経由の購読が動作するかを確認するため、GameCore 側でペナルティイベントを発火させる
        viewModel.core.updatePenaltyEventID(UUID())
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))

        XCTAssertTrue(viewModel.isShowingPenaltyBanner, "ペナルティ発生時にバナーが表示されていません")
        XCTAssertEqual(scheduler.scheduleCallCount, 1, "自動クローズのスケジュールが登録されていません")
        XCTAssertEqual(scheduler.lastScheduledDelay, 2.6, accuracy: 0.001, "バナー自動クローズの遅延秒数が仕様と一致しません")

        // メニュー操作で手動ペナルティを適用すると、バナー表示がキャンセルされる想定
        viewModel.performMenuAction(.manualPenalty(penaltyCost: viewModel.core.mode.manualRedrawPenaltyCost))

        XCTAssertEqual(scheduler.cancelCallCount, 1, "手動ペナルティ適用時にバナーのキャンセルが呼ばれていません")
        XCTAssertFalse(viewModel.isShowingPenaltyBanner, "キャンセル後もバナーが表示されたままです")
    }

    /// ゲームクリア時にスコア送信と結果画面表示が自動的に実施されることを確認する
    func testProgressClearedSubmitsScoreAndPresentsResult() {
        let scheduler = PenaltyBannerSchedulerSpy()
        let gameCenter = GameCenterServiceSpy()
        let adsService = AdsServiceSpy()
        let interfaces = GameModuleInterfaces { _ in GameCore(mode: .standard) }

        let viewModel = GameViewModel(
            mode: .standard,
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

        let core = GameCore(mode: .standard)
        let interfaces = GameModuleInterfaces { _ in core }

        let viewModel = GameViewModel(
            mode: .standard,
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
    }

    /// カード未選択時でも盤面タップで移動が開始され、通常カードが優先されることを確認する
    func testBoardTapWithoutSelectionTriggersPlayAndPrefersSingleVectorCards() {
        XCTContext.runActivity(named: "複数候補カードのみでも移動が開始される") { _ in
            let scheduler = PenaltyBannerSchedulerSpy()
            let gameCenter = GameCenterServiceSpy()
            let adsService = AdsServiceSpy()

            let core = GameCore(mode: .standard)
            let interfaces = GameModuleInterfaces { _ in core }

            let viewModel = GameViewModel(
                mode: .standard,
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

        XCTContext.runActivity(named: "通常カードが存在する場合はそちらが優先される") { _ in
            let scheduler = PenaltyBannerSchedulerSpy()
            let gameCenter = GameCenterServiceSpy()
            let adsService = AdsServiceSpy()

            let core = GameCore(mode: .standard)
            let interfaces = GameModuleInterfaces { _ in core }

            let viewModel = GameViewModel(
                mode: .standard,
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

            guard let pendingRequest = core.boardTapPlayRequest else {
                XCTFail("BoardTapPlayRequest が生成されていません")
                return
            }

            XCTAssertEqual(pendingRequest.stackID, singleCandidateStack.id, "通常カードが優先されていません")
            XCTAssertEqual(pendingRequest.moveVector, MoveVector(dx: 1, dy: 0), "選択された移動ベクトルが想定と異なります")

            RunLoop.main.run(until: Date().addingTimeInterval(0.7))

            XCTAssertEqual(core.current, destination, "盤面タップで選択した通常カードの移動が反映されていません")
            XCTAssertEqual(core.moveCount, 1, "カード使用回数が加算されていません")
            XCTAssertNil(core.boardTapPlayRequest, "処理後に BoardTapPlayRequest が残っています")
            XCTAssertNil(viewModel.selectedHandStackID, "カードプレイ後も選択状態が残っています")
            XCTAssertTrue(viewModel.boardBridge.forcedSelectionHighlightPoints.isEmpty, "カードプレイ後に強制ハイライトが解除されていません")
            XCTAssertNil(viewModel.boardBridge.animatingCard, "演出完了後も animatingCard が解放されていません")
        }
    }

    /// 複数の複数候補カードが同一マスへ移動可能な状態で盤面をタップした場合、警告が表示されることを確認する
    func testBoardTapWithoutSelectionPresentsWarningWhenConflictingMultiCandidateCardsExist() {
        let scheduler = PenaltyBannerSchedulerSpy()
        let gameCenter = GameCenterServiceSpy()
        let adsService = AdsServiceSpy()

        let core = GameCore(mode: .standard)
        let interfaces = GameModuleInterfaces { _ in core }

        let viewModel = GameViewModel(
            mode: .standard,
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
    }

    /// 単一ベクトルカードが競合に含まれる場合は警告が表示されず、自動的に通常カードが消費されることを確認する
    func testBoardTapWithoutSelectionSkipsWarningWhenSingleVectorCandidateExists() {
        let scheduler = PenaltyBannerSchedulerSpy()
        let gameCenter = GameCenterServiceSpy()
        let adsService = AdsServiceSpy()

        let core = GameCore(mode: .standard)
        let interfaces = GameModuleInterfaces { _ in core }

        let viewModel = GameViewModel(
            mode: .standard,
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

        // Combine の購読を通じたアニメーション処理完了まで十分な時間待機する（約 0.7 秒で移動が完了する）
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))

        XCTAssertEqual(core.current, destination, "単一ベクトルカードが自動消費されず、駒の位置が更新されていません")
        XCTAssertEqual(core.moveCount, 1, "カード使用回数が加算されていません")
        XCTAssertNil(core.boardTapPlayRequest, "処理後に BoardTapPlayRequest が残っています")
        XCTAssertNil(viewModel.boardTapSelectionWarning, "単一ベクトルカードが存在するにもかかわらず警告が残っています")
        XCTAssertNil(viewModel.selectedHandStackID, "カードプレイ後も選択状態が残っています")
        XCTAssertTrue(viewModel.boardBridge.forcedSelectionHighlightPoints.isEmpty, "カードプレイ後に強制ハイライトが解除されていません")
        XCTAssertNil(viewModel.boardBridge.animatingCard, "演出完了後も animatingCard が解放されていません")
    }

    /// 斜め選択カード同士が同一点を指す場合も警告表示が行われることを確認する（キャンペーン 3-2 相当）
    func testBoardTapWithoutSelectionPresentsWarningWhenDiagonalChoiceStacksConflict() {
        let scheduler = PenaltyBannerSchedulerSpy()
        let gameCenter = GameCenterServiceSpy()
        let adsService = AdsServiceSpy()

        // 標準モードのレギュレーションを基に、斜め選択カードを含む山札構成へ差し替えて再現性を高める
        var diagonalRegulation = GameMode.standard.regulationSnapshot
        diagonalRegulation.deckPreset = .standardWithDiagonalChoices
        let diagonalMode = GameMode(
            identifier: .freeCustom,
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
        var edgeRegulation = GameMode.standard.regulationSnapshot
        edgeRegulation.spawnRule = .fixed(GridPoint(x: 0, y: 0))
        let edgeMode = GameMode(
            identifier: .freeCustom,
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

        // 左端にいるため、左右選択カードのうち左方向だけが盤外となり、候補数が片側に縮む状況を再現する
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

        let core = GameCore(mode: .standard)
        let interfaces = GameModuleInterfaces { _ in core }

        let viewModel = GameViewModel(
            mode: .standard,
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

    #if canImport(SpriteKit)
    /// SpriteKit シーンのサイズ同期と GameCore の紐付けが正しく行われるかを確認する
    func testSceneSizeSyncOnAppear() {
        let interfaces = GameModuleInterfaces { _ in GameCore(mode: .standard) }
        let viewModel = GameViewModel(
            mode: .standard,
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
