import Foundation
import UIKit
import SwiftUI
import AppTrackingTransparency

// MARK: - Protocol
protocol AdsServiceProtocol: AnyObject {
    func showInterstitial()
    func resetPlayFlag()
    func disableAds()
    func requestTrackingAuthorization() async
    func requestConsentIfNeeded() async
    func refreshConsentStatus() async
}

// MARK: - Stub Impl (SDKなしでもビルド可)
final class AdsService: NSObject, ObservableObject, AdsServiceProtocol {
    static let shared = AdsService()

    @AppStorage("remove_ads") private var removeAds: Bool = false
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true

    private var lastInterstitialDate: Date?
    private var hasShownInCurrentPlay: Bool = false
    private let interstitialAdUnitID: String

    override private init() {
        // Info.plist から GMA のアプリ ID を取得し、未設定なら開発者に通知
        if let appID = Bundle.main.object(forInfoDictionaryKey: "GADApplicationIdentifier") as? String,
           !appID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // ここでは値を保持しないが、設定されていることを確認しておく
        } else {
            assertionFailure("GADApplicationIdentifier が Info.plist に設定されていません。")
        }

        // 同様に広告ユニット ID を検証し、空文字の場合はダミーを代入しておく
        if let unitID = Bundle.main.object(forInfoDictionaryKey: "GADInterstitialAdUnitID") as? String,
           !unitID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            interstitialAdUnitID = unitID
        } else {
            interstitialAdUnitID = ""
            assertionFailure("GADInterstitialAdUnitID が Info.plist に設定されていません。")
        }

        super.init()

        // SDK 導入時に備えて起動直後にロード処理を呼び出す
        loadInterstitial()
    }

    func requestTrackingAuthorization() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    // UMP/GMA は後で導入。今は no-op で良い
    func requestConsentIfNeeded() async { /* no-op */ }
    func refreshConsentStatus() async { /* no-op */ }

    func showInterstitial() {
        // 1プレイ1回 & インターバル & 購入済なら出さない
        guard !removeAds,
              canShowByTime(),
              !hasShownInCurrentPlay,
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }

        // ダミーの全画面ビューを表示（タップで閉じる）
        let vc = UIHostingController(rootView: DummyInterstitialView())
        vc.modalPresentationStyle = .fullScreen
        root.present(vc, animated: true)

        if hapticsEnabled { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        lastInterstitialDate = Date()
        hasShownInCurrentPlay = true
    }

    func resetPlayFlag() { hasShownInCurrentPlay = false }
    func disableAds()    { /* no-op */ }

    private func canShowByTime() -> Bool {
        guard let last = lastInterstitialDate else { return true }
        return Date().timeIntervalSince(last) >= 90
    }

    private func loadInterstitial() {
        // 実装メモ: GMA SDK を導入したら下記のように読み込みを行う想定
        // GADInterstitialAd.load(withAdUnitID: interstitialAdUnitID, request: GADRequest(), completionHandler: ...)
        guard !interstitialAdUnitID.isEmpty else { return }
#if DEBUG
        NSLog("[AdsService] インタースティシャル広告を読み込む想定の adUnitID: %@", interstitialAdUnitID)
#endif
    }
}

// ダミー広告ビュー
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
