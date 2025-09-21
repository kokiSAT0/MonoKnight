import Foundation
import UIKit
import SwiftUI
import AppTrackingTransparency
import GoogleMobileAds
import UserMessagingPlatform
// ログ出力ユーティリティを利用するため Game モジュールを読み込む
import Game

// MARK: - Protocol
/// UI レイヤーからメインスレッド経由で利用する前提のため、プロトコル自体も MainActor に固定する
@MainActor
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
    private var interstitial: InterstitialAd?
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
    /// UMP の同意フォームを保持する参照
    private var consentForm: ConsentForm?

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

        // SDK 初期化。v11 以降では `GADMobileAds` が `MobileAds` に改名されたため、shared プロパティから最新 API を取得する。
        // （名称変更に追従しつつ、将来的な API 差分を把握しやすくする意図で明示的にコメントを残している）
        let mobileAds = MobileAds.shared

        // Swift 6 では completionHandler に nil を渡すと型推論ができずビルドエラーになるため、
        // ここでは何もしない空クロージャを渡して初期化を完了させる。
        mobileAds.start { _ in
            // 現時点では初期化結果を利用しないが、将来的にログ出力やイベント送信を追加できるよう空実装としておく。
        }

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
        // Info.plist 側の設定が揃っていない場合はフォーム表示を行わない
        guard hasValidAdConfiguration else { return }

        do {
            // まずは地域規制の判定を最新化
            try await requestConsentInfoUpdate()
            // 同意状態に応じて NPA フラグを更新し、広告リクエストへ反映させる
            applyConsentStatusAndReloadIfNeeded()

            let consentInfo = UMPConsentInformation.shared
            // 同意フォームが利用可能な場合のみロードと表示を行う
            guard consentInfo.formStatus == .available else { return }

            // 最新のフォームをロード
            consentForm = try await loadConsentForm()

            // 規制対象地域かつ同意が未取得の場合はフォームを提示
            if consentInfo.consentStatus == .required || consentInfo.consentStatus == .unknown {
                try await presentLoadedConsentForm()
                // 表示後に同意内容が更新されるため再評価する
                applyConsentStatusAndReloadIfNeeded()
            }
        } catch {
            // UMP 周りの失敗は広告表示を止めつつ、デバッグしやすいようログに残す
            debugError(error, message: "Google UMP の同意取得に失敗")
        }
    }

    func refreshConsentStatus() async {
        // Info.plist の設定が不足している場合は処理しない
        guard hasValidAdConfiguration else { return }

        do {
            // 現在の同意状況を最新化
            try await requestConsentInfoUpdate()
            applyConsentStatusAndReloadIfNeeded()

            let consentInfo = UMPConsentInformation.shared
            guard consentInfo.formStatus == .available else { return }

            // 設定画面などから呼び出された際は Privacy Options を直接表示する
            try await presentPrivacyOptions()
            // ユーザー操作後の状態を反映する
            applyConsentStatusAndReloadIfNeeded()
        } catch {
            debugError(error, message: "Google UMP の同意状態更新に失敗")
        }
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

        interstitial.present(from: root)
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
              UMPConsentInformation.shared.canRequestAds,
              !adsDisabled,
              !removeAds,
              !isLoadingAd,
              interstitial == nil else { return }

        isLoadingAd = true

        // Google Mobile Ads SDK v11 以降では `GADRequest` が `Request` に改名されたため、明示的に名前空間を付けて生成する
        // （同名型との衝突を避け、将来の API 変更にも備える目的で `GoogleMobileAds.Request()` を利用）
        let request = GoogleMobileAds.Request()
        if shouldUseNPA {
            // UMP の結果に従い非パーソナライズ広告をリクエスト
            let extras = Extras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
        }

        InterstitialAd.load(with: interstitialAdUnitID, request: request) { [weak self] ad, error in
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
            // Task 実行時点で self が解放されていないことを確認し、以降は強参照で扱う
            guard let self else { return }

            // 秒数からナノ秒に変換し、一定時間後に再読み込みを試みる
            let delay = UInt64(self.retryDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)

            // MainActor 上でインタースティシャルの読み込みを再開
            await MainActor.run { self.loadInterstitial() }
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

// MARK: - UMP 関連のヘルパー

private extension AdsService {
    /// UMP の同意情報を最新化する
    func requestConsentInfoUpdate() async throws {
        // 未成年向けコンテンツではないため、isTaggedForUnderAgeOfConsent を false に固定する
        let parameters = UMPRequestParameters()
        parameters.isTaggedForUnderAgeOfConsent = false

#if DEBUG
        // テスト中は常に EEA として扱い、フォームを確認しやすくする
        let debugSettings = UMPDebugSettings()
        debugSettings.geography = .EEA
        parameters.debugSettings = debugSettings
#endif

        let consentInfo = UMPConsentInformation.shared

        try await withCheckedThrowingContinuation { continuation in
            consentInfo.requestConsentInfoUpdate(with: parameters) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// 同意フォームをロードする
    func loadConsentForm() async throws -> ConsentForm {
        try await withCheckedThrowingContinuation { continuation in
            ConsentForm.load { [weak self] form, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let form {
                    continuation.resume(returning: form)
                } else {
                    // フォームもエラーも返らないケースは想定外のため、明示的にエラーを生成する
                    let error = NSError(
                        domain: "MonoKnight.AdsService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "UMP 同意フォームのロード結果が不正"]
                    )
                    continuation.resume(throwing: error)
                }

                // 参照が不要になったフォームは明示的に破棄する
                if self?.consentForm != nil && form == nil {
                    self?.consentForm = nil
                }
            }
        }
    }

    /// ロード済みフォームを現在の RootViewController から表示する
    func presentLoadedConsentForm() async throws {
        guard let viewController = rootViewController(), let consentForm else {
            let error = NSError(
                domain: "MonoKnight.AdsService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "UMP 同意フォームを表示するための ViewController 取得に失敗"]
            )
            throw error
        }

        try await withCheckedThrowingContinuation { continuation in
            consentForm.present(from: viewController) { [weak self] error in
                defer { self?.consentForm = nil }
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// プライバシーオプションを直接表示する
    func presentPrivacyOptions() async throws {
        guard let viewController = rootViewController() else {
            let error = NSError(
                domain: "MonoKnight.AdsService",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "UMP Privacy Options を表示できる ViewController が見つかりません"]
            )
            throw error
        }

        try await withCheckedThrowingContinuation { continuation in
            ConsentForm.presentPrivacyOptionsForm(from: viewController) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    /// 現在の同意ステータスを見て NPA フラグを更新し、必要に応じて広告を再読み込みする
    func applyConsentStatusAndReloadIfNeeded() {
        let consentInfo = UMPConsentInformation.shared
        // 取得済み or 規制対象外の場合のみパーソナライズを許可し、それ以外は安全側として NPA を指定する
        let newShouldUseNPA: Bool
        switch consentInfo.consentStatus {
        case .obtained, .notRequired:
            newShouldUseNPA = false
        default:
            newShouldUseNPA = true
        }

        let hasChanged = newShouldUseNPA != shouldUseNPA
        shouldUseNPA = newShouldUseNPA

        // 値が変わった場合は既存キャッシュを破棄し、新しい設定で広告をロードし直す
        guard hasChanged else { return }
        interstitial = nil
        loadInterstitial()
    }

    /// 最前面の ViewController を取得する
    func rootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return nil }
        return scene.windows.first?.rootViewController
    }
}
