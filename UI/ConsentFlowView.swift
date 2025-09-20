import SwiftUI

/// 初回起動時に表示するオンボーディングビュー
/// 広告・トラッキングに関する説明と同意取得を行う
// Swift 6 のコンカレンシーモデルでは MainActor 以外から AdsService.shared に触れるとエラーになるため、
// ビュー全体を MainActor 管理下に置き、UI 系処理をメインスレッドで扱うことを明示する
@MainActor
struct ConsentFlowView: View {
    /// 広告サービス。ATT/UMP の許諾処理を呼び出す
    private let adsService: AdsServiceProtocol
    /// 同意フローが完了したかどうかを UserDefaults と連携して保持
    @AppStorage("has_completed_consent_flow") private var hasCompletedConsentFlow: Bool = false
    /// 処理中でボタンを無効化するためのフラグ
    @State private var isRequesting: Bool = false

    /// サービスを外部から注入可能にする初期化処理
    /// - Parameter adsService: 広告処理を担うサービス（未指定時はシングルトンを利用）
    /// Swift 6 ではデフォルト引数が非分離コンテキストとして扱われるため、
    /// `AdsService.shared` のような MainActor 隔離プロパティを直接参照するとコンパイルエラーになる。
    /// そのため、引数をオプショナルにして初期化本体でシングルトンを代入するように変更し、
    /// MainActor コンテキスト内で安全に共有インスタンスへアクセスする。
    init(adsService: AdsServiceProtocol? = nil) {
        self.adsService = adsService ?? AdsService.shared
    }

    var body: some View {
        VStack(spacing: 24) {
            // MARK: - 説明テキスト
            // 同意内容を簡潔にユーザーへ伝える
            Text("本アプリでは広告表示のために\nトラッキングとプライバシーに関する\n許諾をお願いしています。")
                .multilineTextAlignment(.center)
                .padding()

            // MARK: - 続行ボタン
            Button(action: {
                // 非同期で同意フローを開始
                Task { await startFlow() }
            }) {
                Text("続行")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRequesting)
        }
        .padding()
    }

    /// ATT → UMP の順に同意ダイアログを表示する
    private func startFlow() async {
        isRequesting = true
        // まずはトラッキング許諾を求める
        await adsService.requestTrackingAuthorization()
        // 続いて Google UMP の同意フォームを表示
        await adsService.requestConsentIfNeeded()
        // フロー完了フラグを保存し、次回以降は表示しない
        hasCompletedConsentFlow = true
        isRequesting = false
    }
}

#Preview {
    ConsentFlowView(adsService: MockAdsService())
}
