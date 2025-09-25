import Combine  // PreferenceKey と Combine パブリッシャの購読処理をまとめるために読み込む
import Game  // GameMenuAction や HandOrderingStrategy を参照するために読み込む
import SharedSupport  // debugLog を利用して高さ変更ログを出力するために読み込む
import SwiftUI

// MARK: - View の監視モディファイアを集約
@MainActor
extension GameView {
    /// PreferenceKey や Combine パブリッシャによる状態監視モディファイアをひとまとめに適用する
    /// - Parameter content: 監視対象となるベースビュー
    /// - Returns: 各種監視モディファイアを適用済みのビュー
    func applyGameViewObservers<Content: View>(to content: Content) -> some View {
        content
        // PreferenceKey で伝搬した各セクションの高さを受け取り、レイアウト計算に利用する
            .onPreferenceChange(StatisticsHeightPreferenceKey.self) { newHeight in
                // 統計バッジ領域の計測値が変わったタイミングで旧値と比較し、変化量をログへ残して原因調査を容易にする
                let previousHeight = viewModel.statisticsHeight
                guard previousHeight != newHeight else { return }
                debugLog("GameView.viewModel.statisticsHeight 更新: 旧値=\(previousHeight), 新値=\(newHeight)")
                viewModel.statisticsHeight = newHeight
            }
            .onPreferenceChange(HandSectionHeightPreferenceKey.self) { newHeight in
                // 手札セクションの高さ変化も逐次観測し、ホームインジケータ付近での余白不足を切り分けられるようにする
                let previousHeight = viewModel.handSectionHeight
                guard previousHeight != newHeight else { return }
                debugLog("GameView.viewModel.handSectionHeight 更新: 旧値=\(previousHeight), 新値=\(newHeight)")
                viewModel.handSectionHeight = newHeight
            }
            // 盤面 SpriteView のアンカー更新を監視し、アニメーションの移動先として保持
            .onPreferenceChange(BoardAnchorPreferenceKey.self) { anchor in
                viewModel.updateBoardAnchor(anchor)
            }
            // 初回表示時に SpriteKit の背景色もテーマに合わせて更新
            .onAppear {
                viewModel.prepareForAppear(
                    colorScheme: colorScheme,
                    guideModeEnabled: guideModeEnabled,
                    hapticsEnabled: hapticsEnabled,
                    handOrderingStrategy: resolveHandOrderingStrategy()
                )
            }
            // ライト/ダーク切り替えが発生した場合も SpriteKit 側へ反映
            .onChange(of: colorScheme) { newScheme in
                viewModel.applyScenePalette(for: newScheme)
                // カラースキーム変更時はガイドの色味も再描画して視認性を確保
                viewModel.refreshGuideHighlights()
            }
            // 手札の並び設定が変わったら即座にゲームロジックへ伝え、UI の並びも更新する
            .onChange(of: handOrderingRawValue) { _ in
                viewModel.applyHandOrderingStrategy(rawValue: handOrderingRawValue)
            }
            // ガイドモードのオン/オフを切り替えたら即座に ViewModel 側へ委譲する
            .onChange(of: guideModeEnabled) { isEnabled in
                viewModel.updateGuideMode(enabled: isEnabled)
            }
            // ハプティクス設定が切り替わった際も ViewModel へ伝え、サービス呼び出しを統一する
            .onChange(of: hapticsEnabled) { isEnabled in
                viewModel.updateHapticsSetting(isEnabled: isEnabled)
            }
            // 経過時間を 1 秒ごとに再計算し、リアルタイム表示へ反映
            .onReceive(viewModel.elapsedTimer) { _ in
                viewModel.updateDisplayedElapsedTime()
            }
            // カードが盤面へ移動中は UI 全体を操作不可とし、状態の齟齬を防ぐ
            .disabled(boardBridge.animatingCard != nil)
            // Preference から取得したアンカー情報を用いて、カードが盤面中央へ吸い込まれる演出を重ねる
            .overlayPreferenceValue(CardPositionPreferenceKey.self) { anchors in
                GameCardAnimationOverlay(
                    anchors: anchors,
                    boardBridge: boardBridge,
                    fallbackCurrentPosition: viewModel.currentPosition,
                    cardAnimationNamespace: cardAnimationNamespace
                )
            }
    }

    /// レギュラー幅（iPad）向けにシート表示へ切り替えるためのバインディング
    /// - Returns: iPad では viewModel.pendingMenuAction を返し、それ以外では常に nil を返すバインディング
    var regularWidthPendingActionBinding: Binding<GameMenuAction?> {
        Binding(
            get: {
                // 横幅が十分でない場合はシート表示を抑制し、確認ダイアログ側に処理を委ねる
                guard horizontalSizeClass == .regular else {
                    return nil
                }
                return viewModel.pendingMenuAction
            },
            set: { newValue in
                // シートを閉じたときに SwiftUI から nil が渡されるため、そのまま状態へ反映しておく
                viewModel.pendingMenuAction = newValue
            }
        )
    }

    /// AppStorage から読み出した文字列を安全に列挙体へ変換する
    /// - Returns: 有効な設定値。未知の値は従来方式へフォールバックする
    func resolveHandOrderingStrategy() -> HandOrderingStrategy {
        HandOrderingStrategy(rawValue: handOrderingRawValue) ?? .insertionOrder
    }
}
