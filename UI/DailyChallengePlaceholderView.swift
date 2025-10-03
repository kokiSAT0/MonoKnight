import SwiftUI
import Combine

/// デイリーチャレンジの詳細情報と挑戦開始導線をまとめた画面
/// - Important: これまでのプレースホルダーを置き換え、実際の挑戦回数管理・広告補充と連携させる。
struct DailyChallengeView: View {
    /// 画面全体で利用するテーマカラーセット
    private let theme = AppTheme()
    /// ビュー内部で状態を管理する ViewModel
    @StateObject private var viewModel: DailyChallengeViewModel
    /// ランキングボタン押下時の処理
    private let onOpenLeaderboard: (DailyChallengeDefinition) -> Void
    /// 挑戦開始が確定した際に親へ伝えるクロージャ
    private let onStart: (DailyChallengeDefinition) -> Void
    /// ナビゲーションを閉じる処理
    private let onDismiss: () -> Void
    /// NavigationStack からのポップを確実に行うための dismiss アクション
    @Environment(\.dismiss) private var dismiss
    /// iPad などでの幅調整に利用するサイズクラス
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// - Parameters:
    ///   - definition: 当日のチャレンジ定義
    ///   - attemptStore: 挑戦回数管理ストア
    ///   - adsService: 広告サービス
    ///   - shouldTriggerGameStart: 挑戦開始時に即座にゲームを起動するかどうか
    ///   - onStart: ゲーム開始処理を親へ伝搬するクロージャ
    ///   - onOpenLeaderboard: ランキング表示を要求するクロージャ
    ///   - onDismiss: 画面を閉じる際に呼び出すクロージャ
    init(definition: DailyChallengeDefinition,
         attemptStore: DailyChallengeAttemptStore,
         adsService: AdsServiceProtocol,
         shouldTriggerGameStart: Bool,
         onStart: @escaping (DailyChallengeDefinition) -> Void,
         onOpenLeaderboard: @escaping (DailyChallengeDefinition) -> Void,
         onDismiss: @escaping () -> Void) {
        self._viewModel = StateObject(
            wrappedValue: DailyChallengeViewModel(
                definition: definition,
                attemptStore: attemptStore,
                adsService: adsService,
                shouldTriggerGameStart: shouldTriggerGameStart
            )
        )
        self.onStart = onStart
        self.onOpenLeaderboard = onOpenLeaderboard
        self.onDismiss = onDismiss
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                headerSection
                regulationSection
                attemptsSection
                actionSection
                closeButton
            }
            .frame(maxWidth: contentMaxWidth, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("デイリーチャレンジ")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // 画面表示時に定義とストアの整合性を取る
            viewModel.refreshStateOnAppear()
        }
        .alert(item: $viewModel.activeAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK")) {
                    alert.onDismiss?()
                }
            )
        }
    }

    /// 日付と概要をまとめたヘッダー
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(viewModel.displayDateText)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textSecondary)
                .accessibilityIdentifier("daily_challenge_header_date")

            Text(viewModel.definition.regulationHeadline)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.leading)

            Text(viewModel.definition.regulationDetail)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.displayDateText)。\(viewModel.definition.regulationHeadline)。\(viewModel.definition.regulationDetail)")
    }

    /// レギュレーションの詳細をカード形式で表示
    private var regulationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("レギュレーションのポイント")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)

            ForEach(viewModel.definition.regulationNotes, id: \.self) { note in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(theme.accentPrimary)
                        .padding(.top, 6)
                    Text(note)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.backgroundElevated.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.statisticBadgeBorder.opacity(0.7), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("レギュレーションのポイント。\(viewModel.definition.regulationNotes.joined(separator: "。"))")
    }

    /// 残り挑戦回数とリセット情報をまとめたカード
    private var attemptsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("挑戦状況")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)

            HStack(alignment: .center, spacing: 16) {
                Text(viewModel.compactAttemptsText)
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.accentPrimary)
                    .accessibilityIdentifier("daily_challenge_attempts_value")

                VStack(alignment: .leading, spacing: 6) {
                    Text(viewModel.attemptStatusText)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Text(viewModel.attemptSupplementaryText)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(theme.textSecondary)
                    Text(viewModel.resetTimeText)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(theme.textSecondary.opacity(0.9))
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(theme.backgroundElevated.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(theme.statisticBadgeBorder.opacity(0.8), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(viewModel.attemptStatusText)。\(viewModel.resetTimeText)")
    }

    /// ランキング・挑戦開始・広告補充をまとめたアクションエリア
    private var actionSection: some View {
        VStack(spacing: 14) {
            Button {
                onOpenLeaderboard(viewModel.definition)
            } label: {
                Label("ランキングを表示", systemImage: "trophy")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(theme.backgroundElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(theme.accentPrimary.opacity(0.4), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("daily_challenge_leaderboard_button")

            Button {
                viewModel.handleStartButtonTapped(onStart: onStart)
            } label: {
                Text(viewModel.startButtonTitle)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(viewModel.isStartButtonEnabled ? theme.accentPrimary : theme.statisticBadgeBorder)
                    )
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isStartButtonEnabled)
            .accessibilityIdentifier("daily_challenge_start_button")
            .accessibilityHint("挑戦回数を 1 回消費してゲームを開始します")

            Button {
                viewModel.handleWatchAdButtonTapped()
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isProcessingReward {
                        ProgressView()
                            .progressViewStyle(.circular)
                    } else {
                        Image(systemName: "play.rectangle.on.rectangle")
                    }
                    Text(viewModel.rewardButtonTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(theme.backgroundElevated.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(theme.accentPrimary.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.isRewardButtonEnabled)
            .accessibilityIdentifier("daily_challenge_watch_ad_button")
            .accessibilityHint("広告視聴で挑戦回数を補充します")
        }
    }

    /// 画面を閉じるボタン
    private var closeButton: some View {
        Button {
            onDismiss()
            dismiss()
        } label: {
            Text("閉じる")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.backgroundElevated.opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(theme.statisticBadgeBorder.opacity(0.7), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .padding(.top, 12)
        .accessibilityIdentifier("daily_challenge_close_button")
    }

    /// iPad など横幅が広い環境で中央寄せするための最大幅
    private var contentMaxWidth: CGFloat? {
        horizontalSizeClass == .regular ? 520 : nil
    }
}

/// ユーザー操作を集約する ViewModel
@MainActor
final class DailyChallengeViewModel: ObservableObject {
    /// 表示対象の定義
    let definition: DailyChallengeDefinition
    /// 現在の残り挑戦回数
    @Published private(set) var remainingAttempts: Int
    /// 最大ストック数
    @Published private(set) var maximumAttempts: Int
    /// リワード広告処理中かどうか
    @Published private(set) var isProcessingReward: Bool = false
    /// 挑戦開始処理中かどうか
    @Published private(set) var isLaunchingChallenge: Bool = false
    /// アラート表示内容
    @Published var activeAlert: DailyChallengeAlertState?

    /// 回数管理ストア
    private let attemptStore: DailyChallengeAttemptStore
    /// 広告サービス
    private let adsService: AdsServiceProtocol
    /// UI テストなどでゲーム開始を抑止したい場合に使用するフラグ
    private let shouldTriggerGameStart: Bool
    /// 日付・時間表示に利用するカレンダー
    private let calendar: Calendar
    /// 表示ロケール
    private let locale: Locale
    /// 現在日時を取得するクロージャ（テスト用に差し替え可能）
    private let now: () -> Date
    /// Combine の購読を保持
    private var cancellables = Set<AnyCancellable>()

    init(definition: DailyChallengeDefinition,
         attemptStore: DailyChallengeAttemptStore,
         adsService: AdsServiceProtocol,
         shouldTriggerGameStart: Bool,
         now: @escaping () -> Date = Date.init,
         locale: Locale = Locale(identifier: "ja_JP")) {
        self.definition = definition
        self.attemptStore = attemptStore
        self.adsService = adsService
        self.shouldTriggerGameStart = shouldTriggerGameStart
        self.now = now
        self.locale = locale

        var calendar = Calendar(identifier: definition.calendarIdentifier)
        calendar.timeZone = definition.timeZone
        self.calendar = calendar

        attemptStore.synchronize(with: definition)
        self.remainingAttempts = attemptStore.remainingAttempts
        self.maximumAttempts = attemptStore.maximumAttempts

        attemptStore.$remainingAttempts
            .sink { [weak self] value in
                self?.remainingAttempts = value
            }
            .store(in: &cancellables)

        attemptStore.$maximumAttempts
            .sink { [weak self] value in
                self?.maximumAttempts = value
            }
            .store(in: &cancellables)
    }

    /// 画面表示のたびに定義とストアの同期を再確認する
    func refreshStateOnAppear() {
        let didReset = attemptStore.synchronize(with: definition)
        if didReset {
            activeAlert = DailyChallengeAlertState(
                title: "挑戦回数をリセットしました",
                message: "新しいデイリーチャレンジが開放されています。"
            )
        }
    }

    /// 開始ボタン押下時の処理
    /// - Parameter onStart: 親ビューへ開始要求を伝えるクロージャ
    func handleStartButtonTapped(onStart: (DailyChallengeDefinition) -> Void) {
        guard !isLaunchingChallenge else { return }
        guard attemptStore.consumeAttempt() else {
            activeAlert = DailyChallengeAlertState(
                title: "挑戦できません",
                message: "本日の挑戦回数を使い切っています。広告視聴で補充するか、リセットまでお待ちください。"
            )
            return
        }

        isLaunchingChallenge = true
        if shouldTriggerGameStart {
            onStart(definition)
        } else {
            isLaunchingChallenge = false
            activeAlert = DailyChallengeAlertState(
                title: "挑戦準備が完了しました",
                message: "テストモードのためゲーム開始はスキップしています。"
            )
        }
    }

    /// 広告視聴ボタン押下時の処理
    func handleWatchAdButtonTapped() {
        guard !isProcessingReward else { return }
        guard !attemptStore.isAtMaximumStock else {
            activeAlert = DailyChallengeAlertState(
                title: "上限に達しています",
                message: "これ以上ストックできません。挑戦を進めて消費してください。"
            )
            return
        }

        isProcessingReward = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let success = await adsService.presentRewardedAd(for: .dailyChallenge)
            if success {
                let granted = attemptStore.grantAdditionalAttempts(
                    amount: definition.adRewardAmount,
                    maximum: definition.maximumAttemptStock
                )
                if granted > 0 {
                    activeAlert = DailyChallengeAlertState(
                        title: "挑戦回数を補充しました",
                        message: "挑戦回数が +\(granted) 回復しました。"
                    )
                } else {
                    activeAlert = DailyChallengeAlertState(
                        title: "これ以上追加できません",
                        message: "すでに最大ストック数に到達しています。"
                    )
                }
            } else {
                activeAlert = DailyChallengeAlertState(
                    title: "広告を確認できませんでした",
                    message: "通信状況などにより報酬を獲得できませんでした。時間を置いて再試行してください。"
                )
            }
            isProcessingReward = false
        }
    }

    /// 日付表示文字列
    var displayDateText: String {
        definition.formattedDateText(calendar: calendar, locale: locale)
    }

    /// 残り回数の詳細文
    var attemptStatusText: String {
        definition.attemptStatusText(remainingAttempts: remainingAttempts)
    }

    /// コンパクトな回数表記
    var compactAttemptsText: String {
        definition.compactAttemptStatus(remainingAttempts: remainingAttempts)
    }

    /// 基本回数と最大ストックをまとめた説明
    var attemptSupplementaryText: String {
        "基本 \(definition.baseAttemptsPerDay) 回 ・ 上限 \(definition.maximumAttemptStock) 回"
    }

    /// 次回リセットの表示文
    var resetTimeText: String {
        definition.formattedNextResetText(after: now(), calendar: calendar, locale: locale)
    }

    /// 開始ボタンのラベル
    var startButtonTitle: String { "挑戦を開始" }

    /// 開始ボタンが有効かどうか
    var isStartButtonEnabled: Bool { remainingAttempts > 0 && !isLaunchingChallenge }

    /// 広告ボタンのラベル
    var rewardButtonTitle: String {
        "広告視聴で +\(definition.adRewardAmount) 回復"
    }

    /// 広告ボタンを押下可能かどうか
    var isRewardButtonEnabled: Bool { !isProcessingReward && !attemptStore.isAtMaximumStock }
}

/// アラート表示用の構造体
struct DailyChallengeAlertState: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var onDismiss: (() -> Void)?
}

#if DEBUG && canImport(UIKit)
#Preview {
    let definition = DailyChallengeDefinition.makeForToday()
    let store = DailyChallengeAttemptStore(initialDefinition: definition)
    return DailyChallengeView(
        definition: definition,
        attemptStore: store,
        adsService: MockAdsService(),
        shouldTriggerGameStart: false,
        onStart: { _ in },
        onOpenLeaderboard: { _ in },
        onDismiss: {}
    )
}
#endif
