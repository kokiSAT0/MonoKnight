import XCTest
@testable import MonoKnightApp
import Game
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

    /// BoardTapPlayRequest に含まれる ResolvedCardMove がそのまま適用され、指定マスへ移動することを確認する
    func testBoardTapPlayRequestUsesResolvedDestination() {
        let scheduler = PenaltyBannerSchedulerSpy()
        let gameCenter = GameCenterServiceSpy()
        let adsService = AdsServiceSpy()
        let deck = Deck.makeTestDeck(cards: [
            .kingUp,
            .kingRight,
            .kingDown,
            .kingLeft,
            .kingUpLeft,
            .straightUp2,
            .straightRight2,
            .straightDown2
        ])
        let interfaces = GameModuleInterfaces { _ in GameCore.makeTestInstance(deck: deck) }

        let viewModel = GameViewModel(
            mode: .standard,
            gameInterfaces: interfaces,
            gameCenterService: gameCenter,
            adsService: adsService,
            onRequestReturnToTitle: nil,
            penaltyBannerScheduler: scheduler
        )

        guard let current = viewModel.core.current else {
            XCTFail("現在位置が未設定のままです")
            return
        }

        // 手札先頭のスタックとカードを取得し、任意の移動ベクトルを指定する
        guard let stack = viewModel.core.handStacks.first,
              let topCard = stack.topCard else {
            XCTFail("トップカードを取得できませんでした")
            return
        }

        let targetPoint = current.offset(dx: 1, dy: 0)
        XCTAssertTrue(viewModel.core.board.contains(targetPoint), "ターゲット座標が盤面外です")

        let resolvedMove = ResolvedCardMove(
            stackID: stack.id,
            stackIndex: 0,
            card: topCard,
            moveVector: MoveVector(dx: 1, dy: 0),
            destination: targetPoint
        )

        let request = BoardTapPlayRequest(resolvedMove: resolvedMove)

        viewModel.handleBoardTapPlayRequest(request)

        // 非同期アニメーション完了を待つ
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        XCTAssertEqual(viewModel.core.current, targetPoint, "ResolvedCardMove の destination が反映されていません")
        XCTAssertEqual(viewModel.core.moveCount, 1, "カードプレイ後の手数が想定より少ないです")
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
    func requestTrackingAuthorization() async {}
    func requestConsentIfNeeded() async {}
    func refreshConsentStatus() async {}
}
