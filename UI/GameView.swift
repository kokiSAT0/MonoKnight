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
    /// 複数候補カードの警告トーストを保持する秒数
    /// - Note: 高速で盤面を連続タップした場合でも読み切れるよう、3 秒を基準としている。
    private let boardTapWarningDisplayDuration: Double = 3.0
    /// 現在のライト/ダーク設定を環境から取得し、SpriteKit 側の色にも反映する
    /// - Note: 監視系ロジックを別ファイルへ分割しているため、`fileprivate` にするとアクセスできずビルドエラーとなる。
    ///         そのためアクセスレベルはデフォルト（internal）のままにして、同一モジュール内の拡張から安全に参照できるようにしている。
    @Environment(\.colorScheme) var colorScheme
    /// シーンフェーズを監視し、アプリが非アクティブになったタイミングでタイマー制御を委譲する
    /// - Note: 監視ロジックは `GameView+Observers` 側で適用するため、同一モジュール内から参照できるようアクセスレベルを維持する
    @Environment(\.scenePhase) var scenePhase
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
    /// ゲーム準備オーバーレイの表示状態を親ビューから受け取り、タイマー制御と同期する
    /// - Note: RootView 側のローディング表示と GameViewModel 内の pause/resume 呼び出しを結び付けるため、
    ///         `@Binding` を用いて双方向に状態を監視できるようにしている。
    @Binding var isPreparationOverlayVisible: Bool
    /// Game Center 認証済みかどうかの状態。ResultView のボタン表示や ViewModel 連携で利用する。
    let isGameCenterAuthenticated: Bool
    /// Game Center への再サインインをルートビューへ依頼するためのクロージャ。
    let onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?
    /// View とロジックの橋渡しを担う ViewModel
    /// - Note: レイアウトや監視系の拡張（別ファイル）からもアクセスするため、`internal` 相当の公開範囲（デフォルト）を維持する。
    ///         `fileprivate` にすると `GameView+Layout` から参照できずビルドエラーになるため注意。
    @StateObject var viewModel: GameViewModel
    /// 警告トーストの自動消滅を制御する Task を保持し、連続表示時の競合を避ける
    @State private var boardTapWarningDismissTask: Task<Void, Never>?
    /// ハプティクスを有効にするかどうかの設定値

    /// - Note: 監視処理を別ファイルの拡張（`GameView+Observers`）へ切り出しているため、`fileprivate` ではアクセスできずビルドエラーとなる。
    ///         internal（デフォルト）へ緩和してモジュール内の拡張から安全に共有する。

    @AppStorage("haptics_enabled") var hapticsEnabled: Bool = true
    /// ガイドモードのオン/オフを永続化し、盤面ハイライト表示を制御する
    /// - Note: こちらも監視処理を別ファイルで扱う必要があるため、`fileprivate` ではなく internal を維持して拡張から参照できるようにする。
    @AppStorage("guide_mode_enabled") var guideModeEnabled: Bool = true
    /// 手札の並び替え方式。設定変更時に GameCore へ伝搬する

    /// - Note: 監視系ロジックを切り出した `GameView+Observers` でも値を参照する必要があるため、
    ///         デフォルトのアクセスレベル（internal）を維持し、モジュール内の別ファイル拡張からも安全に共有できるようにしている。

    @AppStorage(HandOrderingStrategy.storageKey) var handOrderingRawValue: String = HandOrderingStrategy.insertionOrder.rawValue
    /// 手札や NEXT の位置をマッチングさせるための名前空間
    /// - Note: レイアウト拡張（GameView+Layout）でも利用するため、アクセスレベルを internal（デフォルト）で共有する。
    @Namespace var cardAnimationNamespace
    /// SpriteKit シーンへのショートカット
    /// - Note: レイアウト用拡張（`GameView+Layout`）で SpriteView を構築する際にも同じシーンへアクセスする必要があるため、
    ///         `viewModel.boardBridge` を経由したプロパティとして切り出し、`@StateObject` が再利用された場合も一貫したシーンを参照できるようにする。
    var scene: GameScene { viewModel.boardBridge.scene }

    /// GameBoardBridgeViewModel へのショートカット
    /// - Note: プロパティとしてまとめることで、別ファイルの拡張からも一貫した参照経路を利用できるようにする。
    var boardBridge: GameBoardBridgeViewModel { viewModel.boardBridge }

    /// デフォルトのサービスを利用して `GameView` を生成するコンビニエンスイニシャライザ
    /// - Parameters:
    ///   - mode: 表示したいゲームモード
    ///   - gameInterfaces: GameCore 生成を担当するファクトリセット（省略時は `.live`）
    ///   - isPreparationOverlayVisible: RootView が保持するローディング表示のバインディング
    ///   - onRequestReturnToTitle: タイトル画面への遷移要求クロージャ（省略可）
    ///   - onRequestStartCampaignStage: キャンペーンの別ステージを開始するリクエストクロージャ
    init(
        mode: GameMode = .standard,
        gameInterfaces: GameModuleInterfaces = .live,
        isGameCenterAuthenticated: Bool? = nil,
        isPreparationOverlayVisible: Binding<Bool> = .constant(false),
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)? = nil,
        onRequestReturnToTitle: (() -> Void)? = nil,
        onRequestStartCampaignStage: ((CampaignStage) -> Void)? = nil
    ) {
        // 既定値はメインアクター上で解決し、@MainActor 隔離済みのシングルトンを安全に参照する
        let resolvedIsAuthenticated = isGameCenterAuthenticated ?? GameCenterService.shared.isAuthenticated
        self.init(
            mode: mode,
            gameInterfaces: gameInterfaces,
            gameCenterService: GameCenterService.shared,
            adsService: AdsService.shared,
            campaignProgressStore: CampaignProgressStore(),
            isPreparationOverlayVisible: isPreparationOverlayVisible,
            isGameCenterAuthenticated: resolvedIsAuthenticated,
            onRequestGameCenterSignIn: onRequestGameCenterSignIn,
            onRequestReturnToTitle: onRequestReturnToTitle,
            onRequestStartCampaignStage: onRequestStartCampaignStage
        )
    }

    /// 初期化で ViewModel を組み立て、GameCore と GameScene を橋渡しする
    /// - Parameters:
    ///   - mode: 利用するゲームモード
    ///   - gameInterfaces: GameCore 生成用の依存セット
    ///   - gameCenterService: Game Center 連携サービス
    ///   - adsService: 広告制御サービス
    ///   - campaignProgressStore: キャンペーン進捗ストア
    ///   - isPreparationOverlayVisible: ローディング表示状態を伝えるバインディング
    ///   - isGameCenterAuthenticated: Game Center 認証状態
    ///   - onRequestGameCenterSignIn: サインイン依頼クロージャ
    ///   - onRequestReturnToTitle: タイトル復帰依頼クロージャ
    ///   - onRequestStartCampaignStage: キャンペーン継続依頼クロージャ
    init(
        mode: GameMode,
        gameInterfaces: GameModuleInterfaces,
        gameCenterService: GameCenterServiceProtocol,
        adsService: AdsServiceProtocol,
        campaignProgressStore: CampaignProgressStore,
        isPreparationOverlayVisible: Binding<Bool>,
        isGameCenterAuthenticated: Bool?,
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)? = nil,
        onRequestReturnToTitle: (() -> Void)? = nil,
        onRequestStartCampaignStage: ((CampaignStage) -> Void)? = nil
    ) {
        // Game Center 認証状態をローカル変数へ束ね、後続の代入と ViewModel 初期化で同じ値を共有する
        let resolvedIsAuthenticated = isGameCenterAuthenticated ?? gameCenterService.isAuthenticated
        // MARK: - GameViewModel の生成を 1 度きりに抑制
        // 以前はローカル定数で GameViewModel を生成してから @StateObject へ渡していたため、
        // SwiftUI の再初期化に伴い不要なインスタンスが都度作られ、GameCore の `configureForNewSession` が複数回走っていた。
        // ここでは `StateObject` の初期化クロージャへ直接渡し、必要なタイミングでのみインスタンス化されるようにする。
        // MARK: - ユーザー設定を読み出して ViewModel 初期化へ渡す
        // `StateObject` へ直接クロージャを渡し、SwiftUI 側で既存インスタンスが再利用される場合はイニシャライザ評価をスキップさせる。
        let savedOrdering = UserDefaults.standard.string(forKey: HandOrderingStrategy.storageKey)
        _isPreparationOverlayVisible = isPreparationOverlayVisible
        self.isGameCenterAuthenticated = resolvedIsAuthenticated
        self.onRequestGameCenterSignIn = onRequestGameCenterSignIn
        _viewModel = StateObject(
            wrappedValue: GameViewModel(
                mode: mode,
                gameInterfaces: gameInterfaces,
                gameCenterService: gameCenterService,
                adsService: adsService,
                campaignProgressStore: campaignProgressStore,
                onRequestGameCenterSignIn: onRequestGameCenterSignIn,
                onRequestReturnToTitle: onRequestReturnToTitle,
                onRequestStartCampaignStage: onRequestStartCampaignStage,
                initialHandOrderingRawValue: savedOrdering,
                initialGameCenterAuthenticationState: resolvedIsAuthenticated
            )
        )
    }

    var body: some View {
        applyGameViewObservers(to:
            GeometryReader { geometry in
                // 専用メソッドへ委譲し、レイアウト計算と描画処理の責務を明示的に分離する
                mainContent(for: geometry)
            }
        )
        .onAppear {
            // 表示時点の認証状態を ViewModel へ反映し、スコア送信フローとの整合性を保つ。
            viewModel.updateGameCenterAuthenticationStatus(isGameCenterAuthenticated)
            // 画面復帰時に警告が残っている場合でもトーストが自動的に閉じるよう監視を再開する
            scheduleBoardTapWarningAutoDismiss(for: viewModel.boardTapSelectionWarning)
        }
        .onChange(of: isGameCenterAuthenticated) { _, newValue in
            // RootView から認証状態が更新された場合に備えて随時同期する。
            viewModel.updateGameCenterAuthenticationStatus(newValue)
        }
        // 警告ステートの変化をフックし、トーストの自動消滅タスクを更新する
        .onChange(of: viewModel.boardTapSelectionWarning) { _, newValue in
            // 新しい警告が届いたらタイマーを再スケジュールし、nil になったときは確実にキャンセルする
            scheduleBoardTapWarningAutoDismiss(for: newValue)
        }
        // 画面を離れる際にタイマーを破棄し、不要なタスクがバックグラウンドで動き続けないようにする
        .onDisappear {
            boardTapWarningDismissTask?.cancel()
            boardTapWarningDismissTask = nil
        }
        // ポーズメニューをフルスクリーンで重ね、端末サイズに左右されずに全項目を視認できるようにする
        .fullScreenCover(isPresented: $viewModel.isPauseMenuPresented) {
            PauseMenuView(
                campaignSummary: viewModel.campaignPauseSummary,
                penaltyItems: viewModel.pauseMenuPenaltyItems,
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
        // リザルトはゲーム体験の区切りとなるため、全画面カバーで没入感を維持する
        .fullScreenCover(isPresented: $viewModel.showingResult) {
            ResultView(
                moveCount: viewModel.moveCount,
                penaltyCount: viewModel.penaltyCount,
                elapsedSeconds: viewModel.elapsedSeconds,
                modeIdentifier: viewModel.mode.identifier,
                modeDisplayName: viewModel.mode.displayName,
                showsLeaderboardButton: viewModel.isLeaderboardEligible,
                isGameCenterAuthenticated: viewModel.isGameCenterAuthenticated,
                onRequestGameCenterSignIn: onRequestGameCenterSignIn,
                campaignClearRecord: viewModel.latestCampaignClearRecord,
                newlyUnlockedStages: viewModel.newlyUnlockedStages,
                onSelectCampaignStage: { stage in
                    // ViewModel に処理を委譲してリザルト閉鎖と広告フラグの初期化を一元管理する
                    viewModel.handleCampaignStageAdvance(to: stage)
                },
                onRetry: {
                    // ViewModel 側でリセットと広告フラグの再設定をまとめて処理する
                    viewModel.handleResultRetry()
                },
                onReturnToTitle: {
                    // ホーム復帰時の初期化と遷移要求を ViewModel 側で統一的に処理する
                    viewModel.handleResultReturnToTitle()
                },
                gameCenterService: viewModel.gameCenterService,
                adsService: viewModel.adsService
            )
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

    /// 警告トーストの自動クローズをスケジュールし、一定時間後に状態をリセットする
    /// - Parameter warning: 最新の警告ペイロード。nil の場合はタイマーを破棄する
    private func scheduleBoardTapWarningAutoDismiss(for warning: GameViewModel.BoardTapSelectionWarning?) {
        // 既存のタイマーが走っていればキャンセルし、連続発火時に古いタスクが残らないようにする
        boardTapWarningDismissTask?.cancel()
        boardTapWarningDismissTask = nil

        guard warning != nil else { return }

        boardTapWarningDismissTask = Task { @MainActor in
            // Task 終了時に参照を解放し、次回以降のスケジュールが正しく登録できるようにする
            defer { boardTapWarningDismissTask = nil }

            let nanoseconds = UInt64(boardTapWarningDisplayDuration * 1_000_000_000)
            do {
                // 指定時間だけ待機し、ユーザーがトーストを視認できる猶予を確保する
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                // キャンセルされた場合はそのまま抜け、不要な再描画を避ける
                return
            }

            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.28)) {
                viewModel.clearBoardTapSelectionWarning()
            }
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
