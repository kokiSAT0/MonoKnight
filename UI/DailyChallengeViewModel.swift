import Combine
import Game
import SwiftUI

@MainActor
final class DailyChallengeViewModel: ObservableObject {
    struct AlertState: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

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

        static func identifier(for variant: DailyChallengeDefinition.Variant) -> String {
            switch variant {
            case .fixed:
                return "fixed"
            case .random:
                return "random"
            }
        }

        var remainingText: String {
            if isDebugUnlimited {
                return "\(variantDisplayName): デバッグモード（無制限）"
            } else {
                return "\(variantDisplayName): 残り \(remaining) 回 / 最大 \(totalMaximum) 回"
            }
        }

        var rewardProgressText: String {
            if isDebugUnlimited {
                return "広告視聴は不要です（デバッグモード）"
            } else {
                return "広告追加 \(rewardedGranted) / \(maximumRewarded)"
            }
        }

        var isStartButtonEnabled: Bool {
            isDebugUnlimited || remaining > 0
        }

        var isRewardButtonEnabled: Bool {
            guard !isDebugUnlimited else { return false }
            return rewardedGranted < maximumRewarded && !isRequestingReward
        }
    }

    private let attemptStore: AnyDailyChallengeAttemptStore
    private let definitionService: DailyChallengeDefinitionProviding
    private let adsService: AdsServiceProtocol
    private let gameCenterService: GameCenterServiceProtocol
    private let nowProvider: () -> Date
    private let dateFormatter: DateFormatter
    private let resetFormatter: DateFormatter
    private var cancellable: AnyCancellable?
    private var requestingVariant: DailyChallengeDefinition.Variant?

    @Published private(set) var challengeBundle: DailyChallengeDefinitionService.ChallengeBundle
    @Published private(set) var challengeDateText: String
    @Published private(set) var resetTimeText: String
    @Published private(set) var variantAttemptStatuses: [VariantAttemptStatus]
    @Published private(set) var rewardProgressMessage: String?
    @Published var alertState: AlertState?

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

        let bundle = definitionService.challengeBundle(for: nowProvider())
        self.challengeBundle = bundle
        self.challengeDateText = Self.makeDateText(for: bundle.date, formatter: dateFormatter)
        self.resetTimeText = Self.makeResetText(bundle: bundle, formatter: resetFormatter, service: definitionService)
        self.variantAttemptStatuses = []
        self.rewardProgressMessage = nil
        self.requestingVariant = nil

        attemptStore.refreshForCurrentDate()
        updateAttemptRelatedTexts()

        cancellable = attemptStore.objectWillChange.sink { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateAttemptRelatedTexts()
            }
        }
    }

    func handleAppear() {
        refreshChallengeInfoIfNeeded()
    }

    func presentLeaderboard(for variant: DailyChallengeDefinition.Variant) {
        let info = challengeBundle.info(for: variant)
        gameCenterService.showLeaderboard(for: info.leaderboardIdentifier)
    }

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

    var orderedStageInfos: [DailyChallengeDefinitionService.ChallengeInfo] {
        challengeBundle.orderedInfos
    }

    func status(for variant: DailyChallengeDefinition.Variant) -> VariantAttemptStatus? {
        let identifier = VariantAttemptStatus.identifier(for: variant)
        return variantAttemptStatuses.first { $0.identifierSuffix == identifier }
    }

    var headerPresentation: DailyChallengeHeaderPresentation {
        DailyChallengeHeaderPresentation(
            challengeDateText: challengeDateText,
            variantNames: orderedStageInfos.map(\.variantDisplayName).joined(separator: " / "),
            modeNames: orderedStageInfos.map { $0.mode.displayName }.joined(separator: " / ")
        )
    }

    func cardPresentation(for info: DailyChallengeDefinitionService.ChallengeInfo) -> DailyChallengeCardPresentation {
        DailyChallengeCardPresentation(
            info: info,
            status: status(for: info.variant)
        )
    }

    private func refreshChallengeInfoIfNeeded() {
        let currentDate = nowProvider()
        let latestBundle = definitionService.challengeBundle(for: currentDate)
        guard latestBundle.baseSeed != challengeBundle.baseSeed else {
            return
        }

        challengeBundle = latestBundle
        challengeDateText = Self.makeDateText(for: latestBundle.date, formatter: dateFormatter)
        resetTimeText = Self.makeResetText(bundle: latestBundle, formatter: resetFormatter, service: definitionService)
        updateAttemptRelatedTexts()
    }

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

    private static func makeDateText(for date: Date, formatter: DateFormatter) -> String {
        formatter.string(from: date)
    }

    private static func makeResetText(
        bundle: DailyChallengeDefinitionService.ChallengeBundle,
        formatter: DateFormatter,
        service: DailyChallengeDefinitionProviding
    ) -> String {
        let resetDateUTC = service.nextResetDate(after: bundle.date)
        return "リセット: \(formatter.string(from: resetDateUTC))"
    }
}
