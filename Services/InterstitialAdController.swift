import Foundation
import SwiftUI
import UIKit
import GoogleMobileAds
import SharedSupport // ログユーティリティを利用するため追加

// MARK: - インタースティシャル制御用のプロトコル
/// AdsService が UI 側の責務を担いつつ、広告ロード/表示ロジックのみを委譲できるようにする
@MainActor
protocol InterstitialAdControllerDelegate: AnyObject {
    /// 表示に利用する最前面の ViewController を返す
    func rootViewControllerForPresentation(_ controller: InterstitialAdControlling) -> UIViewController?
    /// 表示時にユーザーへ警告ハプティクスを鳴らすかどうかを委譲する
    func interstitialAdControllerShouldPlayWarningHaptic(_ controller: InterstitialAdControlling)
}

/// インタースティシャル広告の振る舞いを統一するためのインターフェース
@MainActor
protocol InterstitialAdControlling: AnyObject, FullScreenContentDelegate, AdsConsentCoordinatorStateDelegate {
    var delegate: InterstitialAdControllerDelegate? { get set }
    var areAdsDisabled: Bool { get }

    func beginInitialLoad()
    func showInterstitial()
    func resetPlayFlag()
    func disableAds()
    func updateRemoveAdsProvider(_ provider: @escaping () -> Bool)
}

/// GoogleMobileAds.InterstitialAd をテスト可能にするための薄い抽象化
protocol InterstitialAdPresentable: AnyObject, FullScreenPresentingAd {
    var fullScreenContentDelegate: FullScreenContentDelegate? { get set }
    func present(from viewController: UIViewController)
}

extension InterstitialAd: InterstitialAdPresentable {
    // MARK: - GoogleMobileAds.InterstitialAd をプロトコル経由で扱うための橋渡し
    /// GoogleMobileAds 側の `present(from:)` をアプリ内のインターフェースに合わせてラップする
    /// - Parameter viewController: 表示元となる最前面の ViewController
    func present(from viewController: UIViewController) {
        // SDK 本体のメソッドを直接呼び出し、ラッパー側での再帰呼び出しを防ぐ
        // （`FullScreenPresentingAd` プロトコルが提供する fromRootViewController ラベルを利用）
        present(from: viewController) 
    }
}

/// インタースティシャル広告のロード処理を差し替え可能にする
protocol InterstitialAdLoading {
    func load(adUnitID: String, request: GoogleMobileAds.Request, completion: @escaping (InterstitialAdPresentable?, Error?) -> Void)
}

/// 実機用の標準ローダー
struct DefaultInterstitialAdLoader: InterstitialAdLoading {
    func load(adUnitID: String, request: GoogleMobileAds.Request, completion: @escaping (InterstitialAdPresentable?, Error?) -> Void) {
        // API の引数ラベル変更に合わせ、`withAdUnitID` ではなく `with` を使用する
        InterstitialAd.load(with: adUnitID, request: request) { ad, error in
            completion(ad, error)
        }
    }
}

// MARK: - 本体実装
@MainActor
final class InterstitialAdController: NSObject, InterstitialAdControlling {
    weak var delegate: InterstitialAdControllerDelegate?

    private let adUnitID: String
    private let hasValidAdConfiguration: Bool
    private var consentState: AdsConsentState
    private let loader: InterstitialAdLoading
    private let retryDelay: TimeInterval
    private let minimumInterval: TimeInterval
    private var removeAdsProvider: () -> Bool = { false }

    private var interstitial: InterstitialAdPresentable?
    private var lastInterstitialDate: Date?
    private var hasShownInCurrentPlay: Bool = false
    private var isLoadingAd: Bool = false
    private var isWaitingForPresentation: Bool = false
    private var retryTask: Task<Void, Never>?
    private(set) var areAdsDisabled: Bool = false

    init(
        adUnitID: String,
        hasValidAdConfiguration: Bool,
        initialConsentState: AdsConsentState,
        loader: InterstitialAdLoading = DefaultInterstitialAdLoader(),
        retryDelay: TimeInterval = 30,
        minimumInterval: TimeInterval = 300
    ) {
        self.adUnitID = adUnitID
        self.hasValidAdConfiguration = hasValidAdConfiguration
        self.consentState = initialConsentState
        self.loader = loader
        self.retryDelay = retryDelay
        self.minimumInterval = minimumInterval
        super.init()
    }

    deinit {
        retryTask?.cancel()
    }

    func updateRemoveAdsProvider(_ provider: @escaping () -> Bool) {
        removeAdsProvider = provider
    }

    func beginInitialLoad() {
        guard !areAdsDisabled else { return }
        loadInterstitial()
    }

    func showInterstitial() {
        guard hasValidAdConfiguration else {
            debugLog("Info.plist の広告設定が不足しているためインタースティシャル広告の表示を行いません")
            return
        }

        if areAdsDisabled || removeAdsProvider() {
            debugLog("広告が無効化されているため表示処理をスキップしました")
            return
        }

        guard consentState.canRequestAds else {
            debugLog("Google UMP の状態により広告リクエストが許可されていません (canRequestAds: \(consentState.canRequestAds))")
            return
        }

        guard canShowByTime() else {
            debugLog("前回表示から最低インターバルを満たしていないため広告を表示しません")
            return
        }

        guard !hasShownInCurrentPlay else {
            debugLog("同一プレイで既に広告を表示済みのためスキップしました")
            return
        }

        guard let root = delegate?.rootViewControllerForPresentation(self) else {
            debugLog("RootViewController の取得に失敗したため読み込みのみ再実行します")
            triggerAsyncReload()
            return
        }

        guard let interstitial else {
            debugLog("広告が未ロードのため表示待機フラグを設定し再読み込みします")
            isWaitingForPresentation = true
            triggerAsyncReload()
            return
        }

        debugLog("インタースティシャル広告の表示を開始します")
        presentInterstitial(interstitial, from: root)
    }

    func resetPlayFlag() {
        hasShownInCurrentPlay = false
        debugLog("プレイ開始に合わせて広告表示フラグをリセットしました")
    }

    func disableAds() {
        guard !areAdsDisabled else {
            debugLog("広告機能は既に無効化済みのため追加処理を行いません")
            return
        }
        areAdsDisabled = true
        isWaitingForPresentation = false
        interstitial = nil
        retryTask?.cancel()
        retryTask = nil
        debugLog("広告機能を無効化しました。今後のリクエストを停止します")
    }

    func adsConsentCoordinator(_ coordinator: AdsConsentCoordinating, didUpdate state: AdsConsentState, shouldReloadAds: Bool) {
        consentState = state
        if shouldReloadAds {
            interstitial = nil
            loadInterstitial()
            return
        }

        if state.canRequestAds && interstitial == nil && !isLoadingAd {
            loadInterstitial()
        }
    }

    // MARK: - FullScreenContentDelegate
    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        triggerAsyncReload()
        debugLog("インタースティシャル広告を閉じたため次の読み込みを開始します")
    }

    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        lastInterstitialDate = Date()
        hasShownInCurrentPlay = true
        debugLog("インタースティシャル広告の表示準備が完了したためインターバル制御を更新しました")
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        debugError(error, message: "インタースティシャル広告の表示に失敗")
        interstitial = nil
        hasShownInCurrentPlay = false
        isWaitingForPresentation = !areAdsDisabled && !removeAdsProvider()
        scheduleRetry()
    }

    // MARK: - 内部処理
    private func triggerAsyncReload() {
        Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.loadInterstitial() }
        }
    }

    private func loadInterstitial() {
        guard hasValidAdConfiguration else {
            debugLog("Info.plist の広告設定が不足しているためインタースティシャル広告の読み込みを行いません")
            return
        }

        guard consentState.canRequestAds else {
            debugLog("Google UMP の状態により広告リクエストが許可されていません (canRequestAds: \(consentState.canRequestAds))")
            return
        }

        guard !areAdsDisabled else {
            debugLog("adsDisabled フラグが立っているため広告読み込みをスキップしました")
            return
        }

        guard !removeAdsProvider() else {
            debugLog("広告削除オプションが有効なため広告読み込みをスキップしました")
            return
        }

        guard !isLoadingAd else {
            debugLog("インタースティシャル広告を読み込み中のため二重リクエストを防ぎました")
            return
        }

        guard interstitial == nil else {
            debugLog("既にキャッシュ済みのインタースティシャルが存在するため新規読み込みを行いません")
            return
        }

        debugLog("インタースティシャル広告の読み込みを開始します (NPA: \(consentState.shouldUseNPA))")
        isLoadingAd = true

        let request = GoogleMobileAds.Request()
        if consentState.shouldUseNPA {
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
        }

        loader.load(adUnitID: adUnitID, request: request) { [weak self] ad, error in
            Task { [weak self] in
                guard let self else { return }
                await self.handleLoadResult(ad: ad, error: error)
            }
        }
    }

    private func handleLoadResult(ad: InterstitialAdPresentable?, error: Error?) async {
        isLoadingAd = false

        if let error {
            debugError(error, message: "インタースティシャル広告の読み込みに失敗")
            scheduleRetry()
            return
        }

        guard !areAdsDisabled, !removeAdsProvider() else { return }
        interstitial = ad
        interstitial?.fullScreenContentDelegate = self
        retryTask?.cancel()
        retryTask = nil
        debugLog("インタースティシャル広告の読み込みが完了しました")
        presentInterstitialIfNeededAfterLoad()
    }

    private func presentInterstitial(_ interstitial: InterstitialAdPresentable, from root: UIViewController) {
        isWaitingForPresentation = false
        self.interstitial = nil
        interstitial.present(from: root)
        delegate?.interstitialAdControllerShouldPlayWarningHaptic(self)
        debugLog("インタースティシャル広告の表示処理をトリガーしました")
    }

    private func presentInterstitialIfNeededAfterLoad() {
        guard isWaitingForPresentation else { return }
        debugLog("読み込み完了後の自動表示処理を開始します")

        guard !areAdsDisabled, !removeAdsProvider() else {
            isWaitingForPresentation = false
            interstitial = nil
            debugLog("広告が無効化されているため自動表示を取りやめました")
            return
        }

        guard let interstitial else {
            debugLog("インタースティャル広告の表示待機中に広告インスタンスが破棄されたため、再読み込みを実行します")
            loadInterstitial()
            return
        }

        guard let root = delegate?.rootViewControllerForPresentation(self) else {
            debugLog("インタースティシャル広告の表示待機中でしたが RootViewController が取得できませんでした。再読み込みして次回に備えます")
            self.interstitial = nil
            loadInterstitial()
            return
        }

        debugLog("読み込み完了直後にインタースティシャル広告を自動表示します")
        presentInterstitial(interstitial, from: root)
    }

    private func scheduleRetry() {
        guard !areAdsDisabled else { return }
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            guard let self else { return }
            let delay = UInt64(self.retryDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            await MainActor.run { self.loadInterstitial() }
        }
        debugLog("インタースティシャル広告の再読み込みを \(retryDelay) 秒後にスケジュールしました")
    }

    private func canShowByTime() -> Bool {
        guard let lastInterstitialDate else { return true }
        return Date().timeIntervalSince(lastInterstitialDate) >= minimumInterval
    }
}
