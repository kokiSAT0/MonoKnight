import Foundation
import GoogleMobileAds
import UIKit
import SwiftUI
import AppTrackingTransparency
import UserMessagingPlatform

/// インタースティシャル広告を管理するサービス
/// ゲーム終了時に ResultView から呼び出される
final class AdsService: NSObject, ObservableObject {
    /// シングルトンインスタンス
    static let shared = AdsService()

    /// 環境変数から取得したテスト用インタースティシャル ID
    /// - 値が存在する場合は Google SDK を利用せずプレースホルダーを表示する
    private let testInterstitialID = ProcessInfo.processInfo.environment["GAD_INTERSTITIAL_ID"]

    /// テストモードであるかを判定するフラグ
    private var isTestMode: Bool { testInterstitialID != nil }

    /// ロード済みのインタースティシャル広告
    private var interstitial: GADInterstitialAd?

    /// 広告除去購入済みフラグ（UserDefaults と連携）
    @AppStorage("remove_ads") private var removeAds: Bool = false

    /// ATT と UMP の同意状況に基づくパーソナライズ可否
    private var isPersonalized: Bool = false

    /// 最後に広告を表示した時刻
    private var lastInterstitialDate: Date?

    /// 1 プレイ内で既に表示したかどうか
    private var hasShownInCurrentPlay: Bool = false

    private override init() {
        super.init()
        // テストモードでは SDK を使わないため初期化のみで終了
        guard !isTestMode else { return }

        // 非同期で ATT と UMP の同意を取得してから広告を読み込む
        Task {
            await requestTrackingAuthorization()
            await requestConsentIfNeeded()
            if !removeAds {
                loadInterstitial()
            }
        }
    }

    /// ATT の許諾ダイアログを表示（初回のみ）
    private func requestTrackingAuthorization() async {
        // 既に選択済みであれば何もしない
        guard ATTrackingManager.trackingAuthorizationStatus == .notDetermined else { return }
        // ユーザーに許可を求める
        _ = await ATTrackingManager.requestTrackingAuthorization()
    }

    /// UMP 同意フォームを表示してパーソナライズ可否を更新
    private func requestConsentIfNeeded() async {
        let parameters = UMPRequestParameters()
        // 13 歳未満ではないので false
        parameters.tagForUnderAgeOfConsent = false

        let consentInfo = UMPConsentInformation.sharedInstance
        do {
            // 同意情報を取得
            try await withCheckedThrowingContinuation { continuation in
                consentInfo.requestConsentInfoUpdate(with: parameters) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
        } catch {
            // 取得に失敗した場合は非パーソナライズ扱い
            print("同意情報の取得に失敗: \(error.localizedDescription)")
            isPersonalized = false
            return
        }

        // フォームが必要であれば表示
        if consentInfo.formStatus == .available {
            do {
                let form = try await withCheckedThrowingContinuation { continuation in
                    UMPConsentForm.load { form, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let form {
                            continuation.resume(returning: form)
                        }
                    }
                }

                // ルートビューコントローラを取得して表示
                if let root = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first?.windows.first?.rootViewController {
                    try await withCheckedThrowingContinuation { continuation in
                        form.present(from: root) { error in
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                    }
                }
            } catch {
                // 表示に失敗しても処理は続行
                print("同意フォームの表示に失敗: \(error.localizedDescription)")
            }
        }

        // 最終的な同意結果を反映
        isPersonalized = (consentInfo.consentStatus == .obtained)
    }

    /// インタースティシャル広告を読み込む
    private func loadInterstitial() {
        // 広告除去購入済み または テストモードのときは読み込み不要
        guard !removeAds, !isTestMode else { return }

        let request = GADRequest()
        // 非パーソナライズ広告を指定する場合は npa=1 を設定
        if !isPersonalized {
            let extras = GADExtras()
            extras.additionalParameters = ["npa": "1"]
            request.register(extras)
        }

        // テスト用広告ユニット ID（実装時に差し替え）
        GADInterstitialAd.load(withAdUnitID: "ca-app-pub-3940256099942544/4411468910", request: request) { [weak self] ad, error in
            if let error {
                // 読み込み失敗時はログを出力
                print("広告の読み込み失敗: \(error.localizedDescription)")
                return
            }
            // 正常に取得できたら保持
            self?.interstitial = ad
        }
    }

    /// 準備済みの広告があれば表示する
    func showInterstitial() {
        // 購入済み・インターバル未満・1 プレイ 1 回上限の場合は表示しない
        guard !removeAds,
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController,
              canShowByTime(),
              !hasShownInCurrentPlay else { return }

        if isTestMode {
            // --- テストモード ---
            // ダミー広告ビューをモーダルで表示
            let vc = UIHostingController(rootView: DummyInterstitialView())
            vc.modalPresentationStyle = .fullScreen
            root.present(vc, animated: true)
            // 表示後にタイムスタンプとフラグを更新
            lastInterstitialDate = Date()
            hasShownInCurrentPlay = true
            return
        }

        // --- 通常モード ---
        guard let ad = interstitial else { return }
        // 現在のルートビューから広告を表示
        ad.present(fromRootViewController: root)
        // 表示後にタイムスタンプとフラグを更新し、次回に備えて再読み込み
        lastInterstitialDate = Date()
        hasShownInCurrentPlay = true
        interstitial = nil
        loadInterstitial()
    }

    /// 最後の表示から 90 秒以上経過しているか確認
    private func canShowByTime() -> Bool {
        guard let lastInterstitialDate else { return true }
        return Date().timeIntervalSince(lastInterstitialDate) >= 90
    }

    /// 新しいプレイ開始時に 1 回表示フラグをリセットする
    func resetPlayFlag() {
        hasShownInCurrentPlay = false
    }

    /// 購入済みのときに既存広告を破棄し、以降読み込まないようにする
    func disableAds() {
        interstitial = nil
    }
}

/// テストモードで表示するプレースホルダー広告ビュー
/// 実際の広告 SDK を利用せず、UI テスト用の簡易表示を提供する
private struct DummyInterstitialView: View {
    /// 表示を閉じるための dismiss アクション
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // 背景は黒一色で実広告を模倣
            Color.black
            // 画面中央にテキストを配置
            Text("Test Ad")
                .foregroundColor(.white)
        }
        .ignoresSafeArea()
        // UI テストから参照するための識別子
        .accessibilityIdentifier("dummy_interstitial_ad")
        // タップで閉じる
        .onTapGesture {
            dismiss()
        }
    }
}
