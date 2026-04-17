import Game
import SwiftUI

/// 日替わりチャレンジの概要と操作ボタンを表示する SwiftUI ビュー
struct DailyChallengeView: View {
    @StateObject private var viewModel: DailyChallengeViewModel
    let onDismiss: () -> Void
    let onStart: (GameMode) -> Void
    private let theme = AppTheme()

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
                DailyChallengeHeaderSection(
                    presentation: viewModel.headerPresentation,
                    theme: theme
                )
                stageCardsSection
                DailyChallengeAttemptsSection(
                    statuses: viewModel.variantAttemptStatuses,
                    resetTimeText: viewModel.resetTimeText,
                    theme: theme
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("デイリーチャレンジ")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
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

    private var stageCardsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(viewModel.orderedStageInfos, id: \.identifierSuffix) { info in
                DailyChallengeStageCard(
                    presentation: viewModel.cardPresentation(for: info),
                    theme: theme,
                    onShowLeaderboard: {
                        viewModel.presentLeaderboard(for: info.variant)
                    },
                    onStart: {
                        if let mode = viewModel.startChallengeIfPossible(for: info.variant) {
                            onStart(mode)
                        }
                    },
                    onRequestReward: {
                        Task { await viewModel.requestRewardedAttempt(for: info.variant) }
                    }
                )
            }
        }
    }
}

#Preview {
    let previewStore = DailyChallengeAttemptStore(userDefaults: UserDefaults(suiteName: "preview_daily") ?? .standard)
    let anyStore = AnyDailyChallengeAttemptStore(base: previewStore)
    let definitionService = DailyChallengeDefinitionService()
    let viewModel = DailyChallengeViewModel(
        attemptStore: anyStore,
        definitionService: definitionService,
        adsService: AdsService.shared,
        gameCenterService: GameCenterService.shared
    )
    NavigationStack {
        DailyChallengeView(
            viewModel: viewModel,
            onDismiss: {},
            onStart: { _ in }
        )
    }
}
