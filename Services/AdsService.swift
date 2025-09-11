import Foundation
import UIKit
import SwiftUI
import AppTrackingTransparency

#if canImport(GoogleMobileAds)
import GoogleMobileAds               // あるときだけ使う
#endif

#if canImport(UserMessagingPlatform)
import UserMessagingPlatform         // あるときだけ使う
#endif

// MARK: - Protocol

protocol AdsServiceProtocol: AnyObject {
    func showInterstitial()
    func resetPlayFlag()
    func disableAds()
    func requestTrackingAuthorization() async
    func requestConsentIfNeeded() async
    func refreshConsentStatus() async
}

// MARK: - Impl

final class AdsService: NSObject, ObservableObject, AdsServiceProtocol {
    static let shared = AdsService()

    // env をセットしたら「常にダミーを出す」挙動に
    private let testInterstitialID = ProcessInfo.processInfo.environment["GAD_INTERSTITIAL_ID"]
    private var isTestMode: Bool { testInterstitialID != nil }

    // GMA がある時だけ実体を保持
    #if canImport(GoogleMobileAds)
    private var interstitial: InterstitialAd?   // v11+ は InterstitialAd
    #endif

    @AppStorage("remove_ads") private var removeAds: Bool = false
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true

    private var isPersonalized: Bool = false
    private var lastInterstitialDate: Date?
    private var hasShownInCurrentPlay: Bool = false

    private override init() { super.init() }

    // MARK: Consent / ATT

    func requestTrackingAuthorization() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    func requestConsentIfNeeded() async {
        #if canImport(UserMessagingPlatform)
        let params = UMPRequestParameters()
        params.tagForUnderAgeOfConsent = false
        let consentInfo = UMPConsentInformation.sharedInstance

        do {
            try await withCheckedThrowingContinuation { cont in
                consentInfo.requestConsentInfoUpdate(with: params) { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
            if consentInfo.formStatus == .available {
                let form = try await withCheckedThrowingContinuation { cont in
                    UMPConsentForm.load { form, error in
                        if let error { cont.resume(throwing: error) }
                        else if let form { cont.resume(returning: form) }
                    }
                }
                if let root = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene }).first?
                    .windows.first?.rootViewController {
                    try await withCheckedThrowingContinuation { cont in
                        form.present(from: root) { error in
                            if let error { cont.resume(throwing: error) } else { cont.resume() }
                        }
                    }
                }
            }
            isPersonalized = (consentInfo.consentStatus == .obtained)
        } catch {
            debugPrint("[UMP] 同意取得失敗:", error.localizedDescription)
            isPersonalized = false
        }
        #else
        // UMP が無ければ非パーソナライズ扱い
        isPersonalized = false
        #endif

        if !removeAds { loadInterstitial() }
    }

    func refreshConsentStatus() async {
        #if canImport(UserMessagingPlatform)
        let params = UMPRequestParameters()
        params.tagForUnderAgeOfConsent = false
        let consentInfo = UMPConsentInformation.sharedInstance
        do {
            try await withCheckedThrowingContinuation { cont in
                consentInfo.requestConsentInfoUpdate(with: params) { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
            isPersonalized = (consentInfo.consentStatus == .obtained)
        } catch {
            debugPrint("[UMP] 再取得失敗:", error.localizedDescription)
            isPersonalized = false
        }
        #else
        isPersonalized = false
        #endif

        if !removeAds {
            #if canImport(GoogleMobileAds)
            interstitial = nil
            #endif
            loadInterstitial()
        } else {
            #if canImport(GoogleMobileAds)
            interstitial = nil
            #endif
        }
    }

    // MARK: Load

    private func loadInterstitial() {
        // 購入済/テストモード は読み込み不要
        guard !removeAds, !isTestMode else { return }

        #if canImport(GoogleMobileAds)
        let request = GADRequest()
        if !isPersonalized {
            let extras = GADExtras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
        }

        // テスト用ユニット ID
        let adUnit = "ca-app-pub-3940256099942544/4411468910"

        InterstitialAd.load(withAdUnitID: adUnit, request: request) { [weak self] ad, error in
            if let error {
                debugPrint("[Ads] load 失敗:", error.localizedDescription)
                return
            }
            self?.interstitial = ad
        }
        #else
        // GMA が無いビルドは何もしない
        debugPrint("[Ads] GoogleMobileAds 無し（読み込みスキップ）")
        #endif
    }

    // MARK: Show

    func showInterstitial() {
        guard !removeAds,
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController,
              canShowByTime(),
              !hasShownInCurrentPlay else { return }

        // --- テストモード or GMA 無し → ダミー表示 ---
        #if !canImport(GoogleMobileAds)
        presentDummy(from: root)
        return
        #else
        if isTestMode {
            presentDummy(from: root)
            return
        }

        // --- GMA あり通常表示 ---
        guard let ad = interstitial else { return }
        ad.present(fromRootViewController: root)
        if hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        lastInterstitialDate = Date()
        hasShownInCurrentPlay = true
        interstitial = nil
        loadInterstitial()
        #endif
    }

    // MARK: Utilities

    private func presentDummy(from root: UIViewController) {
        let vc = UIHostingController(rootView: DummyInterstitialView())
        vc.modalPresentationStyle = .fullScreen
        root.present(vc, animated: true)
        if hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        lastInterstitialDate = Date()
        hasShownInCurrentPlay = true
    }

    private func canShowByTime() -> Bool {
        guard let lastInterstitialDate else { return true }
        return Date().timeIntervalSince(lastInterstitialDate) >= 90
    }

    func resetPlayFlag() { hasShownInCurrentPlay = false }
    func disableAds()   {
        #if canImport(GoogleMobileAds)
        interstitial = nil
        #endif
    }
}

// MARK: - Dummy View

private struct DummyInterstitialView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack {
            Color.black
            Text("Test Ad").foregroundColor(.white)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("dummy_interstitial_ad")
        .onTapGesture { dismiss() }
    }
}
