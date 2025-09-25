import Testing
import AppTrackingTransparency
import UserMessagingPlatform
@testable import MonoKnightApp

// MARK: - テスト本体
struct AdsConsentCoordinatorTests {
    /// requestConsentIfNeeded が必須同意の際にフォームを表示し、最終的に NPA フラグが false へ戻ることを検証
    @MainActor
    @Test func requestConsentIfNeeded_showsFormWhenRequired() async throws {
        UserDefaults.standard.removeObject(forKey: "ads_should_use_npa")

        let environment = TestAdsConsentEnvironment()
        environment.consentStatus = .required
        environment.formStatus = .available
        environment.canRequestAds = false
        environment.requestUpdateHandler = {
            environment.canRequestAds = true
        }
        environment.presenterFactory = {
            return { _, completion in
                environment.consentStatus = .obtained
                environment.canRequestAds = true
                completion(nil)
            }
        }

        let presenter = TestConsentPresentationDelegate()
        let stateDelegate = TestConsentStateRecorder()
        let coordinator = AdsConsentCoordinator(
            hasValidAdConfiguration: true,
            environment: environment,
            trackingAuthorizationStatusProvider: { .authorized }
        )
        coordinator.presentationDelegate = presenter
        coordinator.stateDelegate = stateDelegate

        await coordinator.requestConsentIfNeeded()

        #expect(environment.requestUpdateCallCount == 1)
        #expect(environment.loadFormCallCount == 1)
        #expect(presenter.presentConsentFormCallCount == 1)
        #expect(stateDelegate.recordedStates.count >= 2)

        if let last = stateDelegate.recordedStates.last {
            #expect(last.state.shouldUseNPA == false)
            #expect(last.state.canRequestAds == true)
        }
        #expect(UserDefaults.standard.bool(forKey: "ads_should_use_npa") == false)
    }

    /// refreshConsentStatus がプライバシーオプション表示を要求することを確認
    @MainActor
    @Test func refreshConsentStatus_showsPrivacyOptions() async throws {
        UserDefaults.standard.removeObject(forKey: "ads_should_use_npa")

        let environment = TestAdsConsentEnvironment()
        environment.consentStatus = .obtained
        environment.formStatus = .available
        environment.canRequestAds = true
        environment.privacyPresenterFactory = {
            return { _, completion in
                environment.consentStatus = .required
                environment.canRequestAds = false
                completion(nil)
            }
        }

        let presenter = TestConsentPresentationDelegate()
        let stateDelegate = TestConsentStateRecorder()
        let coordinator = AdsConsentCoordinator(
            hasValidAdConfiguration: true,
            environment: environment,
            trackingAuthorizationStatusProvider: { .authorized }
        )
        coordinator.presentationDelegate = presenter
        coordinator.stateDelegate = stateDelegate

        await coordinator.refreshConsentStatus()

        #expect(environment.requestUpdateCallCount == 1)
        #expect(environment.makePrivacyOptionsCallCount == 1)
        #expect(presenter.presentPrivacyOptionsCallCount == 1)
        #expect(!stateDelegate.recordedStates.isEmpty)
    }

    /// Info.plist の設定が不完全な場合、環境側の処理が呼ばれないことを保証
    @MainActor
    @Test func coordinator_skipsOperations_whenConfigurationIsInvalid() async throws {
        let environment = TestAdsConsentEnvironment()
        let presenter = TestConsentPresentationDelegate()
        let stateDelegate = TestConsentStateRecorder()
        let coordinator = AdsConsentCoordinator(
            hasValidAdConfiguration: false,
            environment: environment,
            trackingAuthorizationStatusProvider: { .authorized }
        )
        coordinator.presentationDelegate = presenter
        coordinator.stateDelegate = stateDelegate

        await coordinator.requestConsentIfNeeded()
        await coordinator.refreshConsentStatus()
        await coordinator.synchronizeOnLaunch()

        #expect(environment.requestUpdateCallCount == 0)
        #expect(environment.loadFormCallCount == 0)
        #expect(environment.makePrivacyOptionsCallCount == 0)
        #expect(presenter.presentConsentFormCallCount == 0)
        #expect(presenter.presentPrivacyOptionsCallCount == 0)
        #expect(stateDelegate.recordedStates.isEmpty)
    }

    /// ATT が拒否されている場合は UMP が obtained でも NPA を維持する
    @MainActor
    @Test func coordinator_forcesNPA_whenTrackingDenied() async throws {
        UserDefaults.standard.removeObject(forKey: "ads_should_use_npa")

        let environment = TestAdsConsentEnvironment()
        environment.consentStatus = .obtained
        environment.formStatus = .available
        environment.canRequestAds = true

        let stateDelegate = TestConsentStateRecorder()
        let coordinator = AdsConsentCoordinator(
            hasValidAdConfiguration: true,
            environment: environment,
            trackingAuthorizationStatusProvider: { .denied }
        )
        coordinator.stateDelegate = stateDelegate

        await coordinator.requestConsentIfNeeded()

        #expect(stateDelegate.recordedStates.last?.state.shouldUseNPA == true)
        #expect(coordinator.currentState.shouldUseNPA == true)
        #expect(UserDefaults.standard.bool(forKey: "ads_should_use_npa") == true)
    }

    /// UMP 管理画面でフォームが未設定の場合でも NPA=1 で広告リクエストを許可するフォールバックが動作するか検証
    @MainActor
    @Test func coordinator_fallsBackWhenConsentFormMissing() async throws {
        UserDefaults.standard.removeObject(forKey: "ads_should_use_npa")

        let environment = TestAdsConsentEnvironment()
        environment.requestUpdateError = NSError(
            domain: "com.google.user_messaging_platform",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "No form configured"]
        )

        let presenter = TestConsentPresentationDelegate()
        let stateDelegate = TestConsentStateRecorder()
        let coordinator = AdsConsentCoordinator(
            hasValidAdConfiguration: true,
            environment: environment,
            trackingAuthorizationStatusProvider: { .authorized }
        )
        coordinator.presentationDelegate = presenter
        coordinator.stateDelegate = stateDelegate

        await coordinator.synchronizeOnLaunch()

        #expect(environment.requestUpdateCallCount == 1)
        #expect(presenter.presentConsentFormCallCount == 0)
        #expect(stateDelegate.recordedStates.last?.state.shouldUseNPA == true)
        #expect(stateDelegate.recordedStates.last?.state.canRequestAds == true)
        #expect(UserDefaults.standard.bool(forKey: "ads_should_use_npa") == true)

        let callCountAfterSync = environment.requestUpdateCallCount
        await coordinator.requestConsentIfNeeded()
        #expect(environment.requestUpdateCallCount == callCountAfterSync)
        #expect(presenter.presentConsentFormCallCount == 0)
        #expect(coordinator.currentState.shouldUseNPA == true)
        #expect(coordinator.currentState.canRequestAds == true)
    }

    /// ATT の許諾状態が後から authorized へ変化した場合に NPA フラグが解除されるか検証
    @MainActor
    @Test func coordinator_updatesNPAAfterTrackingAuthorizationGranted() async throws {
        UserDefaults.standard.removeObject(forKey: "ads_should_use_npa")

        let environment = TestAdsConsentEnvironment()
        environment.consentStatus = .obtained
        environment.formStatus = .available
        environment.canRequestAds = true
        environment.requestUpdateHandler = {
            // --- requestConsentInfoUpdate 呼び出し時に canRequestAds を true へ調整して広告ロード可能状態を模倣 ---
            environment.canRequestAds = true
        }

        var attStatus: ATTrackingManager.AuthorizationStatus = .denied
        let stateDelegate = TestConsentStateRecorder()
        let coordinator = AdsConsentCoordinator(
            hasValidAdConfiguration: true,
            environment: environment,
            trackingAuthorizationStatusProvider: { attStatus }
        )
        coordinator.stateDelegate = stateDelegate

        await coordinator.requestConsentIfNeeded()
        #expect(stateDelegate.recordedStates.last?.state.shouldUseNPA == true)
        #expect(UserDefaults.standard.bool(forKey: "ads_should_use_npa") == true)

        // --- ユーザーが後から ATT を許可したシナリオを再現 ---
        attStatus = .authorized
        await coordinator.refreshConsentStatus()

        #expect(stateDelegate.recordedStates.last?.state.shouldUseNPA == false)
        #expect(stateDelegate.recordedStates.last?.shouldReload == true)
        #expect(UserDefaults.standard.bool(forKey: "ads_should_use_npa") == false)
    }
}
