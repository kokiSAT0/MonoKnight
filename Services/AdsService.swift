import Foundation
import SwiftUI
import UIKit
import AppTrackingTransparency
import GoogleMobileAds
// ログ出力ユーティリティを利用するため共有モジュールを読み込む
import SharedSupport

// MARK: - Protocol
// AdsServiceProtocol 自体は `ServiceInterfaces.swift` で共通定義しているため、ここでは実装のみを記述する。

// MARK: - 補助的な依存関係
/// Google Mobile Ads SDK の初期化処理を差し替えやすくするためのプロトコル
protocol MobileAdsControlling {
    func start(completion: @escaping () -> Void)
}

/// 実機用の初期化ラッパー
struct DefaultMobileAdsController: MobileAdsControlling {
    func start(completion: @escaping () -> Void) {
        MobileAds.shared.start { _ in completion() }
    }
}

// MARK: - ATT 許諾状態取得用の抽象化
/// AppTrackingTransparency の状態取得とリクエストを統一インターフェースで扱うためのプロトコル
protocol TrackingAuthorizationControlling {
    /// 現時点のトラッキング許諾ステータス
    var currentStatus: ATTrackingManager.AuthorizationStatus { get }
    /// 許諾ダイアログを表示し、結果をコールバックへ返す
    func requestAuthorization(completion: @escaping (ATTrackingManager.AuthorizationStatus) -> Void)
}

/// 実機向けのデフォルト実装
struct DefaultTrackingAuthorizationController: TrackingAuthorizationControlling {
    var currentStatus: ATTrackingManager.AuthorizationStatus { ATTrackingManager.trackingAuthorizationStatus }

    func requestAuthorization(completion: @escaping (ATTrackingManager.AuthorizationStatus) -> Void) {
        ATTrackingManager.requestTrackingAuthorization { status in
            completion(status)
        }
    }
}

// MARK: - ルート ViewController 取得用の抽象化
/// UI テストや統合テストからも差し替えやすいよう、最前面の ViewController を提供する依存を切り出す
protocol RootViewControllerProviding {
    /// インタースティシャル表示や UMP 同意フォーム表示に利用する最前面 ViewController を返す
    func topViewController() -> UIViewController?
}

/// UIApplication の階層を辿って最前面の ViewController を解決するデフォルト実装
struct DefaultRootViewControllerProvider: RootViewControllerProviding {
    func topViewController() -> UIViewController? {
        // シーン階層が取得できないケースでは即座に nil を返し、呼び出し元でリトライさせる
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }

        // isKeyWindow を優先しつつ、fallback として最初のウィンドウも見る（マルチウィンドウ環境を考慮）
        let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        guard let rootController = window?.rootViewController else { return nil }

        // ルートから辿れる最前面の ViewController を再帰的に探索する
        return topMostViewController(from: rootController)
    }

    /// ナビゲーション/タブ/モーダル等のコンテナを考慮して最前面の VC を返す
    private func topMostViewController(from controller: UIViewController?) -> UIViewController? {
        guard let controller else { return nil }

        // モーダルで提示されている場合は更に深い階層を優先する
        if let presented = controller.presentedViewController {
            return topMostViewController(from: presented)
        }

        // ナビゲーションコントローラは表示中の VC（visibleViewController）を優先
        if let navigation = controller as? UINavigationController {
            return topMostViewController(from: navigation.visibleViewController ?? navigation.topViewController)
        }

        // タブコントローラは選択中のタブ配下を辿る
        if let tab = controller as? UITabBarController {
            return topMostViewController(from: tab.selectedViewController)
        }

        // SplitViewController も最後尾（詳細側）を表示中とみなし辿る
        if let split = controller as? UISplitViewController {
            return topMostViewController(from: split.viewControllers.last)
        }

        // それ以外は最前面の具体的な VC として返却
        return controller
    }
}

/// Info.plist 由来の設定値をまとめる構造体
struct AdsServiceConfiguration {
    let interstitialAdUnitID: String
    let hasValidAdConfiguration: Bool
}

// MARK: - Google Mobile Ads 実装
@MainActor
final class AdsService: NSObject, ObservableObject, AdsServiceProtocol {
    /// Info.plist に定義するキー名をまとめる
    private enum InfoPlistKey {
        static let applicationIdentifier = "GADApplicationIdentifier"
        static let interstitialAdUnitID = "GADInterstitialAdUnitID"
    }

    /// シングルトンでサービスを共有
    static let shared = AdsService()

    @AppStorage("remove_ads_mk") private var removeAdsMK: Bool = false
    @AppStorage("haptics_enabled") private var hapticsEnabled: Bool = true

    private let consentCoordinator: AdsConsentCoordinating
    private let interstitialController: InterstitialAdControlling
    private let mobileAdsController: MobileAdsControlling
    private let trackingAuthorizationController: TrackingAuthorizationControlling
    private let configuration: AdsServiceConfiguration
    private let rootViewControllerProvider: RootViewControllerProviding

    /// 生成直後に依存関係を注入できるよう DI 対応したイニシャライザを用意する
    init(
        configuration: AdsServiceConfiguration? = nil,
        consentCoordinator: AdsConsentCoordinating? = nil,
        interstitialController: InterstitialAdControlling? = nil,
        mobileAdsController: MobileAdsControlling = DefaultMobileAdsController(),
        trackingAuthorizationController: TrackingAuthorizationControlling = DefaultTrackingAuthorizationController(),
        rootViewControllerProvider: RootViewControllerProviding = DefaultRootViewControllerProvider()
    ) {
        let resolvedConfiguration = configuration ?? AdsService.makeConfiguration()
        let resolvedTrackingController = trackingAuthorizationController
        let resolvedConsentCoordinator = consentCoordinator ?? AdsConsentCoordinator(
            hasValidAdConfiguration: resolvedConfiguration.hasValidAdConfiguration,
            environment: nil,
            trackingAuthorizationStatusProvider: { resolvedTrackingController.currentStatus }
        )
        let resolvedInterstitialController = interstitialController ?? InterstitialAdController(
            adUnitID: resolvedConfiguration.interstitialAdUnitID,
            hasValidAdConfiguration: resolvedConfiguration.hasValidAdConfiguration,
            initialConsentState: resolvedConsentCoordinator.currentState
        )

        self.configuration = resolvedConfiguration
        self.consentCoordinator = resolvedConsentCoordinator
        self.interstitialController = resolvedInterstitialController
        self.mobileAdsController = mobileAdsController
        self.trackingAuthorizationController = resolvedTrackingController
        self.rootViewControllerProvider = rootViewControllerProvider
        super.init()

        // デリゲートを接続して UI 連携と状態同期を AdsService 側で担う
        self.interstitialController.delegate = self
        self.interstitialController.updateRemoveAdsProvider { [weak self] in
            self?.removeAdsMK ?? false
        }
        self.consentCoordinator.presentationDelegate = self
        self.consentCoordinator.stateDelegate = self.interstitialController

        // IAP による広告除去が永続化されている場合は、初期化直後から広告のロードを完全に停止する
        if removeAdsMK {
            self.interstitialController.disableAds()
            debugLog("広告除去オプションが有効なため AdMob SDK のロード処理をスキップします")
        }

        guard self.configuration.hasValidAdConfiguration else { return }
        guard !self.interstitialController.areAdsDisabled else { return }

        // SDK 初期化。v11 以降では `GADMobileAds` が `MobileAds` に改名されたため、shared プロパティから最新 API を取得する。
        // （名称変更に追従しつつ、将来的な API 差分を把握しやすくする意図で明示的にコメントを残している）
        mobileAdsController.start { [weak self] in
            guard self != nil else {
                // self が解放されている場合はログのみ出力を省略し、不要な処理を避ける
                return
            }
            debugLog("Google Mobile Ads SDK の初期化が完了しました")
        }

        // 初期化直後から広告読み込みを開始（非同期で走らせる）
        Task { [weak self] in
            // beginInitialLoad() 自体は同期関数のため await は不要。Task 内で呼び出すだけで初回ロードを開始できる。
            self?.interstitialController.beginInitialLoad()
        }

        // 起動直後は UMP の同意情報と shouldUseNPA の値がずれている恐れがあるため、明示的に同期処理を差し込む
        Task { [weak self] in
            await self?.consentCoordinator.synchronizeOnLaunch()
        }
    }

    /// シングルトン利用時は Info.plist から設定を取得する
    private override convenience init() {
        self.init(
            configuration: nil,
            consentCoordinator: nil,
            interstitialController: nil,
            mobileAdsController: DefaultMobileAdsController(),
            rootViewControllerProvider: DefaultRootViewControllerProvider()
        )
    }

    func showInterstitial() {
        interstitialController.showInterstitial()
    }

    func resetPlayFlag() {
        interstitialController.resetPlayFlag()
    }

    func disableAds() {
        interstitialController.disableAds()
    }

    func requestTrackingAuthorization() async {
        let currentStatus = trackingAuthorizationController.currentStatus
        // 既に許諾済みであればリフレッシュのみ行う
        if currentStatus != .notDetermined {
            if currentStatus == .authorized {
                await consentCoordinator.refreshConsentStatus()
            }
            return
        }

        // ATT の許諾ダイアログはクロージャベース API のため、Continuation で async/await へ橋渡しする
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<ATTrackingManager.AuthorizationStatus, Never>) in
            trackingAuthorizationController.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        if status == .authorized {
            await consentCoordinator.refreshConsentStatus()
        } else {
            debugLog("ATT 許諾が得られなかったため NPA 維持で進行します (status: \(describeTrackingStatus(status)))")
        }
    }

    func requestConsentIfNeeded() async {
        await consentCoordinator.requestConsentIfNeeded()
    }

    func refreshConsentStatus() async {
        await consentCoordinator.refreshConsentStatus()
    }

    func presentRewardedAd(for placement: AdsRewardPlacement) async -> Bool {
        debugLog("リワード広告 API は未実装のためダミー結果を返却 placement=\(placement.rawValue)")
        return false
    }

    /// Info.plist を読み取り、広告設定が揃っているかどうかを返す
    private static func makeConfiguration() -> AdsServiceConfiguration {
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

        let hasValid = !applicationIdentifier.isEmpty && !interstitialIdentifier.isEmpty
        return AdsServiceConfiguration(interstitialAdUnitID: interstitialIdentifier, hasValidAdConfiguration: hasValid)
    }

    /// デバッグログ用に ATT ステータスを文字列化するヘルパー
    private func describeTrackingStatus(_ status: ATTrackingManager.AuthorizationStatus) -> String {
        switch status {
        case .authorized:
            return "authorized"
        case .notDetermined:
            return "notDetermined"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        @unknown default:
            return "unknown"
        }
    }
}

// MARK: - AdsConsentCoordinatorPresenting
extension AdsService: AdsConsentCoordinatorPresenting {
    func presentConsentForm(using presenter: @escaping ConsentFormPresenter) async throws {
        guard let viewController = rootViewControllerProvider.topViewController() else {
            let error = NSError(
                domain: "MonoKnight.AdsService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "UMP 同意フォームを表示するための ViewController 取得に失敗"]
            )
            throw error
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            presenter(viewController) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func presentPrivacyOptions(using presenter: @escaping PrivacyOptionsPresenter) async throws {
        guard let viewController = rootViewControllerProvider.topViewController() else {
            let error = NSError(
                domain: "MonoKnight.AdsService",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "UMP Privacy Options を表示できる ViewController が見つかりません"]
            )
            throw error
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            presenter(viewController) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

// MARK: - InterstitialAdControllerDelegate
extension AdsService: InterstitialAdControllerDelegate {
    func rootViewControllerForPresentation(_ controller: InterstitialAdControlling) -> UIViewController? {
        rootViewControllerProvider.topViewController()
    }

    func interstitialAdControllerShouldPlayWarningHaptic(_ controller: InterstitialAdControlling) {
        guard hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
