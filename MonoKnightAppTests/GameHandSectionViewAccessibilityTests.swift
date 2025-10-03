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
            onRequestReturnToTitle: nil
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

        // SwiftUI ビューをホストしてアクセシビリティ文言を取得する
        let host = GameHandSectionHost(viewModel: viewModel, boardBridge: viewModel.boardBridge)
        let controller = UIHostingController(rootView: host)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 360, height: 260)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        guard let slotView = controller.view.findSubview(withAccessibilityIdentifier: "hand_slot_0") else {
            XCTFail("手札ビューを取得できませんでした")
            return
        }

        let hint = slotView.accessibilityHint ?? ""
        XCTAssertTrue(hint.contains("盤面で移動方向を決めてください"), "複数候補時の方向選択案内が欠落しています: \(hint)")
        XCTAssertTrue(hint.contains("候補は 2 方向"), "候補数の読み上げが欠落しています: \(hint)")
    }
}

// MARK: - テスト用ホストビュー
private struct GameHandSectionHost: View {
    @ObservedObject var viewModel: GameViewModel
    @ObservedObject var boardBridge: GameBoardBridgeViewModel
    let theme = AppTheme()
    @Namespace private var namespace

    var body: some View {
        GameHandSectionView(
            theme: theme,
            viewModel: viewModel,
            boardBridge: boardBridge,
            cardAnimationNamespace: namespace,
            handSlotCount: 5,
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

private extension UIView {
    /// 指定したアクセシビリティ識別子を持つサブビューを深さ優先で探索する
    func findSubview(withAccessibilityIdentifier identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier { return self }
        for subview in subviews {
            if let match = subview.findSubview(withAccessibilityIdentifier: identifier) {
                return match
            }
        }
        return nil
    }
}
#endif
