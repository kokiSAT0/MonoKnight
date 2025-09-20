import Foundation
import UIKit
import SwiftUI
import AppTrackingTransparency
import GoogleMobileAds
import UserMessagingPlatform

// MARK: - Protocol
protocol AdsServiceProtocol: AnyObject {
    func showInterstitial()
    func resetPlayFlag()
    func disableAds()
    func requestTrackingAuthorization() async
    func requestConsentIfNeeded() async
    func refreshConsentStatus() async
}

// MARK: - 本番実装
@MainActor
final class AdsService: NSObject, ObservableObject, AdsServiceProtocol {
    /// グローバルに共有するシングルトンインスタンス
    static let shared = AdsService()

    // MARK: 永続化フラグ
    /// 広告除去購入済みフラグ。`true` の場合は一切の広告読み込みを停止する。
    @AppStorage("remove_ads") private var removeAds: Bool = false
    /// ハプティクスの有効／無効設定。広告表示時の通知に利用する。
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true
    /// パーソナライズ広告を許可してよいかどうか。UMP の同意結果に応じて更新する。
    @AppStorage("ads_is_personalized") private var isPersonalized: Bool = false
    /// プライバシー設定フォームを再表示できるかどうか。設定画面の文言と連携する。
    @AppStorage("ads_privacy_options_available") private var isPrivacyOptionsAvailable: Bool = false

    // MARK: UMP 関連
    /// Google UMP の同意情報を管理するシングルトン。
    private let consentInformation = UMPConsentInformation.sharedInstance()
    /// 直近で読み込んだ同意フォーム。再表示が必要な場合に保持しておく。
    private var consentForm: UMPConsentForm?
    /// 同意フォームを多重起動しないためのフラグ。
    private var isPresentingForm: Bool = false

    // MARK: AdMob 関連
    /// 現在保持しているインタースティシャル広告オブジェクト。
    private var interstitial: GADInterstitialAd?
    /// 読み込みリクエストの多重実行を防ぐためのフラグ。
    private var isLoadingInterstitial: Bool = false
    /// 読み込み中のリクエストを識別する ID。途中で設定が変わった場合は旧リクエストを無効化する。
    private var currentLoadIdentifier: UUID = .init()

    /// 前回広告を表示した日時（90 秒間隔制御用）。
    private var lastInterstitialDate: Date?
    /// 1 プレイ中に既に広告を表示したかどうか。
    private var hasShownInCurrentPlay: Bool = false

    /// テスト用／本番用のインタースティシャル広告ユニット ID。
    /// - NOTE: 実機リリース前に本番用 ID へ差し替えること。
    private let interstitialAdUnitID: String

    private override init() {
        #if DEBUG
        self.interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"
        #else
        self.interstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910" // 本番リリース前に実際の広告ユニット ID へ差し替える
        #endif
        super.init()
        // SDK 初期化を先に行い、以降のロードが確実に動作するようにする。
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        // 起動直後は保持している同意情報に基づきフラグを整合させる。
        _ = updateConsentFlags()
        // 初回の広告読み込みを準備しておく（除去済みの場合は内部でスキップされる）。
        loadInterstitial()
    }

    // MARK: ATT
    func requestTrackingAuthorization() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    // MARK: UMP - 初回同意取得
    func requestConsentIfNeeded() async {
        guard !removeAds else { return }
        let parameters = buildRequestParameters()

        do {
            // 最新の同意状況を取得
            try await requestConsentInfoUpdate(with: parameters)
            _ = updateConsentFlags()

            if consentInformation.formStatus == .available {
                do {
                    // 同意フォームを読み込み → 表示の順で実行
                    try await presentConsentFormFlow()
                } catch {
                    // フォーム表示で失敗した場合もユーザーに致命的影響は無いためログのみに留める。
                    debugError(error, message: "UMP 同意フォームの表示に失敗")
                }
            }

            // フォーム完了後の最終ステータスを反映し、必要なら広告を再ロード
            let didChange = updateConsentFlags()
            if didChange {
                reloadInterstitialForConsentChange()
            } else if interstitial == nil {
                loadInterstitial()
            }
        } catch {
            debugError(error, message: "UMP 同意情報の取得に失敗")
        }
    }

    // MARK: UMP - 状態更新
    func refreshConsentStatus() async {
        guard !removeAds else { return }
        let parameters = buildRequestParameters()

        do {
            try await requestConsentInfoUpdate(with: parameters)
            _ = updateConsentFlags()

            // 規制対象地域などで再同意が必要になった場合のみフォームを再表示
            if consentInformation.formStatus == .available && consentInformation.consentStatus == .required {
                do {
                    try await presentConsentFormFlow()
                } catch {
                    debugError(error, message: "UMP 同意フォームの再提示に失敗")
                }
            }

            let didChange = updateConsentFlags()
            if didChange {
                reloadInterstitialForConsentChange()
            } else if interstitial == nil {
                loadInterstitial()
            }
        } catch {
            debugError(error, message: "UMP 同意状況の更新に失敗")
        }
    }

    // MARK: インタースティシャル表示
    func showInterstitial() {
        guard !removeAds,
              canShowByTime(),
              !hasShownInCurrentPlay,
              let presentingViewController = topViewController(),
              let interstitial else {
            // 条件未達の場合は次回のために読み込みだけ仕込んでおく。
            if self.interstitial == nil { loadInterstitial() }
            return
        }

        // 実際に広告を表示。警告ハプティクスも併用して注意喚起する。
        interstitial.present(fromRootViewController: presentingViewController)
        if hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        hasShownInCurrentPlay = true
        lastInterstitialDate = Date()
    }

    func resetPlayFlag() {
        hasShownInCurrentPlay = false
    }

    func disableAds() {
        removeAds = true
        discardInterstitial()
    }

    // MARK: - プライベートヘルパー
    /// ユーザーの年齢設定などを考慮した UMP リクエストパラメータを構築する。
    private func buildRequestParameters() -> UMPRequestParameters {
        let parameters = UMPRequestParameters()
        parameters.tagForUnderAgeOfConsent = false
        return parameters
    }

    /// UMP の consentInfoUpdate を async/await で扱えるようラップする。
    private func requestConsentInfoUpdate(with parameters: UMPRequestParameters) async throws {
        try await withCheckedThrowingContinuation { continuation in
            consentInformation.requestConsentInfoUpdate(with: parameters) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// 同意フォームを読み込み、表示まで完了させる。
    private func presentConsentFormFlow() async throws {
        guard !isPresentingForm else { return }
        isPresentingForm = true
        defer { isPresentingForm = false }

        let form = try await loadConsentForm()
        consentForm = form
        do {
            try await present(consentForm: form)
        } catch {
            consentForm = nil
            throw error
        }
        consentForm = nil
    }

    /// UMP の同意フォーム読み込み処理を async/await へ変換する。
    private func loadConsentForm() async throws -> UMPConsentForm {
        try await withCheckedThrowingContinuation { continuation in
            UMPConsentForm.load { form, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let form {
                    continuation.resume(returning: form)
                } else {
                    continuation.resume(throwing: AdsServiceError.formUnavailable)
                }
            }
        }
    }

    /// 同意フォームを最前面の ViewController から表示する。
    private func present(consentForm: UMPConsentForm) async throws {
        let viewController = try fetchRootViewController()
        try await withCheckedThrowingContinuation { continuation in
            consentForm.present(from: viewController) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// 現在の同意ステータスを `@AppStorage` と同期し、変更有無を返す。
    @discardableResult
    private func updateConsentFlags() -> Bool {
        isPrivacyOptionsAvailable = (consentInformation.formStatus == .available)

        let previousPersonalized = isPersonalized
        let newPersonalized: Bool
        switch consentInformation.consentStatus {
        case .obtained, .notRequired:
            // 同意済み、または規制対象外の場合はパーソナライズ可能
            newPersonalized = true
        case .required, .unknown:
            // 同意が未取得・不明な場合は安全側で非パーソナライズに倒す
            newPersonalized = false
        @unknown default:
            newPersonalized = false
        }
        isPersonalized = newPersonalized
        return previousPersonalized != newPersonalized
    }

    /// 広告読み込み専用の `GADRequest` を生成し、NPA 指定を付与した上でロードを開始する。
    private func loadInterstitial() {
        guard !removeAds else { return }
        guard !isLoadingInterstitial else { return }

        let request = GADRequest()
        let extras = GADExtras()
        if !isPersonalized {
            // 非パーソナライズ広告を要求する場合は npa=1 を付与する。
            extras.additionalParameters = ["npa": "1"]
        }
        request.register(extras)

        isLoadingInterstitial = true
        let loadIdentifier = UUID()
        currentLoadIdentifier = loadIdentifier

        GADInterstitialAd.load(withAdUnitID: interstitialAdUnitID, request: request) { [weak self] ad, error in
            guard let self else { return }
            // 最新のロードでなければ破棄する（同意更新直後など）。
            guard self.currentLoadIdentifier == loadIdentifier else { return }

            self.isLoadingInterstitial = false
            if let error {
                debugError(error, message: "インタースティシャル広告の読み込みに失敗")
                return
            }
            guard let ad else { return }
            ad.fullScreenContentDelegate = self
            self.interstitial = ad
            debugLog("インタースティシャル広告を読み込み済み")
        }
    }

    /// 現在保持している広告を破棄し、新たにロードを仕掛ける。
    private func reloadInterstitialForConsentChange() {
        discardInterstitial()
        loadInterstitial()
    }

    /// 既存のインタースティシャルを解放し、デリゲート参照も破棄する。
    private func discardInterstitial() {
        interstitial?.fullScreenContentDelegate = nil
        interstitial = nil
        isLoadingInterstitial = false
        currentLoadIdentifier = UUID()
    }

    /// 表示可能な最前面 ViewController を取得する。
    private func topViewController() -> UIViewController? {
        guard let root = try? fetchRootViewController() else { return nil }
        return root
    }

    /// UIWindowScene から最前面の ViewController を探索する。
    private func fetchRootViewController() throws -> UIViewController {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              let root = window.rootViewController else {
            throw AdsServiceError.rootViewControllerMissing
        }
        return traversePresentedViewController(from: root)
    }

    /// 再帰的に `presentedViewController` を辿り、最前面の VC を返す。
    private func traversePresentedViewController(from controller: UIViewController) -> UIViewController {
        if let navigation = controller as? UINavigationController,
           let visible = navigation.visibleViewController {
            return traversePresentedViewController(from: visible)
        }
        if let tab = controller as? UITabBarController,
           let selected = tab.selectedViewController {
            return traversePresentedViewController(from: selected)
        }
        if let presented = controller.presentedViewController {
            return traversePresentedViewController(from: presented)
        }
        return controller
    }

    /// 90 秒以上経過しているかを確認し、広告表示の頻度制御を行う。
    private func canShowByTime() -> Bool {
        guard let last = lastInterstitialDate else { return true }
        return Date().timeIntervalSince(last) >= 90
    }
}

// MARK: - GADFullScreenContentDelegate
@MainActor
extension AdsService: GADFullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        // 閉じたら次回に備えて新しい広告を読み込む。
        discardInterstitial()
        loadInterstitial()
    }

    func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        // 表示失敗時も再度ロードしておく。
        debugError(error, message: "インタースティシャル広告の表示に失敗")
        discardInterstitial()
        loadInterstitial()
    }
}

// MARK: - エラー定義
private enum AdsServiceError: LocalizedError {
    /// 最前面の ViewController を取得できなかった場合。
    case rootViewControllerMissing
    /// UMP フォームが nil で返却された場合。
    case formUnavailable

    var errorDescription: String? {
        switch self {
        case .rootViewControllerMissing:
            return "ルート ViewController の取得に失敗"
        case .formUnavailable:
            return "UMP 同意フォームを取得できませんでした"
        }
    }
}

