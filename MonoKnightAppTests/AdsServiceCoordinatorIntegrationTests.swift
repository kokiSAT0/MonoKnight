import Testing
import GoogleMobileAds
import UserMessagingPlatform
import UIKit

@testable import MonoKnightApp

// MARK: - スタブ群
@MainActor
private final class StubAdsConsentCoordinator: AdsConsentCoordinating {
    var presentationDelegate: AdsConsentCoordinatorPresenting?
    var stateDelegate: AdsConsentCoordinatorStateDelegate?
    var currentState: AdsConsentState = AdsConsentState(shouldUseNPA: false, canRequestAds: false)

    private(set) var synchronizeCallCount: Int = 0
    private(set) var requestCallCount: Int = 0
    private(set) var refreshCallCount: Int = 0

    func synchronizeOnLaunch() async {
        synchronizeCallCount += 1
    }

    func requestConsentIfNeeded() async {
        requestCallCount += 1
    }

    func refreshConsentStatus() async {
        refreshCallCount += 1
    }
}

@MainActor
private final class StubInterstitialAdController: InterstitialAdControlling {
    var delegate: InterstitialAdControllerDelegate?
    var areAdsDisabled: Bool = false

    private(set) var beginInitialLoadCallCount: Int = 0
    private(set) var showCallCount: Int = 0
    private(set) var resetCallCount: Int = 0
    private(set) var disableCallCount: Int = 0
    private(set) var receivedConsentUpdates: [(AdsConsentState, Bool)] = []
    private(set) var removeAdsProvider: (() -> Bool)?

    func beginInitialLoad() {
        beginInitialLoadCallCount += 1
    }

    func showInterstitial() {
        showCallCount += 1
    }

    func resetPlayFlag() {
        resetCallCount += 1
    }

    func disableAds() {
        disableCallCount += 1
        areAdsDisabled = true
    }

    func updateRemoveAdsProvider(_ provider: @escaping () -> Bool) {
        removeAdsProvider = provider
    }

    func adsConsentCoordinator(_ coordinator: AdsConsentCoordinating, didUpdate state: AdsConsentState, shouldReloadAds: Bool) {
        receivedConsentUpdates.append((state, shouldReloadAds))
    }

    // FullScreenContentDelegate 要件（テストでは利用しないため空実装）
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {}
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {}
    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {}
}

private final class StubMobileAdsController: MobileAdsControlling {
    private(set) var startCallCount: Int = 0

    func start(completion: @escaping () -> Void) {
        startCallCount += 1
        completion()
    }
}

@MainActor
private final class StubRootViewControllerProvider: RootViewControllerProviding {
    /// テスト用に返却するダミー ViewController
    let stubViewController: UIViewController
    /// AdsService からの取得要求回数
    private(set) var fetchCallCount: Int = 0

    init(stubViewController: UIViewController = UIViewController()) {
        self.stubViewController = stubViewController
    }

    func topViewController() -> UIViewController? {
        fetchCallCount += 1
        return stubViewController
    }
}

// MARK: - テスト本体
struct AdsServiceCoordinatorIntegrationTests {
    /// AdsService が依存注入された協調クラスへ処理を委譲していることを確認
    @MainActor
    @Test func adsService_delegatesToInjectedComponents() async throws {
        UserDefaults.standard.removeObject(forKey: "remove_ads_mk")
        UserDefaults.standard.removeObject(forKey: "ads_should_use_npa")

        let consent = StubAdsConsentCoordinator()
        let interstitial = StubInterstitialAdController()
        let mobileAds = StubMobileAdsController()
        let configuration = AdsServiceConfiguration(interstitialAdUnitID: "test", hasValidAdConfiguration: true)

        let service = AdsService(
            configuration: configuration,
            consentCoordinator: consent,
            interstitialController: interstitial,
            mobileAdsController: mobileAds
        )

        // 非同期タスクが実行される猶予を与える
        await Task.yield()
        await Task.yield()

        #expect(mobileAds.startCallCount == 1)
        #expect(interstitial.beginInitialLoadCallCount == 1)
        #expect(consent.synchronizeCallCount == 1)
        #expect((consent.presentationDelegate as AnyObject?) === service)
        #expect(consent.stateDelegate === interstitial)

        await service.requestConsentIfNeeded()
        await service.refreshConsentStatus()
        service.showInterstitial()
        service.resetPlayFlag()
        service.disableAds()

        #expect(consent.requestCallCount == 1)
        #expect(consent.refreshCallCount == 1)
        #expect(interstitial.showCallCount == 1)
        #expect(interstitial.resetCallCount == 1)
        #expect(interstitial.disableCallCount == 1)
    }

    /// AdsConsentCoordinator が通知する同意状態の変化を AdsService が橋渡しできているか検証
    @MainActor
    @Test func adsService_propagatesConsentStateChanges() async throws {
        UserDefaults.standard.removeObject(forKey: "remove_ads_mk")
        UserDefaults.standard.removeObject(forKey: "ads_should_use_npa")

        let environment = TestAdsConsentEnvironment()
        environment.consentStatus = .obtained
        environment.formStatus = .unavailable // UI 表示を避けつつ状態通知のみ行う
        environment.canRequestAds = true

        // requestConsentInfoUpdate の度に consentStatus をトグルし、状態変化を再現する
        var toggle = false
        environment.requestUpdateHandler = {
            toggle.toggle()
            if toggle {
                environment.consentStatus = .required
                environment.canRequestAds = false
            } else {
                environment.consentStatus = .obtained
                environment.canRequestAds = true
            }
        }

        let coordinator = AdsConsentCoordinator(hasValidAdConfiguration: true, environment: environment)
        let interstitial = StubInterstitialAdController()
        let mobileAds = StubMobileAdsController()
        let configuration = AdsServiceConfiguration(interstitialAdUnitID: "test", hasValidAdConfiguration: true)

        let service = AdsService(
            configuration: configuration,
            consentCoordinator: coordinator,
            interstitialController: interstitial,
            mobileAdsController: mobileAds
        )

        // Task 内で起動直後の同期処理が走るため、明示的に猶予を与える
        await Task.yield()
        await Task.yield()

        // 起動時同期で shouldUseNPA=true / canRequestAds=false へ変化する想定
        #expect(interstitial.receivedConsentUpdates.count == 1)
        if let first = interstitial.receivedConsentUpdates.first {
            #expect(first.0.shouldUseNPA == true)
            #expect(first.0.canRequestAds == false)
            #expect(first.1 == true)
        }

        // 再度状態更新を要求し、NPA=false / canRequestAds=true へ戻ることを確認
        await service.refreshConsentStatus()

        #expect(interstitial.receivedConsentUpdates.count == 2)
        if interstitial.receivedConsentUpdates.count >= 2 {
            let second = interstitial.receivedConsentUpdates[1]
            #expect(second.0.shouldUseNPA == false)
            #expect(second.0.canRequestAds == true)
            #expect(second.1 == true)
        }
    }

    /// requestConsentIfNeeded 実行時に AdsService が差し替えた ViewController プロバイダを利用してフォームを表示することを検証
    @MainActor
    @Test func adsService_presentsConsentFormUsingInjectedProvider() async throws {
        UserDefaults.standard.removeObject(forKey: "remove_ads_mk")
        UserDefaults.standard.removeObject(forKey: "ads_should_use_npa")

        let environment = TestAdsConsentEnvironment()
        environment.consentStatus = .required
        environment.formStatus = .available
        environment.canRequestAds = false

        let interstitial = StubInterstitialAdController()
        let mobileAds = StubMobileAdsController()
        let provider = StubRootViewControllerProvider()
        let configuration = AdsServiceConfiguration(interstitialAdUnitID: "test", hasValidAdConfiguration: true)

        environment.presenterFactory = {
            return { viewController, completion in
                // AdsService が注入済みプロバイダ経由で取得した VC を利用できているか検証
                #expect(viewController === provider.stubViewController)
                environment.consentStatus = .obtained
                environment.canRequestAds = true
                completion(nil)
            }
        }

        let coordinator = AdsConsentCoordinator(hasValidAdConfiguration: true, environment: environment)
        let service = AdsService(
            configuration: configuration,
            consentCoordinator: coordinator,
            interstitialController: interstitial,
            mobileAdsController: mobileAds,
            rootViewControllerProvider: provider
        )

        // 初期同期を待機し、Task が完了する余裕を作る
        await Task.yield()
        await Task.yield()

        await service.requestConsentIfNeeded()

        // presenterFactory 経由で completion が呼ばれたため shouldUseNPA=false / canRequestAds=true へ更新される想定
        #expect(provider.fetchCallCount >= 1)
        #expect(environment.requestUpdateCallCount >= 1)
        #expect(interstitial.receivedConsentUpdates.count >= 2)

        if let last = interstitial.receivedConsentUpdates.last {
            #expect(last.0.shouldUseNPA == false)
            #expect(last.0.canRequestAds == true)
            #expect(last.1 == true)
        }
    }
}
