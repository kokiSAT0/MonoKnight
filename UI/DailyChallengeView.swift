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

    /// バリアント単位での挑戦状況を UI へ提供するステータス
    struct VariantAttemptStatus: Identifiable {
        let variant: DailyChallengeDefinition.Variant
        let variantDisplayName: String
        let remaining: Int
        let totalMaximum: Int
        let rewardedGranted: Int
        let maximumRewarded: Int
        let isDebugUnlimited: Bool
        let isRequestingReward: Bool

        var id: String { identifierSuffix }

        var identifierSuffix: String {
            Self.identifier(for: variant)
        }

        /// バリアントごとの識別子を生成する
        /// - Parameter variant: 固定/ランダムの別
        /// - Returns: ビューの識別子として利用する文字列
        static func identifier(for variant: DailyChallengeDefinition.Variant) -> String {
            switch variant {
            case .fixed:
                return "fixed"
            case .random:
                return "random"
            }
        }

        /// 残量を説明するテキスト
        var remainingText: String {
            if isDebugUnlimited {
                return "\(variantDisplayName): デバッグモード（無制限）"
            } else {
                return "\(variantDisplayName): 残り \(remaining) 回 / 最大 \(totalMaximum) 回"
            }
        }

        /// 広告付与進捗を説明するテキスト
        var rewardProgressText: String {
            if isDebugUnlimited {
                return "広告視聴は不要です（デバッグモード）"
            } else {
                return "広告追加 \(rewardedGranted) / \(maximumRewarded)"
            }
        }

        /// 挑戦ボタンを有効化できるか
        var isStartButtonEnabled: Bool {
            isDebugUnlimited || remaining > 0
        }

        /// 広告ボタンを有効化できるか
        var isRewardButtonEnabled: Bool {
            guard !isDebugUnlimited else { return false }
            return rewardedGranted < maximumRewarded && !isRequestingReward
        }
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
    /// 広告リクエスト中のバリアント。`nil` であればリクエストは発生していない。
    private var requestingVariant: DailyChallengeDefinition.Variant?

    /// 現在表示しているチャレンジ情報バンドル
    @Published private(set) var challengeBundle: DailyChallengeDefinitionService.ChallengeBundle
    /// 「2025年5月26日 (月)」のような日付表示用テキスト
    @Published private(set) var challengeDateText: String
    /// 「リセット: 05/27(火) 09:00」のようなリセット案内テキスト
    @Published private(set) var resetTimeText: String
    /// バリアントごとの挑戦状況まとめ
    @Published private(set) var variantAttemptStatuses: [VariantAttemptStatus]
    /// 広告進捗表示用メッセージ（nil の場合は非表示）
    @Published private(set) var rewardProgressMessage: String?
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
        self.variantAttemptStatuses = []
        self.rewardProgressMessage = nil
        self.requestingVariant = nil

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
        guard attemptStore.consumeAttempt(for: variant) else {
            let variantName = challengeBundle.info(for: variant).variantDisplayName
            alertState = AlertState(title: "挑戦できません", message: "\(variantName)の挑戦回数を使い切りました。")
            updateAttemptRelatedTexts()
            return nil
        }
        updateAttemptRelatedTexts()
        return challengeBundle.info(for: variant).mode
    }

    /// リワード広告視聴をリクエストし、成功時に指定バリアントの挑戦回数を追加する
    /// - Parameter variant: 広告付与対象となるバリアント
    func requestRewardedAttempt(for variant: DailyChallengeDefinition.Variant) async {
        attemptStore.refreshForCurrentDate()

        if attemptStore.isDebugUnlimitedEnabled {
            let variantName = challengeBundle.info(for: variant).variantDisplayName
            alertState = AlertState(title: "デバッグモード", message: "\(variantName)では無制限モードが有効なため広告視聴は不要です。")
            updateAttemptRelatedTexts()
            return
        }

        let granted = attemptStore.rewardedAttemptsGranted(for: variant)
        if granted >= attemptStore.maximumRewardedAttempts {
            let variantName = challengeBundle.info(for: variant).variantDisplayName
            alertState = AlertState(title: "追加不可", message: "\(variantName)では広告で追加できる回数の上限に達しています。")
            updateAttemptRelatedTexts()
            return
        }

        guard requestingVariant == nil else { return }
        requestingVariant = variant
        updateAttemptRelatedTexts()

        let success = await adsService.showRewardedAd()
        if success {
            let grantedSuccess = attemptStore.grantRewardedAttempt(for: variant)
            if !grantedSuccess {
                alertState = AlertState(title: "付与できません", message: "内部状態が更新できなかったため、挑戦回数は増加しませんでした。")
            }
        } else {
            alertState = AlertState(title: "広告を確認してください", message: "広告視聴が完了しなかったため挑戦回数は追加されませんでした。")
        }

        requestingVariant = nil
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
        updateAttemptRelatedTexts()
    }

    /// 残量テキストやボタン有効状態をストアから再計算する
    private func updateAttemptRelatedTexts() {
        let isUnlimited = attemptStore.isDebugUnlimitedEnabled
        let maximumRewarded = attemptStore.maximumRewardedAttempts
        let totalMaximum = 1 + maximumRewarded

        variantAttemptStatuses = challengeBundle.orderedInfos.map { info in
            VariantAttemptStatus(
                variant: info.variant,
                variantDisplayName: info.variantDisplayName,
                remaining: attemptStore.remainingAttempts(for: info.variant),
                totalMaximum: totalMaximum,
                rewardedGranted: attemptStore.rewardedAttemptsGranted(for: info.variant),
                maximumRewarded: maximumRewarded,
                isDebugUnlimited: isUnlimited,
                isRequestingReward: requestingVariant == info.variant
            )
        }

        if let requestingVariant {
            let variantName = challengeBundle.info(for: requestingVariant).variantDisplayName
            rewardProgressMessage = "\(variantName)向けの広告を確認しています…"
        } else {
            rewardProgressMessage = nil
        }
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

    /// 指定バリアントに対応するステータスを検索する
    /// - Parameter variant: 固定/ランダムの別
    /// - Returns: ビュー描画に必要な挑戦状況。該当しない場合は `nil`。
    func status(for variant: DailyChallengeDefinition.Variant) -> VariantAttemptStatus? {
        let identifier = VariantAttemptStatus.identifier(for: variant)
        return variantAttemptStatuses.first { $0.identifierSuffix == identifier }
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
            if let message = viewModel.rewardProgressMessage {
                ProgressView(message)
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
        let status = viewModel.status(for: info.variant)

        return VStack(alignment: .leading, spacing: 16) {
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

            if let status {
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.remainingText)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)

                    Text(status.rewardProgressText)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                }
                .accessibilityIdentifier("daily_challenge_status_\(status.identifierSuffix)")
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
                                .fill((status?.isStartButtonEnabled ?? false) ? theme.accentPrimary : theme.accentPrimary.opacity(0.45))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!(status?.isStartButtonEnabled ?? false))
                .accessibilityIdentifier("daily_challenge_start_button_\(info.identifierSuffix)")
            }

            if let status {
                Button {
                    Task { await viewModel.requestRewardedAttempt(for: info.variant) }
                } label: {
                    HStack {
                        Image(systemName: "gift.fill")
                        Text("広告を視聴して回数を追加")
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(status.isRewardButtonEnabled ? 1 : 0.65))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(theme.accentPrimary.opacity(status.isRewardButtonEnabled ? 0.85 : 0.45))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!status.isRewardButtonEnabled)
                .accessibilityIdentifier("daily_challenge_reward_button_\(status.identifierSuffix)")
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
            ForEach(viewModel.variantAttemptStatuses) { status in
                VStack(alignment: .leading, spacing: 4) {
                    Text(status.remainingText)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)

                    Text(status.rewardProgressText)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                }
                .accessibilityIdentifier("daily_challenge_summary_\(status.identifierSuffix)")
            }

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
