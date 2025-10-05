import SwiftUI
import Combine
import Game

// MARK: - 日替わりチャレンジ画面用ビューモデル
/// 日替わりチャレンジの挑戦可否や表示文言を集約する `ObservableObject`
/// - Note: UI からは Published プロパティ経由で状態変化を監視し、ボタン有効/無効やテキストの更新を反映する
@MainActor
final class DailyChallengeViewModel: ObservableObject {
    // MARK: 内部で利用するアラート表現
    /// ユーザーへ提示するアラート情報
    struct AlertState: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// 挑戦回数ストア（挑戦消費や広告付与を司る）
    private let attemptStore: AnyDailyChallengeAttemptStore
    /// 日替わりモードの定義サービス
    private let definitionService: DailyChallengeDefinitionProviding
    /// 広告サービス（リワード広告の表示に利用する）
    private let adsService: AdsServiceProtocol
    /// Game Center 連携用サービス（ランキング表示に利用）
    private let gameCenterService: GameCenterServiceProtocol
    /// 日付計算を制御するクロージャ（テストで固定日付を注入しやすくする）
    private let nowProvider: () -> Date
    /// 表示用日付フォーマッタ（年月日+曜日をまとめて描画する）
    private let dateFormatter: DateFormatter
    /// 表示用時間フォーマッタ（リセット時刻をローカル時間で案内する）
    private let resetFormatter: DateFormatter
    /// `attemptStore.objectWillChange` を購読して状態同期するためのキャンセラ
    private var cancellable: AnyCancellable?

    /// 現在表示しているチャレンジ情報バンドル
    @Published private(set) var challengeBundle: DailyChallengeDefinitionService.ChallengeBundle
    /// 「2025年5月26日 (月)」のような日付表示用テキスト
    @Published private(set) var challengeDateText: String
    /// 「残り 1 回 / 最大 4 回」のような残量テキスト
    @Published private(set) var remainingAttemptsText: String
    /// 「広告追加済み: 0 / 3」のようなリワード進捗テキスト
    @Published private(set) var rewardProgressText: String
    /// 「リセット: 05/27(火) 09:00」のようなリセット案内テキスト
    @Published private(set) var resetTimeText: String
    /// 挑戦開始ボタンを有効化してよいか
    @Published private(set) var isStartButtonEnabled: Bool
    /// リワード広告ボタンを有効化してよいか
    @Published private(set) var isRewardButtonEnabled: Bool
    /// リワード広告処理中かどうか（進捗インジケータ表示に利用）
    @Published private(set) var isRequestingReward: Bool
    /// ユーザーへ提示するアラート
    @Published var alertState: AlertState?

    /// - Parameters:
    ///   - attemptStore: 日替わり挑戦回数を管理するストア
    ///   - definitionService: 日替わりモード定義を提供するサービス
    ///   - adsService: 広告表示サービス
    ///   - gameCenterService: Game Center 連携サービス
    ///   - nowProvider: 現在日時を取得するクロージャ（省略時は `Date()`）
    ///   - locale: 表示に利用するロケール（デフォルトで日本語環境を想定）
    init(
        attemptStore: AnyDailyChallengeAttemptStore,
        definitionService: DailyChallengeDefinitionProviding,
        adsService: AdsServiceProtocol,
        gameCenterService: GameCenterServiceProtocol,
        nowProvider: @escaping () -> Date = { Date() },
        locale: Locale = Locale(identifier: "ja_JP")
    ) {
        self.attemptStore = attemptStore
        self.definitionService = definitionService
        self.adsService = adsService
        self.gameCenterService = gameCenterService
        self.nowProvider = nowProvider

        // 表示用フォーマッタを準備
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.calendar?.timeZone = TimeZone.current
        dateFormatter.setLocalizedDateFormatFromTemplate("yMMMMdEEE")
        self.dateFormatter = dateFormatter

        let resetFormatter = DateFormatter()
        resetFormatter.locale = locale
        resetFormatter.calendar = Calendar(identifier: .gregorian)
        resetFormatter.calendar?.timeZone = TimeZone.current
        resetFormatter.setLocalizedDateFormatFromTemplate("MdEEE HH:mm")
        self.resetFormatter = resetFormatter

        // 現在日付のチャレンジ情報を取得
        let bundle = definitionService.challengeBundle(for: nowProvider())
        self.challengeBundle = bundle
        self.challengeDateText = Self.makeDateText(for: bundle.date, formatter: dateFormatter)
        self.resetTimeText = Self.makeResetText(bundle: bundle, formatter: resetFormatter, service: definitionService)
        self.remainingAttemptsText = ""
        self.rewardProgressText = ""
        self.isStartButtonEnabled = false
        self.isRewardButtonEnabled = false
        self.isRequestingReward = false

        // 初期状態でストアの日付を同期し、翌日跨ぎに備える
        attemptStore.refreshForCurrentDate()
        // ストア側の Published 値を UI へ反映
        updateAttemptRelatedTexts()

        // ストアの変更を購読し、UI へ即時反映させる
        cancellable = attemptStore.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateAttemptRelatedTexts()
            }
        }
    }

    /// 画面表示時に呼び出し、日付変化や最新レギュレーションを再評価する
    func handleAppear() {
        refreshChallengeInfoIfNeeded()
    }

    /// ランキング表示ボタン押下時に呼び出し、Game Center のリーダーボードを提示する
    /// - Parameter variant: どちらのステージを開くか
    func presentLeaderboard(for variant: DailyChallengeDefinition.Variant) {
        let info = challengeBundle.info(for: variant)
        gameCenterService.showLeaderboard(for: info.leaderboardIdentifier)
    }

    /// 挑戦開始ボタン押下時の処理
    /// - Returns: ゲーム開始に利用する `GameMode`。挑戦不可の場合は `nil`。
    /// - Parameter variant: 固定版かランダム版か
    func startChallengeIfPossible(for variant: DailyChallengeDefinition.Variant) -> GameMode? {
        attemptStore.refreshForCurrentDate()
        guard attemptStore.consumeAttempt() else {
            alertState = AlertState(title: "挑戦できません", message: "本日の挑戦回数を使い切りました。")
            updateAttemptRelatedTexts()
            return nil
        }
        updateAttemptRelatedTexts()
        return challengeBundle.info(for: variant).mode
    }

    /// リワード広告視聴をリクエストし、成功時に挑戦回数を追加する
    func requestRewardedAttempt() async {
        attemptStore.refreshForCurrentDate()

        if attemptStore.isDebugUnlimitedEnabled {
            // デバッグ無制限モードでは広告視聴が不要であることを明示する
            alertState = AlertState(title: "デバッグモード", message: "無制限モードが有効なため広告視聴は不要です。")
            updateAttemptRelatedTexts()
            return
        }

        guard attemptStore.rewardedAttemptsGranted < attemptStore.maximumRewardedAttempts else {
            alertState = AlertState(title: "追加不可", message: "広告で追加できる回数の上限に達しています。")
            updateAttemptRelatedTexts()
            return
        }

        guard !isRequestingReward else { return }
        isRequestingReward = true
        updateAttemptRelatedTexts()

        let success = await adsService.showRewardedAd()
        if success {
            let granted = attemptStore.grantRewardedAttempt()
            if !granted {
                alertState = AlertState(title: "付与できません", message: "内部状態が更新できなかったため、挑戦回数は増加しませんでした。")
            }
        } else {
            alertState = AlertState(title: "広告を確認してください", message: "広告視聴が完了しなかったため挑戦回数は追加されませんでした。")
        }

        updateAttemptRelatedTexts()
        isRequestingReward = false
        updateAttemptRelatedTexts()
    }

    /// チャレンジ情報が日付越えで変化していないか確認し、必要に応じて最新化する
    private func refreshChallengeInfoIfNeeded() {
        let currentDate = nowProvider()
        let latestBundle = definitionService.challengeBundle(for: currentDate)
        // `DailyChallengeDefinition.seed(for:)` は同日であれば一定なので、基準シードの変化で日付越えを検出する
        guard latestBundle.baseSeed != challengeBundle.baseSeed else {
            return
        }

        challengeBundle = latestBundle
        challengeDateText = Self.makeDateText(for: latestBundle.date, formatter: dateFormatter)
        resetTimeText = Self.makeResetText(bundle: latestBundle, formatter: resetFormatter, service: definitionService)
    }

    /// 残量テキストやボタン有効状態をストアから再計算する
    private func updateAttemptRelatedTexts() {
        if attemptStore.isDebugUnlimitedEnabled {
            // 無制限モード時は残量文言とボタン状態を専用表示へ切り替える
            remainingAttemptsText = "デバッグモード: 無制限"
            rewardProgressText = "広告視聴は不要です（デバッグモード）"
            isStartButtonEnabled = true
            isRewardButtonEnabled = false
            return
        }

        let remaining = attemptStore.remainingAttempts
        let granted = attemptStore.rewardedAttemptsGranted
        let maximumRewarded = attemptStore.maximumRewardedAttempts
        let totalMax = 1 + maximumRewarded

        remainingAttemptsText = "残り \(remaining) 回 / 最大 \(totalMax) 回"
        rewardProgressText = "広告追加済み: \(granted) / \(maximumRewarded)"
        isStartButtonEnabled = remaining > 0
        isRewardButtonEnabled = granted < maximumRewarded && !isRequestingReward
    }

    /// 日付表示テキストを生成する
    private static func makeDateText(for date: Date, formatter: DateFormatter) -> String {
        formatter.string(from: date)
    }

    /// リセット案内テキストを生成する
    private static func makeResetText(
        bundle: DailyChallengeDefinitionService.ChallengeBundle,
        formatter: DateFormatter,
        service: DailyChallengeDefinitionProviding
    ) -> String {
        let resetDateUTC = service.nextResetDate(after: bundle.date)
        return "リセット: \(formatter.string(from: resetDateUTC))"
    }

    /// ステージ情報を順序付き配列で取得するヘルパー
    var orderedStageInfos: [DailyChallengeDefinitionService.ChallengeInfo] {
        challengeBundle.orderedInfos
    }
}

// MARK: - 日替わりチャレンジ画面
/// 日替わりチャレンジの概要と操作ボタンを表示する SwiftUI ビュー
struct DailyChallengeView: View {
    /// ビューモデル（StateObject でライフサイクルを安定化）
    @StateObject private var viewModel: DailyChallengeViewModel
    /// 親へ戻るためのクロージャ
    let onDismiss: () -> Void
    /// ゲーム開始を依頼するクロージャ
    let onStart: (GameMode) -> Void
    /// 共通テーマ（配色・背景を統一する）
    private let theme = AppTheme()

    /// - Parameters:
    ///   - viewModel: 依存を注入済みのビューモデル
    ///   - onDismiss: 閉じる操作時に実行する処理
    ///   - onStart: ゲーム開始要求を親へ伝える処理
    init(
        viewModel: DailyChallengeViewModel,
        onDismiss: @escaping () -> Void,
        onStart: @escaping (GameMode) -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onDismiss = onDismiss
        self.onStart = onStart
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                headerSection
                stageCardsSection
                attemptsSection
                rewardButtonSection
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("デイリーチャレンジ")
        .navigationBarTitleDisplayMode(.inline)
        // システム標準の戻る矢印は非表示にし、専用の戻るボタンへ誘導する
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    // 戻る操作を親ビューへ伝達し、タイトル画面へ戻る
                    onDismiss()
                } label: {
                    Label("戻る", systemImage: "chevron.backward")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                }
                .accessibilityIdentifier("daily_challenge_back_button")
            }
        }
        .onAppear {
            viewModel.handleAppear()
        }
        .alert(item: $viewModel.alertState) { state in
            Alert(title: Text(state.title), message: Text(state.message), dismissButton: .default(Text("OK")))
        }
        .overlay(alignment: .center) {
            if viewModel.isRequestingReward {
                ProgressView("広告を確認しています…")
                    .progressViewStyle(.circular)
                    .padding(24)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.black.opacity(0.65))
                    )
                    .foregroundStyle(Color.white)
                    .accessibilityIdentifier("daily_challenge_reward_progress")
            }
        }
        .accessibilityIdentifier("daily_challenge_view")
    }

    /// 日付とバリアント概要
    private var headerSection: some View {
        let variantNames = viewModel.orderedStageInfos.map { $0.variantDisplayName }.joined(separator: " / ")
        let modeNames = viewModel.orderedStageInfos.map { $0.mode.displayName }.joined(separator: " / ")

        return VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.challengeDateText)
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .accessibilityIdentifier("daily_challenge_date_label")

            Text("公開バリアント: \(variantNames)")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(theme.textSecondary)

            Text("モード名: \(modeNames)")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(theme.textSecondary.opacity(0.85))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.challengeDateText)、公開バリアントは \(variantNames)、モード名は \(modeNames) です")
    }

    /// 固定・ランダムそれぞれのカードを縦並びで表示するセクション
    private var stageCardsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(viewModel.orderedStageInfos, id: \.identifierSuffix) { info in
                stageCard(for: info)
            }
        }
    }

    /// 単一ステージのカード表示
    /// - Parameter info: 対応するチャレンジ情報
    private func stageCard(for info: DailyChallengeDefinitionService.ChallengeInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(info.variantDisplayName)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textPrimary)

                Text(info.mode.displayName)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.accentPrimary)

                Text(info.regulationPrimaryText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(theme.textSecondary)

                Text(info.regulationSecondaryText)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(theme.textSecondary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button {
                    viewModel.presentLeaderboard(for: info.variant)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "trophy")
                        Text("ランキング")
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.accentPrimary)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(theme.accentPrimary, lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("daily_challenge_leaderboard_button_\(info.identifierSuffix)")

                Button {
                    if let mode = viewModel.startChallengeIfPossible(for: info.variant) {
                        onStart(mode)
                    }
                } label: {
                    Text("挑戦する")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(Color.white)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(viewModel.isStartButtonEnabled ? theme.accentPrimary : theme.accentPrimary.opacity(0.45))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isStartButtonEnabled)
                .accessibilityIdentifier("daily_challenge_start_button_\(info.identifierSuffix)")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.backgroundElevated.opacity(0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(theme.statisticBadgeBorder.opacity(0.6), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("daily_challenge_stage_card_\(info.identifierSuffix)")
        .accessibilityLabel("\(info.variantDisplayName)。モードは \(info.mode.displayName)。\(info.regulationPrimaryText)。\(info.regulationSecondaryText)")
    }

    /// 挑戦回数とリセット時刻の表示
    private var attemptsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.remainingAttemptsText)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .accessibilityIdentifier("daily_challenge_remaining_label")

            Text(viewModel.rewardProgressText)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(theme.textSecondary)
                .accessibilityIdentifier("daily_challenge_reward_status")

            Text(viewModel.resetTimeText)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(theme.textSecondary.opacity(0.85))
                .accessibilityIdentifier("daily_challenge_reset_label")
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.backgroundElevated.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.statisticBadgeBorder.opacity(0.5), lineWidth: 1)
        )
    }

    /// 広告視聴による挑戦回数追加ボタン
    private var rewardButtonSection: some View {
        Button {
            Task { await viewModel.requestRewardedAttempt() }
        } label: {
            HStack {
                Image(systemName: "gift.fill")
                Text("広告を視聴して回数を追加")
            }
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundColor(Color.white.opacity(viewModel.isRewardButtonEnabled ? 1 : 0.6))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.accentPrimary.opacity(viewModel.isRewardButtonEnabled ? 0.85 : 0.45))
            )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isRewardButtonEnabled)
        .accessibilityIdentifier("daily_challenge_reward_button")
    }
}

#Preview {
    // プレビュー用の簡易依存（永続化を使わずメモリ上で試す）
    let previewStore = DailyChallengeAttemptStore(userDefaults: UserDefaults(suiteName: "preview_daily") ?? .standard)
    let anyStore = AnyDailyChallengeAttemptStore(base: previewStore)
    let definitionService = DailyChallengeDefinitionService()
    let viewModel = DailyChallengeViewModel(
        attemptStore: anyStore,
        definitionService: definitionService,
        adsService: AdsService.shared,
        gameCenterService: GameCenterService.shared
    )
    return NavigationStack {
        DailyChallengeView(
            viewModel: viewModel,
            onDismiss: {},
            onStart: { _ in }
        )
    }
}
