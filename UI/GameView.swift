import SwiftUI
import SpriteKit
import Game
import UIKit // ハプティクス用のフレームワークを追加

/// SwiftUI から SpriteKit の盤面を表示するビュー
/// 画面下部に手札 3 枚と次に引かれるカードを表示し、
/// タップで GameCore を更新する
struct GameView: View {
    /// ゲームロジックを保持する ObservableObject
    /// - NOTE: `StateObject` は init 内で明示的に生成し、GameScene に渡す
    @StateObject private var core: GameCore
    /// 結果画面を表示するかどうかのフラグ
    /// - NOTE: クリア時に true となり ResultView をシート表示する
    @State private var showingResult = false
    /// SpriteKit のシーン。初期化時に一度だけ生成して再利用する
    private let scene: GameScene
    /// Game Center 連携を扱うサービス（プロトコル型で受け取る）
    private let gameCenterService: GameCenterServiceProtocol
    /// 広告表示を扱うサービス（プロトコル型で受け取る）
    private let adsService: AdsServiceProtocol

    /// 初期化で GameCore と GameScene を連結する
    /// 依存するサービスを外部から注入できるようにする初期化処理
    /// - Parameters:
    ///   - gameCenterService: Game Center 連携用サービス（デフォルトはシングルトン）
    ///   - adsService: 広告表示用サービス（デフォルトはシングルトン）
    init(gameCenterService: GameCenterServiceProtocol = GameCenterService.shared,
         adsService: AdsServiceProtocol = AdsService.shared) {
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
                        scene.size = CGSize(width: geometry.size.width, height: geometry.size.width)
                        scene.updateBoard(core.board)
                        scene.moveKnight(to: core.current)
                    }
                    // board が更新されたら色を反映
                    .onChange(of: core.board) { newBoard in
                        scene.updateBoard(newBoard)
                    }
                    // current が更新されたら駒を移動
                    .onChange(of: core.current) { newPoint in
                        scene.moveKnight(to: newPoint)
                    }

                    // MARK: 手札と先読みカードの表示
                    VStack(spacing: 8) {
                        // 手札 3 枚を横並びで表示
                        HStack(spacing: 12) {
                            // MoveCard は Identifiable に準拠していないため、enumerated の offset を id として利用
                            ForEach(Array(core.hand.enumerated()), id: \.offset) { index, card in
                                cardView(for: card)
                                    // 盤外に出るカードは薄く表示し、タップを無効化
                                    .opacity(isCardUsable(card) ? 1.0 : 0.4)
                                    .onTapGesture {
                                        // ハプティクス生成器を都度生成
                                        let generator = UINotificationFeedbackGenerator()
                                        // 列挙型 MoveCard の使用可否を判定
                                        if isCardUsable(card) {
                                            // 使用可能 ⇒ ゲーム状態を更新し、成功フィードバックを発火
                                            core.playCard(at: index)
                                            generator.notificationOccurred(.success)
                                        } else {
                                            // 使用不可 ⇒ 警告フィードバックのみを発火
                                            generator.notificationOccurred(.warning)
                                        }
                                    }
                            }
                        }

                        // 先読みカードが存在する場合に表示
                        if let next = core.next {
                            HStack(spacing: 4) {
                                Text("次のカード")
                                    .font(.caption)
                                cardView(for: next)
                                    .opacity(0.6) // 先読みは操作不可なので半透明
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
            // MARK: - 結果画面表示ボタン（テスト用）
            Button(action: {
                // 直接結果画面を開くことで UI テストを容易にする
                showingResult = true
            }) {
                Text("結果へ")
            }
            .padding()
            .buttonStyle(.bordered)
            .accessibilityIdentifier("show_result")
        }
        // 画面全体を黒背景に統一
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
        // progress が .cleared へ変化したタイミングで結果画面を表示
        .onChange(of: core.progress) { newValue in
            guard newValue == .cleared else { return }
            // Game Center へスコア送信
            gameCenterService.submitScore(core.score)
            // 結果画面を開く
            showingResult = true
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

    /// カードの簡易表示ビュー
    /// - Parameter card: 表示対象の MoveCard（列挙型）
    private func cardView(for card: MoveCard) -> some View {
        ZStack {
            // 枠付きの白いカードを描画
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white, lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.2))
                )
            // MoveCard に定義された displayName を表示（例: 上2右1）
            Text(card.displayName)
                .font(.caption)
                .foregroundColor(.white)
        }
        .frame(width: 60, height: 80)
        // VoiceOver での読み上げ用ラベルを設定
        .accessibilityLabel(Text(card.displayName))
        // 操作方法を案内するヒントを付与（ダブルタップで使用）
        .accessibilityHint(Text("ダブルタップでこの方向に移動します"))
        // ボタンとして扱わせるためのトレイトを追加
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - プレビュー
#Preview {
    // Xcode の Canvas で GameView を表示するためのプレビュー
    GameView()
}

