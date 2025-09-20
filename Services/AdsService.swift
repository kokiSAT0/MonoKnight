import Foundation
import UIKit
import SwiftUI
import AppTrackingTransparency
import GoogleMobileAds

// MARK: - Protocol
protocol AdsServiceProtocol: AnyObject {
    func showInterstitial()
    func resetPlayFlag()
    func disableAds()
    func requestTrackingAuthorization() async
    func requestConsentIfNeeded() async
    func refreshConsentStatus() async
}

// MARK: - Google Mobile Ads 実装
@MainActor
final class AdsService: NSObject, ObservableObject, AdsServiceProtocol, FullScreenContentDelegate {
    /// Info.plist に定義するキー名をまとめる
    private enum InfoPlistKey {
        static let applicationIdentifier = "GADApplicationIdentifier"
        static let interstitialAdUnitID = "GADInterstitialAdUnitID"
    }

    /// シングルトンでサービスを共有
    static let shared = AdsService()

    @AppStorage("remove_ads") private var removeAds: Bool = false
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true
    /// UMP の同意結果から非パーソナライズ広告を求めるかどうか
    @AppStorage("ads_should_use_npa") private var shouldUseNPA: Bool = false

    /// インタースティシャル広告のキャッシュ
    private var interstitial: GADInterstitialAd?
    /// 直近に広告を表示した日時（頻度制御用）
    private var lastInterstitialDate: Date?
    /// 1プレイ1回の制御フラグ
    private var hasShownInCurrentPlay: Bool = false
    /// 重複読み込みを避けるためのフラグ
    private var isLoadingAd: Bool = false
    /// リトライを後続に送るための Task
    private var retryTask: Task<Void, Never>?
    /// 広告自体を停止するフラグ（IAP などで利用）
    private var adsDisabled: Bool = false

    /// Info.plist から読み取ったインタースティシャル広告ユニット ID（空文字ならロードしない）
    private let interstitialAdUnitID: String
    /// アプリ ID と広告ユニット ID が両方揃っているかどうか
    private let hasValidAdConfiguration: Bool

    /// 失敗時に再読み込みを試みるまでの秒数
    private let retryDelay: TimeInterval = 30

    private override init() {
        let applicationIdentifier = (Bundle.main.object(forInfoDictionaryKey: InfoPlistKey.applicationIdentifier) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if applicationIdentifier.isEmpty {
            assertionFailure("Info.plist に GADApplicationIdentifier が設定されていません。Config/Local.xcconfig で本番値を指定してください。")
        }

        let interstitialIdentifier = (Bundle.main.object(forInfoDictionaryKey: InfoPlistKey.interstitialAdUnitID) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if interstitialIdentifier.isEmpty {
            assertionFailure("Info.plist に GADInterstitialAdUnitID が設定されていません。Config/Local.xcconfig で本番値を指定してください。")
        }

        self.interstitialAdUnitID = interstitialIdentifier
        self.hasValidAdConfiguration = !applicationIdentifier.isEmpty && !interstitialIdentifier.isEmpty
        super.init()
        guard hasValidAdConfiguration else { return }

        // SDK 初期化。完了ハンドラーは現時点で不要のため nil を指定
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        // 初期化直後から広告読み込みを開始（非同期で走らせる）
        Task { [weak self] in
            await MainActor.run { self?.loadInterstitial() }
        }
    }

    deinit {
        // Task がぶら下がったままだと不要なリトライが残るため解放
        retryTask?.cancel()
    }

    func requestTrackingAuthorization() async {
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    func requestConsentIfNeeded() async {
        // UMP SDK 導入前のプレースホルダー。導入後に同意フォームを表示する
    }

    func refreshConsentStatus() async {
        // 将来的に UMP の同意状態を再取得する処理を実装する
    }

    func showInterstitial() {
        // IAP や設定で完全に無効化されている場合は何もしない
        guard !adsDisabled, !removeAds else { return }

        // インターバルや 1 プレイ 1 回の制御に引っかかったら終了
        guard canShowByTime(), !hasShownInCurrentPlay else { return }

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else {
            // RootViewController が取得できなかった場合も次の読み込みだけは仕掛ける
            Task { [weak self] in
                await MainActor.run { self?.loadInterstitial() }
            }
            return
        }

        guard let interstitial else {
            // キャッシュが無ければ即座に再読み込みを開始
            Task { [weak self] in
                await MainActor.run { self?.loadInterstitial() }
            }
            return
        }

        interstitial.present(fromRootViewController: root)
        if hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        lastInterstitialDate = Date()
        hasShownInCurrentPlay = true
        // 同じ広告を再利用しないように破棄
        self.interstitial = nil
    }

    func resetPlayFlag() {
        hasShownInCurrentPlay = false
    }

    func disableAds() {
        adsDisabled = true
        interstitial = nil
        retryTask?.cancel()
        retryTask = nil
    }

    /// インタースティシャル広告を読み込むヘルパー
    private func loadInterstitial() {
        guard hasValidAdConfiguration,
              !adsDisabled,
              !removeAds,
              !isLoadingAd,
              interstitial == nil else { return }

        isLoadingAd = true

        let request = GADRequest()
        if shouldUseNPA {
            // UMP の結果に従い非パーソナライズ広告をリクエスト
            let extras = GADExtras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
        }

        GADInterstitialAd.load(withAdUnitID: interstitialAdUnitID, request: request) { [weak self] ad, error in
            Task { [weak self] in
                await MainActor.run {
                    guard let self else { return }
                    self.isLoadingAd = false

                    if let error {
                        // DEBUG ビルドでは原因を追いやすいようログ出力
                        debugError(error, message: "インタースティシャル広告の読み込みに失敗")
                        self.scheduleRetry()
                        return
                    }

                    guard !self.adsDisabled, !self.removeAds else { return }
                    self.interstitial = ad
                    self.interstitial?.fullScreenContentDelegate = self
                    // 成功したのでリトライは不要
                    self.retryTask?.cancel()
                    self.retryTask = nil
                }
            }
        }
    }

    /// 再読み込みを一定時間後に行う
    private func scheduleRetry() {
        guard !adsDisabled else { return }
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            let delay = UInt64(retryDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            await MainActor.run { self?.loadInterstitial() }
        }
    }

    /// 最低 90 秒のインターバルを満たしているかどうか
    private func canShowByTime() -> Bool {
        guard let last = lastInterstitialDate else { return true }
        return Date().timeIntervalSince(last) >= 90
    }

    // MARK: - FullScreenContentDelegate

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        // 閉じたタイミングで次の広告を読み込む
        Task { [weak self] in
            await MainActor.run { self?.loadInterstitial() }
        }
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        debugError(error, message: "インタースティシャル広告の表示に失敗")
        interstitial = nil
        scheduleRetry()
    }
}
