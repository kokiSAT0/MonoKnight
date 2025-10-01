#if canImport(UIKit)
import XCTest
import SwiftUI
import Game
@testable import MonoKnightApp

/// MoveCardIllustrationView のアクセシビリティ挙動を検証するテスト
/// - Note: VoiceOver の読み上げ内容が複数候補カードでも自然な文面になるか確認する
@MainActor
final class MoveCardIllustrationViewAccessibilityTests: XCTestCase {

    /// 複数候補カードでは盤面で方向を選ぶ旨が案内されることを確認する
    func testHandModeAccessibilityHintMentionsDirectionChoiceWhenMultipleCandidatesExist() {
        let overrideVectors = [
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0),
            MoveVector(dx: 0, dy: 1)
        ]
        MoveCard.setTestMovementVectors(overrideVectors, for: .kingRight)
        defer { MoveCard.setTestMovementVectors(nil, for: .kingRight) }

        let view = MoveCardIllustrationView(card: .kingRight, mode: .hand)
        let controller = UIHostingController(rootView: view)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 120, height: 180)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let hint = controller.view.accessibilityHint ?? ""
        XCTAssertTrue(hint.contains("盤面で移動方向を決めてください"), "複数候補時に方向選択を促す文言が含まれていません")
        XCTAssertTrue(hint.contains("候補は 3 方向"), "候補数の案内が含まれていません: \(hint)")
    }

    /// 複数候補カードではラベル末尾に補足が追加されることを確認する
    func testHandModeAccessibilityLabelAddsMultipleDirectionSuffix() {
        let overrideVectors = [
            MoveVector(dx: 2, dy: 0),
            MoveVector(dx: -2, dy: 0)
        ]
        MoveCard.setTestMovementVectors(overrideVectors, for: .straightRight2)
        defer { MoveCard.setTestMovementVectors(nil, for: .straightRight2) }

        let view = MoveCardIllustrationView(card: .straightRight2, mode: .hand)
        let controller = UIHostingController(rootView: view)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 120, height: 180)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let label = controller.view.accessibilityLabel ?? ""
        XCTAssertTrue(label.contains("複数方向の候補あり"), "複数候補を示す補足がラベルに含まれていません: \(label)")
    }
}
#endif
