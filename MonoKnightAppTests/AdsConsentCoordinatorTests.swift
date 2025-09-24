import SwiftUI
import UIKit
import Testing
import UserMessagingPlatform
@testable import MonoKnightApp

// MARK: - スタブ定義
@MainActor
private final class StubAdsConsentEnvironment: AdsConsentEnvironment {
    /// UMP 側の consentStatus をテストから書き換えやすく保持
    var consentStatus: ConsentStatus = .unknown
    /// フォームの利用可否をテストシナリオ毎に指定
    var formStatus: FormStatus = .unknown
    /// canRequestAds を外部から操作し、ロード条件を切り替える
    var canRequestAds: Bool = false
    /// requestConsentInfoUpdate が呼ばれた回数
    private(set) var requestUpdateCallCount: Int = 0
    /// loadConsentFormPresenter が呼ばれた回数
    private(set) var loadFormCallCount: Int = 0
    /// makePrivacyOptionsPresenter が呼ばれた回数
    private(set) var makePrivacyOptionsCallCount: Int = 0

    /// 更新時に追加で実行したい処理（例: consentStatus の差し替え）
    var requestUpdateHandler: (() -> Void)?
    /// フォーム表示用クロージャを差し替えるためのプロパティ
    var presenterFactory: (() -> ConsentFormPresenter)?
    /// プライバシーオプション表示用クロージャを差し替えるためのプロパティ
    var privacyPresenterFactory: (() -> PrivacyOptionsPresenter)?

    func requestConsentInfoUpdate(with parameters: RequestParameters) async throws {
        requestUpdateCallCount += 1
        requestUpdateHandler?()
    }

    func loadConsentFormPresenter() async throws -> ConsentFormPresenter {
        loadFormCallCount += 1
        if let presenterFactory {
            return presenterFactory()
        }
        return { _, completion in completion(nil) }
    }

    func makePrivacyOptionsPresenter() -> PrivacyOptionsPresenter {
        makePrivacyOptionsCallCount += 1
        if let privacyPresenterFactory {
            return privacyPresenterFactory()
        }
        return { _, completion in completion(nil) }
    }
}

@MainActor
private final class StubConsentPresentationDelegate: AdsConsentCoordinatorPresenting {
    /// 同意フォーム表示要求の回数
    private(set) var presentConsentFormCallCount: Int = 0
    /// プライバシーオプション表示要求の回数
    private(set) var presentPrivacyOptionsCallCount: Int = 0
    /// 直近で受け取った presenter（検証用）
    private(set) var lastConsentPresenter: ConsentFormPresenter?
    /// 直近で受け取ったプライバシー presenter
    private(set) var lastPrivacyPresenter: PrivacyOptionsPresenter?

    func presentConsentForm(using presenter: @escaping ConsentFormPresenter) async throws {
        presentConsentFormCallCount += 1
        lastConsentPresenter = presenter
        presenter(UIViewController()) { _ in }
    }

    func presentPrivacyOptions(using presenter: @escaping PrivacyOptionsPresenter) async throws {
        presentPrivacyOptionsCallCount += 1
        lastPrivacyPresenter = presenter
        presenter(UIViewController()) { _ in }
    }
}

@MainActor
private final class StubConsentStateDelegate: AdsConsentCoordinatorStateDelegate {
    /// 状態更新の履歴（shouldReload フラグも保持）
    private(set) var recordedStates: [(state: AdsConsentState, shouldReload: Bool)] = []

    func adsConsentCoordinator(_ coordinator: AdsConsentCoordinating, didUpdate state: AdsConsentState, shouldReloadAds: Bool) {
        recordedStates.append((state, shouldReloadAds))
    }
}

// MARK: - テスト本体
struct AdsConsentCoordinatorTests {
    /// requestConsentIfNeeded が必須同意の際にフォームを表示し、最終的に NPA フラグが false へ戻ることを検証
    @MainActor
    @Test func requestConsentIfNeeded_showsFormWhenRequired() async throws {
        UserDefaults.standard.removeObject(forKey: "ads_should_use_npa")

        let environment = StubAdsConsentEnvironment()
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

        let presenter = StubConsentPresentationDelegate()
        let stateDelegate = StubConsentStateDelegate()
        let coordinator = AdsConsentCoordinator(hasValidAdConfiguration: true, environment: environment)
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

        let environment = StubAdsConsentEnvironment()
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

        let presenter = StubConsentPresentationDelegate()
        let stateDelegate = StubConsentStateDelegate()
        let coordinator = AdsConsentCoordinator(hasValidAdConfiguration: true, environment: environment)
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
        let environment = StubAdsConsentEnvironment()
        let presenter = StubConsentPresentationDelegate()
        let stateDelegate = StubConsentStateDelegate()
        let coordinator = AdsConsentCoordinator(hasValidAdConfiguration: false, environment: environment)
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
}
