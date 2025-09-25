import Combine  // 経過時間更新で Combine のタイマーパブリッシャを活用するため読み込む
import Game  // GameCore や DealtCard、手札並び設定を利用するためゲームロジックモジュールを読み込む
import SharedSupport // debugLog / debugError を利用するため共有ターゲットを追加
import SpriteKit
import SwiftUI
import UIKit  // ハプティクス用のフレームワークを追加

/// SwiftUI から SpriteKit の盤面を表示するビュー
/// 画面下部に手札スロット（最大種類数を保持できるスタック枠）と次に引かれるカードを表示し、
/// タップで GameCore を更新する
/// SwiftUI ビューは UI 操作のため常にメインアクター上で処理する必要があるため、
/// `@MainActor` を付与してサービスのシングルトンへ安全にアクセスできるようにする
@MainActor
struct GameView: View {
    /// カラーテーマを生成し、ビュー全体で共通の配色を利用できるようにする
    /// - Note: レイアウト補助の拡張（`GameView+Layout`）でもテーマカラーを共有する必要があるため、
    ///         同一型の別ファイル拡張からも参照できるようアクセスレベルはデフォルト（internal）にしている。
    let theme = AppTheme()
    /// 現在のライト/ダーク設定を環境から取得し、SpriteKit 側の色にも反映する
    /// - Note: 監視系ロジックを別ファイルへ分割しているため、`fileprivate` にするとアクセスできずビルドエラーとなる。
    ///         そのためアクセスレベルはデフォルト（internal）のままにして、同一モジュール内の拡張から安全に参照できるようにしている。
    @Environment(\.colorScheme) var colorScheme
    /// デバイスの横幅サイズクラスを取得し、iPad などレギュラー幅でのモーダル挙動を調整する
    /// - Note: レイアウト計算用の拡張（`GameView+Layout`）でも参照するため、アクセスレベルは internal に緩和している
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    /// RootView 側で挿入したトップバーの高さ。safeAreaInsets.top から減算して余分な余白を除去する
    /// - Important: レイアウト計算を担う `GameView+Layout` からも参照するためアクセスレベルを internal にし、
    ///             View 拡張側でも同一値を共有できるようにする。
    /// - Note: Swift 6 では独自 EnvironmentKey の値型が明示されていないと推論に失敗するため、CGFloat 型で注釈を付けている
    @Environment(\.topOverlayHeight) var topOverlayHeight: CGFloat
    /// ルートビューの GeometryReader で得たシステム由来セーフエリアの上端量
    /// - Note: safeAreaInset により増加した分を差し引くための基準値として利用する
    /// - Note: レイアウト補助用の拡張（`GameView+Layout`）でも参照するため、アクセスレベルは internal にとどめている
    @Environment(\.baseTopSafeAreaInset) var baseTopSafeAreaInset: CGFloat
    /// 手札スロットの数（常に 5 スロット分の枠を確保してレイアウトを安定させる）
    /// - Note: レイアウト拡張でハンド UI の構築にも利用するため、アクセスレベルは internal にとどめて同一型内で共有している。
    let handSlotCount = 5
    /// View とロジックの橋渡しを担う ViewModel
    /// - Note: レイアウトや監視系の拡張（別ファイル）からもアクセスするため、`internal` 相当の公開範囲（デフォルト）を維持する。
    ///         `fileprivate` にすると `GameView+Layout` から参照できずビルドエラーになるため注意。
    @StateObject var viewModel: GameViewModel
    /// SpriteKit との仲介を担う BoardBridge
    /// - Note: こちらもレイアウト拡張からの参照が必要なため、`internal`（デフォルト）のアクセスレベルを確保している。
    @ObservedObject var boardBridge: GameBoardBridgeViewModel
    /// ハプティクスを有効にするかどうかの設定値
    /// - Note: 設定変更を監視する処理を `GameView+Observers` 側へ移譲しているため、拡張からも参照できるよう `fileprivate` へ拡張する。
    @AppStorage("haptics_enabled") fileprivate var hapticsEnabled: Bool = true
    /// ガイドモードのオン/オフを永続化し、盤面ハイライト表示を制御する
    /// - Note: 同様に監視処理が別ファイルの拡張へ分離されているため、アクセスレベルを `fileprivate` に調整している。
    @AppStorage("guide_mode_enabled") fileprivate var guideModeEnabled: Bool = true
    /// 手札の並び替え方式。設定変更時に GameCore へ伝搬する

    /// - Note: 監視系ロジックを切り出した `GameView+Observers` でも値を参照する必要があるため、
    ///         デフォルトのアクセスレベル（internal）を維持し、モジュール内の別ファイル拡張からも安全に共有できるようにしている。

    @AppStorage(HandOrderingStrategy.storageKey) var handOrderingRawValue: String = HandOrderingStrategy.insertionOrder.rawValue
    /// 手札や NEXT の位置をマッチングさせるための名前空間
    /// - Note: レイアウト拡張（GameView+Layout）でも利用するため、アクセスレベルを internal（デフォルト）で共有する。
    @Namespace var cardAnimationNamespace
    /// SpriteKit シーンへのショートカット
    private var scene: GameScene { boardBridge.scene }

    /// デフォルトのサービスを利用して `GameView` を生成するコンビニエンスイニシャライザ
    /// - Parameters:
    ///   - mode: 表示したいゲームモード
    ///   - gameInterfaces: GameCore 生成を担当するファクトリセット（省略時は `.live`）
    ///   - onRequestReturnToTitle: タイトル画面への遷移要求クロージャ（省略可）
    init(
        mode: GameMode = .standard,
        gameInterfaces: GameModuleInterfaces = .live,
        onRequestReturnToTitle: (() -> Void)? = nil
    ) {
        self.init(
            mode: mode,
            gameInterfaces: gameInterfaces,
            gameCenterService: GameCenterService.shared,
            adsService: AdsService.shared,
            onRequestReturnToTitle: onRequestReturnToTitle
        )
    }

    /// 初期化で ViewModel を組み立て、GameCore と GameScene を橋渡しする
    init(
        mode: GameMode,
        gameInterfaces: GameModuleInterfaces,
        gameCenterService: GameCenterServiceProtocol,
        adsService: AdsServiceProtocol,
        onRequestReturnToTitle: (() -> Void)? = nil
    ) {
        let viewModel = GameViewModel(
            mode: mode,
            gameInterfaces: gameInterfaces,
            gameCenterService: gameCenterService,
            adsService: adsService,
            onRequestReturnToTitle: onRequestReturnToTitle
        )

        if let savedValue = UserDefaults.standard.string(forKey: HandOrderingStrategy.storageKey) {
            viewModel.restoreHandOrderingStrategy(from: savedValue)
        }

        _viewModel = StateObject(wrappedValue: viewModel)
        _boardBridge = ObservedObject(wrappedValue: viewModel.boardBridge)
    }

    var body: some View {
        applyGameViewObservers(to:
            GeometryReader { geometry in
                // 専用メソッドへ委譲し、レイアウト計算と描画処理の責務を明示的に分離する
                mainContent(for: geometry)
            }
        )
        // ポーズメニューをフルスクリーンで重ね、端末サイズに左右されずに全項目を視認できるようにする
        .fullScreenCover(isPresented: $viewModel.isPauseMenuPresented) {
            PauseMenuView(
                onResume: {
                    // フルスクリーンカバーを閉じてプレイへ戻る
                    viewModel.isPauseMenuPresented = false
                },
                onConfirmReset: {
                    // リセット確定後はフルスクリーンカバーを閉じてから共通処理を呼び出す
                    viewModel.isPauseMenuPresented = false
                    performMenuAction(.reset)
                },
                onConfirmReturnToTitle: {
                    // タイトル復帰時もポーズメニューを閉じてから処理を実行する
                    viewModel.isPauseMenuPresented = false
                    performMenuAction(.returnToTitle)
                }
            )
        }
        // シートで結果画面を表示
        .sheet(isPresented: $viewModel.showingResult) {
            ResultView(
                moveCount: viewModel.moveCount,
                penaltyCount: viewModel.penaltyCount,
                elapsedSeconds: viewModel.elapsedSeconds,
                modeIdentifier: viewModel.mode.identifier,
                onRetry: {
                    // ViewModel 側でリセットと広告フラグの再設定をまとめて処理する
                    viewModel.handleResultRetry()
                },
                gameCenterService: viewModel.gameCenterService,
                adsService: viewModel.adsService
            )
            // MARK: - iPad 向けのモーダル最適化
            // レギュラー幅（iPad など）では初期状態から `.large` を採用し、全要素が確実に表示されるようにする。
            // Compact 幅（iPhone）では従来通り medium/large を切り替えられるよう配慮し、片手操作でも扱いやすく保つ。
            .presentationDetents(
                horizontalSizeClass == .regular ? [.large] : [.medium, .large]
            )
            .presentationDragIndicator(.visible)
        }
        // MARK: - レギュラー幅では確認をシートで提示
        // iPad では confirmationDialog だと文字が途切れやすいため、十分な横幅を確保できるシートで詳細文を表示する
        .sheet(item: regularWidthPendingActionBinding) { action in
            GameMenuActionConfirmationSheet(
                action: action,
                onConfirm: { confirmedAction in
                    // performMenuAction 内で viewModel.pendingMenuAction を破棄しているが、
                    // 明示的に nil を代入しておくことでバインディング由来のシート閉鎖と状態初期化を二重に保証する
                    performMenuAction(confirmedAction)
                    viewModel.pendingMenuAction = nil
                },
                onCancel: {
                    // キャンセル時はダイアログと同じ挙動になるように viewModel.pendingMenuAction を破棄する
                    viewModel.pendingMenuAction = nil
                }
            )
            // iPad では高さに余裕があるため medium/large の選択肢を用意し、読みやすさを優先する
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // メニュー選択後に確認ダイアログを表示し、誤操作を防ぐ
        .confirmationDialog(
            "操作の確認",
            isPresented: Binding(
                get: {
                    // レギュラー幅ではシート側で確認を行うため、コンパクト幅のときだけダイアログを表示する
                    horizontalSizeClass != .regular && viewModel.pendingMenuAction != nil
                },
                set: { isPresented in
                    // キャンセル操作で閉じられた場合もステートを初期化する
                    if !isPresented {
                        viewModel.pendingMenuAction = nil
                    }
                }
            ),
            presenting: viewModel.pendingMenuAction
        ) { action in
            Button(action.confirmationButtonTitle, role: action.buttonRole) {
                // ユーザーの確認後に実際の処理を実行
                performMenuAction(action)
            }
        } message: { action in
            Text(action.confirmationMessage)
        }
    }

    /// メニュー操作を実際に実行する共通処理
    /// - Parameter action: ユーザーが選択した操作種別
    private func performMenuAction(_ action: GameMenuAction) {
        viewModel.performMenuAction(action)
    }
}

// MARK: - プレビュー
#Preview {
    // Xcode の Canvas で GameView を表示するためのプレビュー
    GameView()
}
