import SpriteKit
import SwiftUI
import UIKit  // ハプティクス用のフレームワークを追加

/// SwiftUI から SpriteKit の盤面を表示するビュー
/// 画面下部に手札 3 枚と次に引かれるカードを表示し、
/// タップで GameCore を更新する
struct GameView: View {
    /// 手札スロットの数（常に 5 枚分の枠を確保してレイアウトを安定させる）
    private let handSlotCount = 5
    /// ゲームロジックを保持する ObservableObject
    /// - NOTE: `StateObject` は init 内で明示的に生成し、GameScene に渡す
    @StateObject private var core: GameCore
    /// 結果画面を表示するかどうかのフラグ
    /// - NOTE: クリア時に true となり ResultView をシート表示する
    @State private var showingResult = false
    /// ゲーム状態をリセットする際に確認ダイアログを表示するフラグ
    @State private var showingResetConfirmation = false
    /// タイトルへ戻る際の確認ダイアログ表示フラグ
    @State private var showingReturnConfirmation = false
    /// SpriteKit のシーン。初期化時に一度だけ生成して再利用する
    private let scene: GameScene
    /// Game Center 連携を扱うサービス（プロトコル型で受け取る）
    private let gameCenterService: GameCenterServiceProtocol
    /// 広告表示を扱うサービス（プロトコル型で受け取る）
    private let adsService: AdsServiceProtocol
    /// ハプティクスを有効にするかどうかの設定値
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true
    /// 親ビューから閉じるためのクロージャを受け取る（タイトルへ戻る導線用）
    @Environment(\.dismissGameView) private var dismissGameView
    /// `presentationMode` を併用し、モーダル表示中は標準の dismiss も利用できるようにする
    @Environment(\.presentationMode) private var presentationMode

    /// 初期化で GameCore と GameScene を連結する
    /// 依存するサービスを外部から注入できるようにする初期化処理
    /// - Parameters:
    ///   - gameCenterService: Game Center 連携用サービス（デフォルトはシングルトン）
    ///   - adsService: 広告表示用サービス（デフォルトはシングルトン）
    init(
        gameCenterService: GameCenterServiceProtocol = GameCenterService.shared,
        adsService: AdsServiceProtocol = AdsService.shared
    ) {
        // GameCore の生成。StateObject へ包んで保持する
        let core = GameCore()
        _core = StateObject(wrappedValue: core)

        // GameScene はインスタンス生成後にサイズとスケールを指定
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        // GameScene から GameCore へタップイベントを伝えるため参照を渡す
        scene.gameCore = core
        self.scene = scene
        // サービスを保持
        self.gameCenterService = gameCenterService
        self.adsService = adsService
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 16) {
                    // MARK: SpriteKit 表示領域
                    SpriteView(scene: scene)
                        // 正方形で表示したいため幅に合わせる
                        .frame(width: geometry.size.width, height: geometry.size.width)
                        .onAppear {
                            // サイズと初期状態を反映
                            scene.size = CGSize(
                                width: geometry.size.width, height: geometry.size.width)
                            scene.updateBoard(core.board)
                            scene.moveKnight(to: core.current)
                        }
                        .onReceive(core.$board) { newBoard in scene.updateBoard(newBoard) }
                        .onReceive(core.$current) { newPoint in scene.moveKnight(to: newPoint) }

                    // MARK: 手札と先読みカードの表示
                    VStack(spacing: 8) {
                        // 手札 3 枚を横並びで表示
                        HStack(spacing: 12) {
                            // 固定長スロットで回し、欠番があっても UI が崩れないようにする
                            ForEach(0..<handSlotCount, id: \.self) { index in
                                handSlotView(for: index)
                            }
                        }

                        // 先読みカードが存在する場合に表示
                        if let next = core.next {
                            VStack(alignment: .leading, spacing: 6) {
                                // MARK: - 先読みカードのラベル
                                // テキストでセクションを明示して VoiceOver からも認識しやすくする
                                Text("次のカード")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .accessibilityHidden(true)  // ラベル自体は MoveCardIllustrationView のラベルに統合する

                                // MARK: - 先読みカード本体
                                // MoveCardIllustrationView の next モードで専用スタイルを適用しつつ、操作不可のバッジを重ねる
                                ZStack {
                                    MoveCardIllustrationView(card: next, mode: .next)
                                    NextCardOverlayView()
                                }
                                .allowsHitTesting(false)  // 先読みはタップ不可であることを UI 上でも保証
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
                // MARK: - 画面右上に操作メニューを配置
                // リセットやタイトルへ戻るといった管理系アクションをまとめる
                actionMenu
                #if DEBUG
                    // MARK: - 結果画面へ強制遷移ボタン（デバッグ専用）
                    // デバッグビルドでのみ表示し、リリースビルドでは含めない
                    Button(action: {
                        // 直接結果画面を開き、UI の確認やデバッグを容易にする
                        showingResult = true
                    }) {
                        Text("結果へ")
                    }
                    .padding()
                    .buttonStyle(.bordered)
                    // UI テストでボタンを特定できるよう識別子を設定
                    .accessibilityIdentifier("show_result")
                #endif
            }
            // 画面全体を黒背景に統一
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        // progress が .cleared へ変化したタイミングで結果画面を表示
        .onChange(of: core.progress) { _, newValue in
            guard newValue == .cleared else { return }
            gameCenterService.submitScore(core.score)
            showingResult = true
        }

        // MARK: - リセット確認ダイアログ
        // 誤操作を防ぐためメニュー選択直後に確認を挟む
        .confirmationDialog(
            "ゲームをリセットしますか？",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("リセット", role: .destructive) {
                performReset()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("現在の進行状況は破棄され、初期状態からやり直します。")
        }

        // MARK: - タイトルへ戻る確認ダイアログ
        // 親ビューが閉じるクロージャを提供している場合のみ選択肢を表示
        .confirmationDialog(
            "タイトルへ戻りますか？",
            isPresented: $showingReturnConfirmation,
            titleVisibility: .visible
        ) {
            Button("タイトルへ戻る", role: .destructive) {
                returnToTitle()
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("ゲームを中断し、タイトル画面へ戻ります。")
        }

        // シートで結果画面を表示
        .sheet(isPresented: $showingResult) {
            ResultView(
                moves: core.score,
                onRetry: {
                    // リトライ時はゲームを初期状態に戻して再開する
                    core.reset()
                    // 新しいプレイで広告を再度表示できるようにフラグをリセット
                    adsService.resetPlayFlag()
                    // 結果画面のシートを閉じてゲーム画面へ戻る
                    showingResult = false
                },
                gameCenterService: gameCenterService,
                adsService: adsService
            )
        }
    }

    /// 指定カードが現在位置から盤内に収まるか判定
    /// - Note: MoveCard は列挙型であり、dx/dy プロパティから移動量を取得する
    private func isCardUsable(_ card: MoveCard) -> Bool {
        // 現在位置に MoveCard の移動量を加算して目的地を算出
        let target = core.current.offset(dx: card.dx, dy: card.dy)
        // 目的地が盤面内に含まれているかどうかを判定
        return core.board.contains(target)
    }

    /// 指定したスロットのカード（存在しない場合は nil）を取得するヘルパー
    /// - Parameter index: 手札スロットの添字
    /// - Returns: 対応する MoveCard または nil（スロットが空の場合）
    private func handCard(at index: Int) -> MoveCard? {
        guard core.hand.indices.contains(index) else {
            // スロットにカードが存在しない場合は nil を返してプレースホルダ表示を促す
            return nil
        }
        return core.hand[index]
    }

    /// 手札スロットの描画を担う共通処理
    /// - Parameter index: 対象スロットの添字
    /// - Returns: MoveCardIllustrationView または空枠プレースホルダを含むビュー
    private func handSlotView(for index: Int) -> some View {
        // どのカードが入っているかによってアニメーションのトリガーを切り替える
        let slotStateKey = slotAnimationKey(for: index)

        return ZStack {
            // 指定スロットにカードが入っているか安全に確認
            if let card = handCard(at: index) {
                MoveCardIllustrationView(card: card)
                    // 盤外に出るカードは薄く表示し、タップ操作を抑制
                    .opacity(isCardUsable(card) ? 1.0 : 0.4)
                    .onTapGesture {
                        // 列挙型 MoveCard の使用可否を判定
                        if isCardUsable(card) {
                            // 使用可能 ⇒ ゲーム状態を更新
                            core.playCard(at: index)
                            // 設定で許可されていれば成功ハプティクスを発火
                            if hapticsEnabled {
                                UINotificationFeedbackGenerator()
                                    .notificationOccurred(.success)
                            }
                        } else {
                            // 使用不可の場合、警告ハプティクスのみ発火
                            if hapticsEnabled {
                                UINotificationFeedbackGenerator()
                                    .notificationOccurred(.warning)
                            }
                        }
                    }
            } else {
                placeholderCardView()
            }
        }
        // 実カードとプレースホルダのどちらでも同じスロット識別子で UI テストしやすくする
        .accessibilityIdentifier("hand_slot_\(index)")
        // 実カードが入れ替わった瞬間だけ最小限のアニメーションを適用し、他スロットの位置は維持
        .animation(.easeInOut(duration: 0.18), value: slotStateKey)
    }

    /// リセット処理を共通化し、メニューおよび結果画面から再利用する
    private func performReset() {
        // コアロジックと広告フラグを初期化して新規ゲームを開始
        core.reset()
        adsService.resetPlayFlag()
        // リセット直後に結果画面が表示されないようフラグを明示的に下げる
        showingResult = false
    }

    /// タイトルへ戻る処理をまとめ、親ビューへの通知もここで行う
    private func returnToTitle() {
        // 戻る前にゲーム状態を初期化し、次回開始時にクリーンな状態を保証
        performReset()
        if let dismissAction = dismissGameView {
            // 親側が専用クロージャを提供している場合はそちらを優先
            dismissAction()
        } else if presentationMode.wrappedValue.isPresented {
            // モーダル表示中であれば標準の dismiss を利用して前画面へ戻る
            presentationMode.wrappedValue.dismiss()
        }
    }

    /// タイトルへ戻る操作を提示できるかどうかを判定する補助プロパティ
    private var canReturnToTitle: Bool {
        dismissGameView != nil || presentationMode.wrappedValue.isPresented
    }

    /// メニューのレイアウトをまとめたビュー。アクションの追加・削除にも対応しやすくする
    @ViewBuilder
    private var actionMenu: some View {
        Menu {
            // MARK: - ゲームリセットアクション
            Button {
                showingResetConfirmation = true
            } label: {
                Label("リセット", systemImage: "arrow.counterclockwise")
            }

            // MARK: - タイトルへ戻るアクション（導線がある場合のみ表示）
            if canReturnToTitle {
                Button {
                    showingReturnConfirmation = true
                } label: {
                    Label("タイトルへ戻る", systemImage: "house")
                }
            }
        } label: {
            // メニューアイコン自体は視認性を高めるため半透明の背景を重ねる
            Image(systemName: "ellipsis.circle")
                .font(.title2)
                .foregroundColor(.white)
                .padding(10)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.35))
                )
        }
        .accessibilityIdentifier("game_action_menu")
        .padding([.top, .trailing], 12)
    }

    /// スロットの状態変化をアニメーション制御用に表すキーを生成する
    /// - Parameter index: 対象スロットの添字
    /// - Returns: カードが変化した際にのみ値が変わる文字列キー
    private func slotAnimationKey(for index: Int) -> String {
        if let card = handCard(at: index) {
            // カード名に添字を付加してユニークなキーとし、重複カードでもスロット単位で識別
            return "card_\(index)_\(card.displayName)"
        } else {
            // 空スロットの場合は専用キーを返し、連続で空でもレイアウトが乱れない
            return "empty_\(index)"
        }
    }

    /// 手札が空の際に表示するプレースホルダビュー
    /// - Note: 実カードと同じサイズを確保してレイアウトのズレを防ぐ
    private func placeholderCardView() -> some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4]))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.white.opacity(0.05))
            )
            .frame(width: 60, height: 80)
            .overlay(
                Image(systemName: "questionmark")
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.4))
            )
            .accessibilityHidden(true)  // プレースホルダは VoiceOver の読み上げ対象外にして混乱を避ける
    }

}

// MARK: - 先読みカード専用のオーバーレイ
/// 「NEXT」バッジと点滅インジケータを重ね、操作不可であることを視覚的に伝える補助ビュー
private struct NextCardOverlayView: View {
    /// 点滅インジケータの明るさを制御するステート
    @State private var isIndicatorBright = false

    var body: some View {
        ZStack {
            // MARK: - 上部の NEXT バッジ
            VStack {
                HStack {
                    Text("NEXT")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundColor(.white)
                        .background(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.7), lineWidth: 1)
                                .background(Capsule().fill(Color.white.opacity(0.18)))
                        )
                        .padding([.top, .leading], 6)
                        .accessibilityHidden(true)  // バッジは視覚的強調のみなので読み上げ対象外にする
                    Spacer()
                }
                Spacer()
            }

            // MARK: - 右下の点滅インジケータ
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Circle()
                        .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(0.85))
                                .frame(width: 8, height: 8)
                                .opacity(isIndicatorBright ? 1.0 : 0.2)
                        )
                        .shadow(color: Color.white.opacity(isIndicatorBright ? 0.6 : 0.1), radius: isIndicatorBright ? 4 : 0)
                        .padding(6)
                        .accessibilityHidden(true)  // 視覚的なアクセントのみのため VoiceOver では読み上げない
                }
            }
        }
        .onAppear {
            // MARK: - 点滅アニメーションを開始
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                isIndicatorBright = true
            }
        }
        .allowsHitTesting(false)  // 補助ビューはタップ処理に影響させない
    }
}

// MARK: - プレビュー
#Preview {
    // Xcode の Canvas で GameView を表示するためのプレビュー
    GameView()
}

// MARK: - 環境値の拡張
/// 親ビューが GameView を閉じたい場合に利用するカスタム EnvironmentKey
private struct GameViewDismissActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

extension EnvironmentValues {
    /// GameView からタイトルへ戻る際に呼び出されるクロージャを格納するキー
    var dismissGameView: (() -> Void)? {
        get { self[GameViewDismissActionKey.self] }
        set { self[GameViewDismissActionKey.self] = newValue }
    }
}
