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
            .onChange(of: colorScheme, initial: false) { previousScheme, newScheme in
                // 直前のカラースキームと異なる場合のみ SpriteKit 側の配色を更新して無駄な再描画を防ぐ
                guard previousScheme != newScheme else { return }
                viewModel.applyScenePalette(for: newScheme)
                // カラースキーム変更時はガイドの色味も再描画して視認性を確保
                viewModel.refreshGuideHighlights()
            }
            // 手札の並び設定が変わったら即座にゲームロジックへ伝え、UI の並びも更新する
            .onChange(of: handOrderingRawValue, initial: false) { _, newValue in
                // AppStorage から受け取った新しい手札並び設定を即座に適用し、設定画面とゲーム画面の差異をなくす
                viewModel.applyHandOrderingStrategy(rawValue: newValue)
            }
            // ガイドモードのオン/オフを切り替えたら即座に ViewModel 側へ委譲する
            .onChange(of: guideModeEnabled, initial: false) { _, isEnabled in
                // 新しいガイドモード状態を SpriteKit へ伝え、盤面表示の助情報を同期する
                viewModel.updateGuideMode(enabled: isEnabled)
            }
            // ハプティクス設定が切り替わった際も ViewModel へ伝え、サービス呼び出しを統一する
            .onChange(of: hapticsEnabled, initial: false) { _, isEnabled in
                // 旧設定との差分を検知したタイミングでハプティクス制御ロジックを更新し、無効化時の誤振動を防ぐ
                viewModel.updateHapticsSetting(isEnabled: isEnabled)
            }
            // scenePhase の変化を監視し、キャンペーン時のみタイマーの一時停止/再開を委譲する
            .onChange(of: scenePhase, initial: false) { _, newPhase in
                // 旧値は利用しないため破棄しつつ、新しいライフサイクル状態に応じた挙動だけに集中させる
                viewModel.handleScenePhaseChange(newPhase)
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
