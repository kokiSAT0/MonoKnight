import SwiftUI

struct PrivacyInformationView: View {
    var body: some View {
        List {
            Section("端末内に保存する情報") {
                Text("塔の進行状況、成長、ローカル記録、辞典の発見状況、音量などの設定は端末内に保存します。開発者のサーバーへの自動送信は行いません。")
            }
            Section("広告と同意") {
                Text("広告の表示にはGoogle AdMobを使用します。広告SDKはIPアドレス、端末識別子、広告への操作情報、診断情報などを扱う場合があります。トラッキング許可と広告同意の状態に応じて広告を設定します。")
                Text("端末の「設定」からトラッキング許可を変更できます。アプリの「設定」から広告のプライバシー設定を再確認できます。")
                Link("Googleのプライバシーポリシー", destination: URL(string: "https://policies.google.com/privacy?hl=ja")!)
            }
            Section("購入とサウンド") {
                Text("広告除去の購入と復元はAppleのApp Storeで処理します。開発者は決済カードの情報を取得しません。BGMと効果音はアプリ内に同梱しており、再生時に音声を外部へ送信しません。")
            }
            Section("診断情報の共有") {
                Text("不具合レポートは共有操作を行ったときに送信先を選べます。共有前にレポートの内容を確認してください。")
            }
        }
        .navigationTitle("プライバシーについて")
    }
}
