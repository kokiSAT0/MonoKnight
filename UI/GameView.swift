import SpriteKit
import SwiftUI
import UIKit  // ハプティクス用のフレームワークを追加

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
    /// ハプティクスを有効にするかどうかの設定値
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true

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
                            // MoveCard は Identifiable に準拠していないため、enumerated の offset を id として利用
                            ForEach(Array(core.hand.enumerated()), id: \.offset) { index, card in
                                MoveCardIllustrationView(card: card, mode: .hand)
                                    // 盤外に出るカードは薄く表示し、タップを無効化
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
                            }
                        }

                        // 先読みカードが存在する場合に表示
                        if let next = core.next {
                            VStack(alignment: .leading, spacing: 8) {
                                // タイトルテキストは視覚的な見出しとしてのみ表示し、VoiceOver ではカードのラベルを優先
                                Text("次に補充されるカード")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .accessibilityHidden(true)

                                MoveCardIllustrationView(card: next, mode: .next)
                                    // 操作できないことを明確にするためヒットテストを無効化
                                    .allowsHitTesting(false)
                                    // 左上に NEXT バッジを重ねて先読みであることを強調
                                    .overlay(alignment: .topLeading) {
                                        NextCardBadgeView()
                                            .padding(6)
                                            .accessibilityHidden(true)
                                    }
                                    // 右上に点滅インジケータを配置して更新待ちであることを示す
                                    .overlay(alignment: .topTrailing) {
                                        NextCardIndicatorView()
                                            .padding(6)
                                            .accessibilityHidden(true)
                                    }
                                    // 下部には「操作不可」バッジを配置してタップ無効を明示
                                    .overlay(alignment: .bottom) {
                                        Text("操作不可")
                                            .font(.caption2)
                                            .foregroundColor(.white.opacity(0.75))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule()
                                                    .fill(Color.white.opacity(0.08))
                                            )
                                            .overlay(
                                                Capsule()
                                                    .stroke(Color.white.opacity(0.25), lineWidth: 0.5)
                                            )
                                            .padding(.bottom, 6)
                                            .accessibilityHidden(true)
                                    }
                            }
                        }
                    }
                    .padding(.bottom, 16)
                }
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

}

// MARK: - 先読みバッジ用の補助ビュー
private struct NextCardBadgeView: View {
    var body: some View {
        // シンプルなカプセル型バッジで「NEXT」を表示
        Text("NEXT")
            .font(.caption2.bold())
            .kerning(1)
            .foregroundColor(.white.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.3), lineWidth: 0.6)
            )
    }
}

// MARK: - 点滅インジケータビュー
private struct NextCardIndicatorView: View {
    /// アニメーション状態をトグルするフラグ
    @State private var isAnimating = false

    var body: some View {
        // 2 重円で柔らかく点滅させ、先読み更新を示唆する
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                .frame(width: 16, height: 16)
                .scaleEffect(isAnimating ? 1.2 : 0.9)
                .opacity(isAnimating ? 0.25 : 0.5)

            Circle()
                .fill(Color.white.opacity(0.85))
                .frame(width: 6, height: 6)
        }
        .onAppear {
            // Appear 時にアニメーションを開始
            isAnimating = true
        }
        .animation(
            .easeInOut(duration: 1.1)
                .repeatForever(autoreverses: true),
            value: isAnimating
        )
    }
}

// MARK: - プレビュー
#Preview {
    // Xcode の Canvas で GameView を表示するためのプレビュー
    GameView()
}
