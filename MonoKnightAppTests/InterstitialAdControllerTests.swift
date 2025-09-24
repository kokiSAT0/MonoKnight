import UIKit
import Testing
import GoogleMobileAds

@testable import MonoKnightApp

// MARK: - テスト用スタブ
@MainActor
private final class DummyAdsConsentCoordinator: AdsConsentCoordinating {
    var presentationDelegate: AdsConsentCoordinatorPresenting?
    var stateDelegate: AdsConsentCoordinatorStateDelegate?
    var currentState: AdsConsentState = AdsConsentState(shouldUseNPA: false, canRequestAds: false)

    func synchronizeOnLaunch() async {}
    func requestConsentIfNeeded() async {}
    func refreshConsentStatus() async {}
}

@MainActor
private final class StubInterstitialAdLoader: InterstitialAdLoading {
    /// load 呼び出し回数
    private(set) var loadCallCount: Int = 0
    /// 直近の completion を保持し、任意タイミングで結果を差し込めるようにする
    private(set) var lastCompletion: ((InterstitialAdPresentable?, Error?) -> Void)?
    /// 直近のリクエスト内容（NPA 判定検証用）
    private(set) var capturedRequests: [GoogleMobileAds.Request] = []

    func load(adUnitID: String, request: GoogleMobileAds.Request, completion: @escaping (InterstitialAdPresentable?, Error?) -> Void) {
        loadCallCount += 1
        capturedRequests.append(request)
        lastCompletion = completion
    }
}

@MainActor
private final class StubInterstitialAd: InterstitialAdPresentable {
    var fullScreenContentDelegate: FullScreenContentDelegate?
    /// present が呼ばれた回数
    private(set) var presentCallCount: Int = 0

    func present(from viewController: UIViewController) {
        presentCallCount += 1
        fullScreenContentDelegate?.adWillPresentFullScreenContent(self)
    }
}

@MainActor
private final class StubInterstitialDelegate: InterstitialAdControllerDelegate {
    var rootViewController: UIViewController? = UIViewController()
    /// Root VC 取得の呼び出し回数
    private(set) var rootRequestCount: Int = 0
    /// ハプティクス要求回数
    private(set) var hapticCallCount: Int = 0

    func rootViewControllerForPresentation(_ controller: InterstitialAdControlling) -> UIViewController? {
        rootRequestCount += 1
        return rootViewController
    }

    func interstitialAdControllerShouldPlayWarningHaptic(_ controller: InterstitialAdControlling) {
        hapticCallCount += 1
    }
}

// MARK: - テスト本体
struct InterstitialAdControllerTests {
    /// 初期ロードが行われ、showInterstitial で広告が表示されることを確認
    @MainActor
    @Test func beginInitialLoad_andShowInterstitial_presentAd() async throws {
        let loader = StubInterstitialAdLoader()
        let controller = InterstitialAdController(
            adUnitID: "test",
            hasValidAdConfiguration: true,
            initialConsentState: AdsConsentState(shouldUseNPA: false, canRequestAds: true),
            loader: loader,
            retryDelay: 0,
            minimumInterval: 0
        )
        let delegate = StubInterstitialDelegate()
        controller.delegate = delegate

        controller.beginInitialLoad()
        #expect(loader.loadCallCount == 1)
        let ad = StubInterstitialAd()
        loader.lastCompletion?(ad, nil)
        #expect(loader.capturedRequests.count == 1)

        controller.showInterstitial()
        #expect(ad.presentCallCount == 1)
        #expect(delegate.hapticCallCount == 1)
    }

    /// 同意状態の更新で shouldReload が true の場合に再読込が走ることを検証
    @MainActor
    @Test func consentUpdate_withReloadForcesNewLoad() async throws {
        let loader = StubInterstitialAdLoader()
        let controller = InterstitialAdController(
            adUnitID: "test",
            hasValidAdConfiguration: true,
            initialConsentState: AdsConsentState(shouldUseNPA: false, canRequestAds: true),
            loader: loader,
            retryDelay: 0,
            minimumInterval: 0
        )
        controller.delegate = StubInterstitialDelegate()

        controller.beginInitialLoad()
        #expect(loader.loadCallCount == 1)

        controller.adsConsentCoordinator(DummyAdsConsentCoordinator(), didUpdate: AdsConsentState(shouldUseNPA: true, canRequestAds: true), shouldReloadAds: true)
        #expect(loader.loadCallCount == 2)
    }

    /// disableAds 後は表示要求が無視されることを確認
    @MainActor
    @Test func disableAds_blocksPresentation() async throws {
        let loader = StubInterstitialAdLoader()
        let controller = InterstitialAdController(
            adUnitID: "test",
            hasValidAdConfiguration: true,
            initialConsentState: AdsConsentState(shouldUseNPA: false, canRequestAds: true),
            loader: loader,
            retryDelay: 0,
            minimumInterval: 0
        )
        let delegate = StubInterstitialDelegate()
        controller.delegate = delegate

        controller.disableAds()
        controller.beginInitialLoad()
        #expect(loader.loadCallCount == 0)
        controller.showInterstitial()
        #expect(delegate.hapticCallCount == 0)
    }
}
