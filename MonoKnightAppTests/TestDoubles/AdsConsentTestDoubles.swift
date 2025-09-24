import SwiftUI
import UIKit
import UserMessagingPlatform

@testable import MonoKnightApp

// MARK: - UMP テスト用スタブ環境
/// UMP から取得した同意情報をテストで細かく制御するための環境スタブ
/// - Note: 各プロパティはテスト側から直接書き換えられるよう internal で公開している
@MainActor
final class TestAdsConsentEnvironment: AdsConsentEnvironment {
    /// UMP 側の consentStatus を任意に切り替えるためのプロパティ
    var consentStatus: ConsentStatus = .unknown
    /// 同意フォームの取得可否を模倣するためのフラグ
    var formStatus: FormStatus = .unknown
    /// canRequestAds の真偽をテスト側から操作するためのプロパティ
    var canRequestAds: Bool = false

    /// requestConsentInfoUpdate が呼ばれた回数を検証用に記録
    private(set) var requestUpdateCallCount: Int = 0
    /// loadConsentFormPresenter の呼び出し回数を検証用に保持
    private(set) var loadFormCallCount: Int = 0
    /// makePrivacyOptionsPresenter の呼び出し回数を検証用に保持
    private(set) var makePrivacyOptionsCallCount: Int = 0

    /// ConsentInformation 更新時に追加で実行したい処理を注入するためのクロージャ
    var requestUpdateHandler: (() -> Void)?
    /// 同意フォームのプレゼンターを差し替えるためのクロージャ
    var presenterFactory: (() -> ConsentFormPresenter)?
    /// プライバシーオプションのプレゼンターを差し替えるためのクロージャ
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

        // デフォルトでは失敗しないダミー presenter を返却し、テストの容易さを確保する
        return { _, completion in completion(nil) }
    }

    func makePrivacyOptionsPresenter() -> PrivacyOptionsPresenter {
        makePrivacyOptionsCallCount += 1
        if let privacyPresenterFactory {
            return privacyPresenterFactory()
        }

        // デフォルトでは即座に完了する presenter を返却し、UI 表示を行わない
        return { _, completion in completion(nil) }
    }
}

// MARK: - プレゼンター／デリゲートのスタブ
/// AdsConsentCoordinator からの UI 表示要求を検証するためのスタブ実装
@MainActor
final class TestConsentPresentationDelegate: AdsConsentCoordinatorPresenting {
    /// 同意フォーム表示要求の回数
    private(set) var presentConsentFormCallCount: Int = 0
    /// プライバシーオプション表示要求の回数
    private(set) var presentPrivacyOptionsCallCount: Int = 0
    /// 直近で受け取った同意フォーム presenter（コールバック検証用）
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

/// 同意ステータスの通知内容を蓄積するためのレコーダ
@MainActor
final class TestConsentStateRecorder: AdsConsentCoordinatorStateDelegate {
    /// 通知された状態と shouldReload フラグの履歴
    private(set) var recordedStates: [(state: AdsConsentState, shouldReload: Bool)] = []

    func adsConsentCoordinator(_ coordinator: AdsConsentCoordinating, didUpdate state: AdsConsentState, shouldReloadAds: Bool) {
        recordedStates.append((state, shouldReloadAds))
    }
}

