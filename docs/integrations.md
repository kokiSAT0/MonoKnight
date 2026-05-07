# MonoKnight Integrations

本書は MonoKnight が利用する外部サービス連携の Source of Truth とする。設定キーそのものは `docs/info-plist-guidelines.md` を正本とし、本書では Game Center、AdMob、IAP、ATT、UMP の役割と挙動を自己完結で整理する。

## 1. 連携一覧

- Game Center
  - 用途: 将来の試練塔向けスコア送信と leaderboard 表示の薄いサービス境界
- StoreKit 2
  - 用途: 広告除去 IAP の販売と復元
- Google Mobile Ads SDK
  - 用途: 結果画面のインタースティシャル広告
- AppTrackingTransparency
  - 用途: IDFA 利用の許諾取得
- Google UMP
  - 用途: 地域要件に応じた広告同意管理
- SKAdNetwork
  - 用途: 広告計測のための Apple 標準連携

## 2. Game Center

- Leaderboard ID: 現時点では未設定。旧モード用 ID は使わない。
- ランキング対象スコア: 現時点では未定義。将来の試練塔で仕様を決める。
- 認証導線:
  - 現行の塔攻略通常導線では自動サインイン促しを出さない
  - `GKAccessPoint` の露出は将来の leaderboard 仕様確定まで行わない
- 送信タイミング:
  - 現行の基礎塔、成長塔、試練塔からはスコア送信しない
  - 将来の試練塔 leaderboard 追加時に、送信対象とスコア式を明示する

詳細な ID 管理は [game-center-leaderboards.md](game-center-leaderboards.md) を参照する。

## 3. In-App Purchase

- Product ID: `remove_ads_mk`
- 種別: 永続アイテム
- 期待挙動:
  - 購入後は広告のロードと表示をともに停止する
  - 設定画面から購入の復元を実行できる
  - 復元は `AppStore.sync()` を呼び、成功後に購入状態を再評価する

詳細なプロダクト管理は [iap-product-catalog.md](iap-product-catalog.md) を参照する。

## 4. AdMob

- SDK は `Google Mobile Ads` を利用する
- 広告種別はインタースティシャルのみ
- 表示場所は結果画面のみ
- 表示頻度:
  - 10 回クリアごとに 1 回まで
  - 最低 90 秒間隔
  - 1 プレイ 1 回までを目安
- 誤タップ誘導をしない
- プレイ中には表示しない

## 5. ATT / UMP / NPA の関係

広告配信の考え方は次の通りとする。

- ATT 許諾あり かつ UMP 同意あり
  - パーソナライズ広告を許可する
- 上記以外
  - 非パーソナライズ広告 (`NPA=1`) を使う

補足:

- ATT が許可されなくても、UMP 側で広告リクエスト可能なら NPA 広告は配信できる
- 同意 UI は初回起動で「説明 → ATT → UMP」の順にまとめて提示する
- 設定画面から Privacy Options を再表示できるようにする

詳細な状態遷移は [att-ump-consent-flow.md](att-ump-consent-flow.md) を参照する。

## 6. SKAdNetwork

- `SKAdNetworkItems` を `Info.plist` に定義する
- AdMob 連携に必要な ID を最新状態で維持する
- キー管理は `docs/info-plist-guidelines.md` を正本とする

## 7. プライバシーと同意運用

- 収集/送信は最小限に留める
- IDFA 利用は ATT 許諾時のみ
- UMP の結果に応じて広告リクエスト可否とパーソナライズ可否を切り替える
- 設定画面にプライバシー設定導線を常設する
- 審査や QA で説明できるよう、同意状態の挙動は文書化を維持する

## 8. 実装上の主要サービス

- `GameCenterService`
  - 認証
  - スコア送信
  - leaderboard 表示
  - 現時点では旧 leaderboard 設定を持たない dormant な基盤として保持する
  - leaderboard 導線
- `StoreService`
  - 商品取得
  - 購入
  - 復元
  - `Transaction.updates` 監視
- `AdsService`
  - 広告ロード
  - 表示制御
  - ATT 許諾後の再評価連携

## 9. 関連ドキュメント

- プロダクト仕様とスコア式: [product-spec.md](product-spec.md)
- ゲームルール詳細: [game-rules-handbook.md](game-rules-handbook.md)
- 設定キーと運用: [info-plist-guidelines.md](info-plist-guidelines.md)
- ATT / UMP 詳細: [att-ump-consent-flow.md](att-ump-consent-flow.md)
- Game Center ID 管理: [game-center-leaderboards.md](game-center-leaderboards.md)
- IAP カタログ: [iap-product-catalog.md](iap-product-catalog.md)
