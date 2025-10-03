import Foundation
import UIKit
import GoogleMobileAds
import SharedSupport // ログユーティリティを利用するため追加

// MARK: - デリゲート定義
/// リワード広告を表示する際に UI 依存の処理を委譲するためのプロトコル
@MainActor
protocol RewardedAdControllerDelegate: AnyObject {
    /// 表示に利用する最前面の ViewController を提供する
    func rootViewControllerForPresentation(_ controller: RewardedAdControlling) -> UIViewController?
}

// MARK: - 管理用インターフェース
/// リワード広告のロード・表示を統一インターフェースで扱うためのプロトコル
@MainActor
protocol RewardedAdControlling: AnyObject, FullScreenContentDelegate, AdsConsentCoordinatorStateDelegate {
    var delegate: RewardedAdControllerDelegate? { get set }

    /// 初期表示に備えて広告を読み込み、必要ならば再度ロードする
    func prepareInitialLoad()
    /// リワード広告を表示し、視聴完了で報酬が得られたかどうかを返す
    func showRewardedAd() async -> Bool
    /// 広告機能全体を停止する（IAP による広告除去対応など）
    func disableAds()
    /// removeAds フラグ取得用クロージャを登録する
    func updateRemoveAdsProvider(_ provider: @escaping () -> Bool)
}

// MARK: - GMA SDK を抽象化する薄いラッパー
protocol RewardedAdPresentable: AnyObject, FullScreenPresentingAd {
    var fullScreenContentDelegate: FullScreenContentDelegate? { get set }
    /// SDK 本体の `present(from:)` 呼び出しをラップし、名称衝突による無限再帰を避けるための独自シグネチャ
    func presentAd(from viewController: UIViewController, userDidEarnRewardHandler: @escaping () -> Void)
}

extension RewardedAd: RewardedAdPresentable {
    func presentAd(from viewController: UIViewController, userDidEarnRewardHandler: @escaping () -> Void) {
        // MARK: - SDK メソッドへの委譲
        // Google Mobile Ads SDK の `RewardedAd` が提供する正式な API を明示的に指定することで、
        // プロトコル拡張内の同名メソッドを誤って再帰的に呼び出すリスクを排除する
        (self as GoogleMobileAds.RewardedAd).present(
            fromRootViewController: viewController,
            userDidEarnRewardHandler: {
                // SDK 側のクロージャは引数を伴わないため、報酬獲得時に受け取ったハンドラーをそのまま呼び出す
                userDidEarnRewardHandler()
            }
        )
    }
}

/// リワード広告の読み込みを切り替え可能にするためのプロトコル
protocol RewardedAdLoading {
    func load(adUnitID: String, request: GoogleMobileAds.Request, completion: @escaping (RewardedAdPresentable?, Error?) -> Void)
}

/// 実機用のデフォルトローダー
struct DefaultRewardedAdLoader: RewardedAdLoading {
    func load(adUnitID: String, request: GoogleMobileAds.Request, completion: @escaping (RewardedAdPresentable?, Error?) -> Void) {
        RewardedAd.load(with: adUnitID, request: request) { ad, error in
            completion(ad, error)
        }
    }
}

// MARK: - 本体実装
@MainActor
final class RewardedAdController: NSObject, RewardedAdControlling {
    weak var delegate: RewardedAdControllerDelegate?

    private let adUnitID: String
    private let hasValidAdConfiguration: Bool
    private var consentState: AdsConsentState
    private let loader: RewardedAdLoading
    private var removeAdsProvider: () -> Bool = { false }

    private var rewardedAd: RewardedAdPresentable?
    private var isLoadingAd: Bool = false
    private var areAdsDisabled: Bool = false
    private var pendingContinuation: CheckedContinuation<Bool, Never>?
    private var didEarnRewardInCurrentPresentation: Bool = false

    init(
        adUnitID: String,
        hasValidAdConfiguration: Bool,
        initialConsentState: AdsConsentState,
        loader: RewardedAdLoading = DefaultRewardedAdLoader()
    ) {
        self.adUnitID = adUnitID
        self.hasValidAdConfiguration = hasValidAdConfiguration
        self.consentState = initialConsentState
        self.loader = loader
        super.init()
    }

    deinit {
        pendingContinuation?.resume(returning: false)
        pendingContinuation = nil
    }

    func prepareInitialLoad() {
        loadIfNeeded()
    }

    func showRewardedAd() async -> Bool {
        guard hasValidAdConfiguration else {
            debugLog("RewardedAdController: Info.plist にリワード広告の設定が不足しているため表示を行いません")
            return false
        }

        guard !areAdsDisabled, !removeAdsProvider() else {
            debugLog("RewardedAdController: 広告が無効化されているためリワード広告を表示しません")
            return false
        }

        guard consentState.canRequestAds else {
            debugLog("RewardedAdController: UMP の状態により広告リクエストが禁止されているため表示できません")
            return false
        }

        guard let root = delegate?.rootViewControllerForPresentation(self) else {
            debugLog("RewardedAdController: 表示に利用できる ViewController が見つからなかったためリトライを予約します")
            triggerReload()
            return false
        }

        guard let rewardedAd else {
            debugLog("RewardedAdController: リワード広告が未ロードのため表示できません。再読み込みを実行します")
            triggerReload()
            return false
        }

        didEarnRewardInCurrentPresentation = false
        self.rewardedAd = nil
        rewardedAd.fullScreenContentDelegate = self

        return await withCheckedContinuation { continuation in
            pendingContinuation = continuation
            debugLog("RewardedAdController: リワード広告の表示を開始します")
            // `presentAd` は SDK の `present(from:)` へ橋渡しする独自ラッパーであり、メソッド名衝突による無限再帰を防ぐ
            rewardedAd.presentAd(from: root) { [weak self] in
                self?.didEarnRewardInCurrentPresentation = true
                debugLog("RewardedAdController: ユーザーが報酬条件を満たしました")
            }
        }
    }

    func disableAds() {
        guard !areAdsDisabled else { return }
        areAdsDisabled = true
        rewardedAd = nil
        pendingContinuation?.resume(returning: false)
        pendingContinuation = nil
        debugLog("RewardedAdController: 広告機能を無効化したため以後のリワード広告読み込みを停止します")
    }

    func updateRemoveAdsProvider(_ provider: @escaping () -> Bool) {
        removeAdsProvider = provider
    }

    func adsConsentCoordinator(_ coordinator: AdsConsentCoordinating, didUpdate state: AdsConsentState, shouldReloadAds: Bool) {
        consentState = state
        if shouldReloadAds {
            rewardedAd = nil
            loadIfNeeded(force: true)
            return
        }

        if state.canRequestAds && rewardedAd == nil && !isLoadingAd {
            loadIfNeeded()
        }
    }

    // MARK: - FullScreenContentDelegate
    func adWillPresentFullScreenContent(_ ad: FullScreenPresentingAd) {
        debugLog("RewardedAdController: リワード広告の表示準備が完了しました")
    }

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        pendingContinuation?.resume(returning: didEarnRewardInCurrentPresentation)
        pendingContinuation = nil
        debugLog("RewardedAdController: リワード広告を閉じたため次の読み込みを開始します")
        triggerReload()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        debugError(error, message: "RewardedAdController: リワード広告の表示に失敗しました")
        pendingContinuation?.resume(returning: false)
        pendingContinuation = nil
        triggerReload()
    }

    // MARK: - 内部処理
    private func loadIfNeeded(force: Bool = false) {
        guard hasValidAdConfiguration else { return }
        guard consentState.canRequestAds else { return }
        guard !areAdsDisabled else { return }
        guard !removeAdsProvider() else { return }
        guard force || rewardedAd == nil else { return }
        guard !isLoadingAd else { return }

        debugLog("RewardedAdController: リワード広告の読み込みを開始します (NPA: \(consentState.shouldUseNPA))")
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

    private func handleLoadResult(ad: RewardedAdPresentable?, error: Error?) async {
        isLoadingAd = false

        if let error {
            debugError(error, message: "RewardedAdController: リワード広告の読み込みに失敗しました")
            return
        }

        guard !areAdsDisabled, !removeAdsProvider() else { return }
        rewardedAd = ad
        debugLog("RewardedAdController: リワード広告の読み込みが完了しました")
    }

    private func triggerReload() {
        guard !areAdsDisabled else { return }
        Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.loadIfNeeded(force: true) }
        }
    }
}
