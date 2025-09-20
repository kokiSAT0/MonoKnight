import SpriteKit
import SwiftUI
import UIKit  // ハプティクス用のフレームワークを追加

/// SwiftUI から SpriteKit の盤面を表示するビュー
/// 画面下部に手札 3 枚と次に引かれるカードを表示し、
/// タップで GameCore を更新する
struct GameView: View {
    /// カラーテーマを生成し、ビュー全体で共通の配色を利用できるようにする
    private var theme = AppTheme()
    /// 現在のライト/ダーク設定を環境から取得し、SpriteKit 側の色にも反映する
    @Environment(\.colorScheme) private var colorScheme
    /// 手札スロットの数（常に 5 枚分の枠を確保してレイアウトを安定させる）
    private let handSlotCount = 5
    /// ゲームロジックを保持する ObservableObject
    /// - NOTE: `StateObject` は init 内で明示的に生成し、GameScene に渡す
    @StateObject private var core: GameCore
    /// 結果画面を表示するかどうかのフラグ
    /// - NOTE: クリア時に true となり ResultView をシート表示する
    @State private var showingResult = false
    /// 手詰まりペナルティのバナー表示を制御するフラグ
    @State private var isShowingPenaltyBanner = false
    /// バナーを自動的に閉じるためのディスパッチワークアイテムを保持
    @State private var penaltyDismissWorkItem: DispatchWorkItem?
    /// SpriteKit のシーン。初期化時に一度だけ生成して再利用する
    private let scene: GameScene
    /// Game Center 連携を扱うサービス（プロトコル型で受け取る）
    private let gameCenterService: GameCenterServiceProtocol
    /// 広告表示を扱うサービス（プロトコル型で受け取る）
    private let adsService: AdsServiceProtocol
    /// ハプティクスを有効にするかどうかの設定値
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true
    /// ガイドモードのオン/オフを永続化し、盤面ハイライト表示を制御する
    @AppStorage("guide_mode_enabled") private var guideModeEnabled: Bool = true
    /// タイトル画面へ戻るアクションを親から注入する（未指定なら nil で何もしない）
    private let onRequestReturnToTitle: (() -> Void)?
    /// メニューからの操作確認ダイアログで使用する一時的なアクション保持
    @State private var pendingMenuAction: GameMenuAction?

    /// 初期化で GameCore と GameScene を連結する
    /// 依存するサービスを外部から注入できるようにする初期化処理
    /// - Parameters:
    ///   - gameCenterService: Game Center 連携用サービス（デフォルトはシングルトン）
    ///   - adsService: 広告表示用サービス（デフォルトはシングルトン）
    init(
        gameCenterService: GameCenterServiceProtocol = GameCenterService.shared,
        adsService: AdsServiceProtocol = AdsService.shared,
        onRequestReturnToTitle: (() -> Void)? = nil
    ) {
        // GameCore の生成。StateObject へ包んで保持する
        let core = GameCore()
        _core = StateObject(wrappedValue: core)

        // GameScene はインスタンス生成後にサイズとスケールを指定
        let scene = GameScene()
        scene.scaleMode = .resizeFill
        // GameScene から GameCore へタップイベントを伝えるため参照を渡す
        // StateObject へ格納した同一インスタンスを直接渡し、wrappedValue へ触れず安全に保持する
        scene.gameCore = core
        self.scene = scene
        // サービスを保持
        self.gameCenterService = gameCenterService
        self.adsService = adsService
        self.onRequestReturnToTitle = onRequestReturnToTitle
    }

    var body: some View {
        GeometryReader { geometry in
            // MARK: - 盤面サイズのキャッシュ
            // 同一の幅計算を繰り返さないようローカル定数へ格納する
            let boardWidth = geometry.size.width

            ZStack(alignment: .topTrailing) {
                VStack(spacing: 16) {
                    boardSection(width: boardWidth)
                    handSection()
                }
                // MARK: - 手詰まりペナルティ通知バナー
                penaltyBannerOverlay

                // MARK: - 右上のメニューボタンとデバッグ向けショートカット
                topRightOverlay
            }
            // 画面全体の背景もテーマで制御し、システム設定と調和させる
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.backgroundPrimary)
        }
        // 初回表示時に SpriteKit の背景色もテーマに合わせて更新
        .onAppear {
            // ビュー再表示時に GameScene へ GameCore の参照を再連結し、弱参照が nil にならないよう保証
            scene.gameCore = core
            applyScenePalette(for: colorScheme)
            // 初期状態でもガイド表示のオン/オフに応じてハイライトを更新
            refreshGuideHighlights()
        }
        // ライト/ダーク切り替えが発生した場合も SpriteKit 側へ反映
        .onChange(of: colorScheme) { _, newScheme in
            applyScenePalette(for: newScheme)
            // カラースキーム変更時はガイドの色味も再描画して視認性を確保
            refreshGuideHighlights()
        }
        // progress が .cleared へ変化したタイミングで結果画面を表示
        .onChange(of: core.progress) { _, newValue in
            guard newValue == .cleared else { return }
            gameCenterService.submitScore(core.score)
            showingResult = true
        }

        // 手詰まりペナルティ発生時のバナー表示を制御
        .onReceive(core.$penaltyEventID) { eventID in
            guard eventID != nil else { return }

            // 既存の自動クローズ処理があればキャンセルして状態をリセット
            penaltyDismissWorkItem?.cancel()
            penaltyDismissWorkItem = nil

            // バナーをアニメーション付きで表示
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8, blendDuration: 0.2)) {
                isShowingPenaltyBanner = true
            }

            // ペナルティ発生を触覚で知らせる（設定で有効な場合のみ）
            if hapticsEnabled {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }

            // 一定時間後に自動でバナーを閉じる処理を登録
            let workItem = DispatchWorkItem {
                withAnimation(.easeOut(duration: 0.25)) {
                    isShowingPenaltyBanner = false
                }
                penaltyDismissWorkItem = nil
            }
            penaltyDismissWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: workItem)
        }
        // 手札内容が変わるたびに移動候補を再計算し、ガイドハイライトを更新
        .onReceive(core.$hand) { _ in
            refreshGuideHighlights()
        }
        // ガイドモードのオン/オフを切り替えたら即座に SpriteKit へ反映
        .onChange(of: guideModeEnabled) { _, _ in
            refreshGuideHighlights()
        }
        // 進行状態が変化した際もハイライトを整理（手詰まり・クリア時は消灯）
        .onReceive(core.$progress) { progress in
            if progress == .playing {
                refreshGuideHighlights()
            } else {
                scene.updateGuideHighlights([])
            }
        }

        // シートで結果画面を表示
        .sheet(isPresented: $showingResult) {
            ResultView(
                moveCount: core.moveCount,
                penaltyCount: core.penaltyCount,
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
        // メニュー選択後に確認ダイアログを表示し、誤操作を防ぐ
        .confirmationDialog(
            "操作の確認",
            isPresented: Binding(
                get: { pendingMenuAction != nil },
                set: { isPresented in
                    // キャンセル操作で閉じられた場合もステートを初期化する
                    if !isPresented {
                        pendingMenuAction = nil
                    }
                }
            ),
            presenting: pendingMenuAction
        ) { action in
            Button(action.confirmationButtonTitle, role: action.buttonRole) {
                // ユーザーの確認後に実際の処理を実行
                performMenuAction(action)
            }
        } message: { action in
            Text(action.confirmationMessage)
        }
    }

    /// 盤面の統計と SpriteKit ボードをまとめて描画する
    /// - Parameter width: GeometryReader で算出した盤面の幅（正方形表示の基準）
    /// - Returns: 統計バッジと SpriteView を縦に並べた領域
    private func boardSection(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // MARK: - ゲーム進行度を示すバッジ群
            // 盤面と重ならないよう先に配置し、VoiceOver が確実に読み上げる構造に整える
            HStack(spacing: 12) {
                statisticBadge(
                    title: "移動",
                    value: "\(core.moveCount)",
                    accessibilityLabel: "移動回数",
                    accessibilityValue: "\(core.moveCount)回"
                )

                statisticBadge(
                    title: "ペナルティ",
                    value: "\(core.penaltyCount)",
                    accessibilityLabel: "ペナルティ回数",
                    accessibilityValue: "\(core.penaltyCount)手"
                )

                statisticBadge(
                    title: "残りマス",
                    value: "\(core.remainingTiles)",
                    accessibilityLabel: "残りマス数",
                    accessibilityValue: "残り\(core.remainingTiles)マス"
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                // 盤面外でも読みやすさを維持する半透明の背景（テーマから取得）
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.statisticBadgeBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    // テーマに合わせた薄い境界線でバッジを引き締める
                    .stroke(theme.statisticBadgeBorder, lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .accessibilityElement(children: .contain)

            spriteBoard(width: width)
        }
    }

    /// SpriteKit の盤面を描画し、ライフサイクルに応じた更新処理をまとめる
    /// - Parameter width: 正方形に保つための辺長
    /// - Returns: onAppear / onReceive を含んだ SpriteView
    private func spriteBoard(width: CGFloat) -> some View {
        SpriteView(scene: scene)
            // 正方形で表示したいため幅に合わせる
            .frame(width: width, height: width)
            .onAppear {
                // サイズと初期状態を反映
                scene.size = CGSize(width: width, height: width)
                scene.updateBoard(core.board)
                scene.moveKnight(to: core.current)
                // 盤面の同期が整ったタイミングでガイド表示も更新
                refreshGuideHighlights()
            }
            // GameCore 側の更新を受け取り、SpriteKit の表示へ同期する
            .onReceive(core.$board) { newBoard in
                scene.updateBoard(newBoard)
                // 盤面の踏破状況が変わっても候補マスの情報を最新化
                refreshGuideHighlights()
            }
            .onReceive(core.$current) { newPoint in
                scene.moveKnight(to: newPoint)
                // 現在位置が変化したら移動候補も追従する
                refreshGuideHighlights()
            }
    }

    /// 手札と先読みカードの表示をまとめた領域
    /// - Returns: 下部 UI 全体（余白調整を含む）
    private func handSection() -> some View {
        VStack(spacing: 8) {
            // 手札 3 枚を横並びで表示
            HStack(spacing: 12) {
                // 固定長スロットで回し、欠番があっても UI が崩れないようにする
                ForEach(0..<handSlotCount, id: \.self) { index in
                    handSlotView(for: index)
                }
            }

            // 先読みカードが存在する場合に表示（最大 3 枚を横並びで案内）
            if !core.nextCards.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    // MARK: - 先読みカードのラベル
                    // テキストでセクションを明示して VoiceOver からも認識しやすくする
                    Text("次のカード")
                        .font(.caption)
                        // テーマのサブ文字色で読みやすさと一貫性を確保
                        .foregroundColor(theme.textSecondary)
                        .accessibilityHidden(true)  // ラベル自体は MoveCardIllustrationView のラベルに統合する

                    // MARK: - 先読みカード本体
                    // 3 枚までのカードを順番に描画し、それぞれにインジケータを重ねる
                    HStack(spacing: 12) {
                        ForEach(Array(core.nextCards.enumerated()), id: \.offset) { index, card in
                            ZStack {
                                MoveCardIllustrationView(card: card, mode: .next)
                                NextCardOverlayView(order: index)
                            }
                            // VoiceOver で順番が伝わるようラベルを上書き
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(Text("次のカード\(index == 0 ? "" : "+\(index)"): \(card.displayName)"))
                            .accessibilityHint(Text("この順番で手札に補充されます"))
                            .allowsHitTesting(false)  // 先読みは閲覧専用
                        }
                    }
                }
            }

#if DEBUG
            // MARK: - デバッグ専用ショートカット
            // 盤面の右上オーバーレイに重ねると UI が窮屈になるため、下部セクションへ移設
            HStack {
                Spacer(minLength: 0)
                debugResultButton
                    .padding(.top, 4)  // 手札との距離を確保して視認性を確保
                Spacer(minLength: 0)
            }
#endif
        }
        .padding(.bottom, 16)
    }

    /// 手動ペナルティ（手札引き直し）のショートカットボタン
    /// - Note: 右上メニューの横へアイコンのみで配置し、省スペース化しつつ操作性を維持する
    private var manualPenaltyButton: some View {
        // ゲームが進行中でない場合は無効化し、リザルト表示中などの誤操作を回避
        let isDisabled = core.progress != .playing

        return Button {
            // 実行前に必ず確認ダイアログを挟むため、既存のメニューアクションを再利用
            pendingMenuAction = .manualPenalty
        } label: {
            // MARK: - ボタンは 44pt 以上の円形領域で構成し、メニューアイコンとの統一感を持たせる
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.menuIconForeground)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(theme.menuIconBackground)
                )
                .overlay(
                    Circle()
                        .stroke(theme.menuIconBorder, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(isDisabled ? 0.45 : 1.0)
        .disabled(isDisabled)
        .accessibilityIdentifier("manual_penalty_button")
        .accessibilityLabel(Text("ペナルティを払って手札を引き直す"))
        .accessibilityHint(Text("手数を5消費して現在の手札を全て捨て、新しいカードを3枚引きます。"))
    }

    /// 手詰まりペナルティを知らせるバナーのレイヤーを構成
    private var penaltyBannerOverlay: some View {
        VStack {
            if isShowingPenaltyBanner {
                HStack {
                    Spacer(minLength: 0)
                    PenaltyBannerView()
                        .padding(.horizontal, 20)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .accessibilityIdentifier("penalty_banner")
                    Spacer(minLength: 0)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 12)
        .allowsHitTesting(false)  // バナーが表示されていても下の UI を操作可能にする
        .zIndex(2)
    }

    /// SpriteKit シーンの配色を現在のテーマに合わせて調整する
    /// - Parameter scheme: ユーザーが選択中のライト/ダーク種別
    private func applyScenePalette(for scheme: ColorScheme) {
        // SwiftUI 環境のカラースキームを明示指定した AppTheme を生成し、SpriteKit 側へ適用
        let spriteTheme = AppTheme(colorScheme: scheme)
        scene.applyTheme(spriteTheme)
    }

    /// ガイドモードの設定と現在の手札から移動可能なマスを算出し、SpriteKit 側へ通知する
    private func refreshGuideHighlights() {
        // ガイドモードが無効・ゲームが停止状態ならハイライトをすべて消灯
        guard guideModeEnabled, core.progress == .playing else {
            scene.updateGuideHighlights([])
            return
        }

        var highlightPoints: Set<GridPoint> = []
        for card in core.hand {
            let destination = core.current.offset(dx: card.dx, dy: card.dy)
            if core.board.contains(destination) {
                highlightPoints.insert(destination)
            }
        }

        // 算出した集合を SpriteKit へ渡し、視覚的なサポートを行う
        scene.updateGuideHighlights(highlightPoints)
    }

    /// 指定カードが現在位置から盤内に収まるか判定
    /// - Note: MoveCard は列挙型であり、dx/dy プロパティから移動量を取得する
    private func isCardUsable(_ card: MoveCard) -> Bool {
        // 現在位置に MoveCard の移動量を加算して目的地を算出
        let target = core.current.offset(dx: card.dx, dy: card.dy)
        // 目的地が盤面内に含まれているかどうかを判定
        return core.board.contains(target)
    }

    /// 盤面上部に表示する統計テキストの共通レイアウト
    /// - Parameters:
    ///   - title: メトリクスのラベル（例: 移動）
    ///   - value: 表示する数値文字列
    ///   - accessibilityLabel: VoiceOver に読み上げさせる日本語ラベル
    ///   - accessibilityValue: VoiceOver 用の値（単位を含めた文章）
    /// - Returns: モノクロ配色の小型バッジビュー
    private func statisticBadge(
        title: String,
        value: String,
        accessibilityLabel: String,
        accessibilityValue: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            // 補助ラベルは控えめなトーンで表示
            Text(title)
                .font(.caption2)
                .fontWeight(.medium)
                // テーマの補助文字色でライト/ダーク双方のコントラストを調整
                .foregroundColor(theme.statisticTitleText)

            // 主数値は視認性を高めるためサイズとコントラストを強調
            Text(value)
                .font(.headline)
                .foregroundColor(theme.statisticValueText)
        }
        // VoiceOver ではカスタムラベルと値を読み上げさせる
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
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
            // テーマ由来の枠線色でライト/ダークの差異を吸収
            .stroke(theme.placeholderStroke, style: StrokeStyle(lineWidth: 1, dash: [4]))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    // 枠内もテーマ色で淡く塗りつぶし、背景とのコントラストを確保
                    .fill(theme.placeholderBackground)
            )
            .frame(width: 60, height: 80)
            .overlay(
                Image(systemName: "questionmark")
                    .font(.caption)
                    // プレースホルダアイコンもテーマ色で調整
                    .foregroundColor(theme.placeholderIcon)
            )
            .accessibilityHidden(true)  // プレースホルダは VoiceOver の読み上げ対象外にして混乱を避ける
    }

}

// MARK: - 右上メニューおよびデバッグ操作
private extension GameView {
    /// 右上のメニューとショートカットボタンをまとめて返す
    /// - Returns: HStack で横並びにしたコントロール群
    @ViewBuilder
    private var topRightOverlay: some View {
        HStack(spacing: 12) {
            // MARK: - 手札引き直しを素早く行うためのミニボタン
            manualPenaltyButton

            // MARK: - サブメニュー（リセット/タイトル戻りなど）
            menuButton
        }
        .padding(.trailing, 16)
        .padding(.top, 16)
        // ペナルティバナーよりも手前に配置してタップできるようにする
        .zIndex(3)
    }

    /// ゲーム全体に関わる操作をまとめたメニュー
    private var menuButton: some View {
        Menu {
            // MARK: - メニュー内にはリセット系のみ配置（手札引き直しは隣のアイコンから操作）

            // MARK: - ゲームリセット操作
            Button {
                // 実行前に確認ダイアログを表示するため、ステートへ保持
                pendingMenuAction = .reset
            } label: {
                Label("リセット", systemImage: "arrow.counterclockwise")
            }

            // MARK: - タイトル画面へ戻る操作
            Button(role: .destructive) {
                pendingMenuAction = .returnToTitle
            } label: {
                Label("タイトルへ戻る", systemImage: "house")
            }
        } label: {
            // 常に 44pt 以上のタップ領域を確保する
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 22, weight: .semibold))
                // テーマの前景色でアイコンを描画し、背景色変更に追従
                .foregroundColor(theme.menuIconForeground)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        // 背景もテーマから取得し、ライトモードでも主張しすぎない色合いに調整
                        .fill(theme.menuIconBackground)
                )
                .overlay(
                    Circle()
                        // わずかな境界線で視認性を高める
                        .stroke(theme.menuIconBorder, lineWidth: 1)
                )
        }
        .accessibilityIdentifier("game_menu")
    }

    #if DEBUG
    /// 結果画面を即座に表示するデバッグ向けボタン
    private var debugResultButton: some View {
        Button(action: {
            // 直接結果画面を開き、UI の確認やデバッグを容易にする
            showingResult = true
        }) {
            Text("結果へ")
        }
        .buttonStyle(.bordered)
        // UI テストでボタンを特定できるよう識別子を設定
        .accessibilityIdentifier("show_result")
    }
    #endif

    /// メニュー操作を実際に実行する共通処理
    /// - Parameter action: ユーザーが選択した操作種別
    private func performMenuAction(_ action: GameMenuAction) {
        // ダイアログを閉じるために必ず nil へ戻す
        pendingMenuAction = nil

        switch action {
        case .manualPenalty:
            // 既存バナーの自動クローズ処理を停止し、新規イベントに備える
            penaltyDismissWorkItem?.cancel()
            penaltyDismissWorkItem = nil
            isShowingPenaltyBanner = false
            // GameCore の共通処理を呼び出し、手動ペナルティを適用
            core.applyManualPenaltyRedraw()

        case .reset:
            // バナー表示をリセットし、ゲームを初期状態へ戻す
            penaltyDismissWorkItem?.cancel()
            penaltyDismissWorkItem = nil
            isShowingPenaltyBanner = false
            // シートが開いている場合でも即座に閉じる
            showingResult = false
            core.reset()
            adsService.resetPlayFlag()

        case .returnToTitle:
            // リセットと同じ処理を実行した後にタイトル戻りを通知
            penaltyDismissWorkItem?.cancel()
            penaltyDismissWorkItem = nil
            isShowingPenaltyBanner = false
            showingResult = false
            core.reset()
            adsService.resetPlayFlag()
            onRequestReturnToTitle?()
        }
    }
}

// MARK: - メニュー操作の定義
private enum GameMenuAction: Hashable, Identifiable {
    case manualPenalty
    case reset
    case returnToTitle

    /// Identifiable 準拠のための一意な ID
    var id: Int {
        switch self {
        case .manualPenalty:
            return 0
        case .reset:
            return 1
        case .returnToTitle:
            return 2
        }
    }

    /// ダイアログ内で表示するボタンタイトル
    var confirmationButtonTitle: String {
        switch self {
        case .manualPenalty:
            return "ペナルティを払う"
        case .reset:
            return "リセットする"
        case .returnToTitle:
            return "タイトルへ戻る"
        }
    }

    /// 操作説明として表示するメッセージ
    var confirmationMessage: String {
        switch self {
        case .manualPenalty:
            return "手数を5増やして手札を引き直します。現在の手札は破棄されます。よろしいですか？"
        case .reset:
            return "現在の進行状況を破棄して、最初からやり直します。よろしいですか？"
        case .returnToTitle:
            return "ゲームを終了してタイトル画面へ戻ります。現在のプレイ内容は保存されません。"
        }
    }

    /// ボタンのロール（破壊的操作は .destructive を指定）
    var buttonRole: ButtonRole? {
        switch self {
        case .manualPenalty:
            return .destructive
        case .reset:
            return .destructive
        case .returnToTitle:
            return .destructive
        }
    }
}

// MARK: - 手詰まりペナルティ用のバナー表示
/// ペナルティ発生をユーザーに伝えるトップバナーのビュー
private struct PenaltyBannerView: View {
    /// バナー配色を一元管理するテーマ
    private var theme = AppTheme()

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // MARK: - 警告アイコン
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20, weight: .semibold))
                // テーマの反転色を利用し、背景とのコントラストを確保
                .foregroundColor(theme.penaltyIconForeground)
                .padding(8)
                .background(
                    Circle()
                        // アイコン背景もテーマ側のアクセントに合わせる
                        .fill(theme.penaltyIconBackground)
                )
                .accessibilityHidden(true)  // アイコンは視覚的アクセントのみ

            // MARK: - メッセージ本文
            VStack(alignment: .leading, spacing: 2) {
                Text("手詰まり → 手札を引き直し (+5)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    // メインテキストはテーマに合わせた明度で表示
                    .foregroundColor(theme.penaltyTextPrimary)
                Text("使えるカードが無かったため、手数が 5 増加しました")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(theme.penaltyTextSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                // バナーの背景はテーマ設定で透明感を調整
                .fill(theme.penaltyBannerBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.penaltyBannerBorder, lineWidth: 1)
                )
        )
        .shadow(color: theme.penaltyBannerShadow, radius: 18, x: 0, y: 12)
        .accessibilityIdentifier("penalty_banner_content")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("手詰まり。手札を引き直し、手数が 5 増加しました。")
    }
}

// MARK: - 先読みカード専用のオーバーレイ
/// 「NEXT」「NEXT+1」などのバッジと点滅インジケータを重ね、操作不可であることを視覚的に伝える補助ビュー
fileprivate struct NextCardOverlayView: View {
    /// 表示中のカードが何枚目の先読みか（0 が直近、1 以降は +1, +2 ...）
    let order: Int
    /// 点滅インジケータの明るさを制御するステート
    @State private var isIndicatorBright = false
    /// 先読みオーバーレイの配色を統一するテーマ
    private let theme = AppTheme()

    // MARK: - 初期化
    /// 先読みカードの表示順を受け取り、必要なステートを既定値で初期化する
    /// - Parameter order: 0 始まりでの先読み順序
    fileprivate init(order: Int) {
        self.order = order
    }

    /// バッジに表示する文言を算出するヘルパー
    private var badgeText: String {
        order == 0 ? "NEXT" : "NEXT+\(order)"
    }

    var body: some View {
        ZStack {
            // MARK: - 上部の NEXT バッジ
            VStack {
                HStack {
                    Text(badgeText)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        // テーマ経由でラベル色を取得し、ライトモードでも視認性を保つ
                        .foregroundColor(theme.nextBadgeText)
                        .background(
                            Capsule()
                                .strokeBorder(theme.nextBadgeBorder, lineWidth: 1)
                                .background(Capsule().fill(theme.nextBadgeBackground))
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
                        .stroke(theme.nextIndicatorStroke, lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                        .overlay(
                            Circle()
                                .fill(theme.nextIndicatorFill)
                                .frame(width: 8, height: 8)
                                .opacity(isIndicatorBright ? 1.0 : 0.2)
                        )
                        .shadow(color: theme.nextIndicatorShadow.opacity(isIndicatorBright ? 1.0 : 0.2), radius: isIndicatorBright ? 4 : 0)
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
