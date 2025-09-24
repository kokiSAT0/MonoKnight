import Foundation
import SwiftUI
import UIKit
import UserMessagingPlatform
import SharedSupport // debugLog / debugError を利用するため追加

// MARK: - 同意状態の表現
/// UMP の情報を中継しつつアプリ側で扱いやすいようにした構造体
/// - Note: `shouldUseNPA` は広告リクエストへ直結するため、テストからも直接参照できるようプロパティとして公開している
struct AdsConsentState {
    /// 非パーソナライズ広告を要求すべきかどうか
    let shouldUseNPA: Bool
    /// Google Mobile Ads へ広告リクエストを送ってよい状態か
    let canRequestAds: Bool
}

/// 同意フォーム表示用クロージャの型定義
/// - Parameter viewController: 表示に利用する最前面の ViewController
/// - Parameter completion: 表示完了後に UMP から渡されるエラー（成功時は `nil`）
typealias ConsentFormPresenter = (_ viewController: UIViewController, _ completion: @escaping (Error?) -> Void) -> Void

/// プライバシーオプション表示用クロージャの型定義
typealias PrivacyOptionsPresenter = (_ viewController: UIViewController, _ completion: @escaping (Error?) -> Void) -> Void

// MARK: - プロトコル定義
/// AdsConsentCoordinator が UI へ委譲する際のプレゼンター
@MainActor
protocol AdsConsentCoordinatorPresenting: AnyObject {
    /// UMP の同意フォームを提示するためのクロージャを受け取り、UI 表示を担う
    func presentConsentForm(using presenter: @escaping ConsentFormPresenter) async throws
    /// UMP の Privacy Options を提示するためのクロージャを受け取り、UI 表示を担う
    func presentPrivacyOptions(using presenter: @escaping PrivacyOptionsPresenter) async throws
}

/// 同意状況の変化を受け取るデリゲート
@MainActor
protocol AdsConsentCoordinatorStateDelegate: AnyObject {
    /// shouldUseNPA や canRequestAds の更新結果を通知し、必要に応じて広告キャッシュの更新を促す
    func adsConsentCoordinator(_ coordinator: AdsConsentCoordinating, didUpdate state: AdsConsentState, shouldReloadAds: Bool)
}

/// 同意周りの処理を提供するプロトコル
@MainActor
protocol AdsConsentCoordinating: AnyObject {
    var presentationDelegate: AdsConsentCoordinatorPresenting? { get set }
    var stateDelegate: AdsConsentCoordinatorStateDelegate? { get set }
    var currentState: AdsConsentState { get }

    func synchronizeOnLaunch() async
    func requestConsentIfNeeded() async
    func refreshConsentStatus() async
}

/// UMP SDK の操作を抽象化した環境依存プロトコル
@MainActor
protocol AdsConsentEnvironment: AnyObject {
    var consentStatus: ConsentStatus { get }
    var formStatus: FormStatus { get }
    var canRequestAds: Bool { get }

    func requestConsentInfoUpdate(with parameters: RequestParameters) async throws
    func loadConsentFormPresenter() async throws -> ConsentFormPresenter
    func makePrivacyOptionsPresenter() -> PrivacyOptionsPresenter
}

// MARK: - デフォルト環境
/// 実機動作用に UMP SDK を直接呼び出す実装
@MainActor
final class DefaultAdsConsentEnvironment: AdsConsentEnvironment {
    func requestConsentInfoUpdate(with parameters: RequestParameters) async throws {
        let consentInfo = ConsentInformation.shared
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            consentInfo.requestConsentInfoUpdate(with: parameters) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    var consentStatus: ConsentStatus {
        ConsentInformation.shared.consentStatus
    }

    var formStatus: FormStatus {
        ConsentInformation.shared.formStatus
    }

    var canRequestAds: Bool {
        ConsentInformation.shared.canRequestAds
    }

    func loadConsentFormPresenter() async throws -> ConsentFormPresenter {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ConsentFormPresenter, Error>) in
            ConsentForm.load { form, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let form else {
                    let unexpected = NSError(
                        domain: "MonoKnight.AdsConsentCoordinator",
                        code: -10,
                        userInfo: [NSLocalizedDescriptionKey: "同意フォームが取得できませんでした"]
                    )
                    continuation.resume(throwing: unexpected)
                    return
                }

                // presenter 内で強参照が残り続けると二重表示の原因になるため、ローカル変数で管理しておく
                var storedForm: ConsentForm? = form
                let presenter: ConsentFormPresenter = { viewController, completion in
                    // guard の省略記法を使うと storedForm がシャドーイングされてしまい、
                    // 後続で nil 代入ができなくなるため別名に退避する
                    guard let formForPresentation = storedForm else {
                        let error = NSError(
                            domain: "MonoKnight.AdsConsentCoordinator",
                            code: -11,
                            userInfo: [NSLocalizedDescriptionKey: "同意フォームが破棄済みのため再表示できません"]
                        )
                        completion(error)
                        return
                    }
                    formForPresentation.present(from: viewController) { error in
                        storedForm = nil
                        completion(error)
                    }
                }
                continuation.resume(returning: presenter)
            }
        }
    }

    func makePrivacyOptionsPresenter() -> PrivacyOptionsPresenter {
        return { viewController, completion in
            ConsentForm.presentPrivacyOptionsForm(from: viewController) { error in
                completion(error)
            }
        }
    }
}

// MARK: - Coordinator 本体
@MainActor
final class AdsConsentCoordinator: AdsConsentCoordinating {
    weak var presentationDelegate: AdsConsentCoordinatorPresenting?
    weak var stateDelegate: AdsConsentCoordinatorStateDelegate?

    /// UMP の処理を抽象化した環境
    private let environment: AdsConsentEnvironment
    /// Info.plist に必要な値が揃っているかどうか
    private let hasValidAdConfiguration: Bool
    /// AppStorage 経由で NPA 判定を永続化する
    @AppStorage("ads_should_use_npa") private var shouldUseNPA: Bool = false

    init(hasValidAdConfiguration: Bool, environment: AdsConsentEnvironment = DefaultAdsConsentEnvironment()) {
        self.hasValidAdConfiguration = hasValidAdConfiguration
        self.environment = environment
    }

    var currentState: AdsConsentState {
        AdsConsentState(shouldUseNPA: shouldUseNPA, canRequestAds: environment.canRequestAds)
    }

    func synchronizeOnLaunch() async {
        guard hasValidAdConfiguration else { return }

        do {
            await MainActor.run {
                debugLog("アプリ起動直後の UMP 同意情報を同期します")
            }
            try await requestConsentUpdateAndNotify()
        } catch {
            await MainActor.run {
                debugError(error, message: "起動時の UMP 同期に失敗")
            }
        }
    }

    func requestConsentIfNeeded() async {
        guard hasValidAdConfiguration else { return }

        do {
            debugLog("Google UMP の同意取得フローを開始します")
            try await requestConsentUpdateAndNotify()

            guard environment.formStatus == .available else { return }

            let presenter = try await environment.loadConsentFormPresenter()
            if environment.consentStatus == .required || environment.consentStatus == .unknown {
                try await presentationDelegate?.presentConsentForm(using: presenter)
                applyConsentStatusAndNotify()
            }
            debugLog("Google UMP の同意取得フローが完了しました (status: \(String(describing: environment.consentStatus)))")
        } catch {
            debugError(error, message: "Google UMP の同意取得に失敗")
        }
    }

    func refreshConsentStatus() async {
        guard hasValidAdConfiguration else { return }

        do {
            debugLog("Google UMP の同意ステータス更新を開始します")
            try await requestConsentUpdateAndNotify()

            guard environment.formStatus == .available else { return }

            let presenter = environment.makePrivacyOptionsPresenter()
            try await presentationDelegate?.presentPrivacyOptions(using: presenter)
            applyConsentStatusAndNotify()
            debugLog("Google UMP の同意ステータス更新が完了しました (status: \(String(describing: environment.consentStatus)))")
        } catch {
            debugError(error, message: "Google UMP の同意状態更新に失敗")
        }
    }

    /// DEBUG/リリース共通で ConsentInformation の更新と通知まで行う共通処理
    private func requestConsentUpdateAndNotify() async throws {
        let parameters = makeRequestParameters()
        try await environment.requestConsentInfoUpdate(with: parameters)
        applyConsentStatusAndNotify()
    }

    /// UMP の結果に応じて shouldUseNPA を更新し、デリゲートへ状態を伝える
    @discardableResult
    private func applyConsentStatusAndNotify() -> AdsConsentState {
        let newShouldUseNPA: Bool
        switch environment.consentStatus {
        case .obtained, .notRequired:
            newShouldUseNPA = false
        default:
            newShouldUseNPA = true
        }

        let hasChanged = newShouldUseNPA != shouldUseNPA
        shouldUseNPA = newShouldUseNPA

        let state = AdsConsentState(shouldUseNPA: newShouldUseNPA, canRequestAds: environment.canRequestAds)
        stateDelegate?.adsConsentCoordinator(self, didUpdate: state, shouldReloadAds: hasChanged)
        debugLog("UMP の同意結果を反映しました (shouldUseNPA: \(newShouldUseNPA), canRequestAds: \(state.canRequestAds))")
        return state
    }

    /// RequestParameters を生成するヘルパー
    /// - Note: RequestParameters / DebugSettings は MainActor 専有のイニシャライザを持つため、
    ///         メソッド全体を @MainActor で明示してメインスレッド上で生成されることを保証する。
    @MainActor
    private func makeRequestParameters() -> RequestParameters {
        let parameters = RequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false // UMP SDK v2 以降のリネームに追従（未成年扱いのフラグを明示的に無効化）

        #if DEBUG
        let debugSettings = DebugSettings()
        debugSettings.geography = .EEA
        parameters.debugSettings = debugSettings
        #endif

        return parameters
    }
}
