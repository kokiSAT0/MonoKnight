# TestFlight Internal Distribution

本書は MonoKnight を App Store Connect の内部テスターへ配布するための最小手順をまとめる。
App Store 本審査用の説明文、スクリーンショット、完全なメタデータ整備は後続作業とし、まず内部 TestFlight で実機 QA を開始することを目的にする。

## 1. ローカル設定の確認

Xcode 側の現在値は次を基準にする。

- Scheme: `MonoKnight`
- Product: `MonoKnightApp.app`
- Bundle ID: `com.kokisato.MonoKnightApp`
- Display Name: `MonoKnight`
- Version: `1.0`
- Build: `1` から開始し、再アップロード時は必ず +1 する
- Team ID: `5TAKV37ZM4`
- Signing: Automatic
- Devices: iPhone / iPad

App Store Connect 側のアプリ登録では、Bundle ID が `com.kokisato.MonoKnightApp` と一致していることを確認する。
一致していないアプリレコードにはアップロードできないため、App Store Connect 側で正しい Bundle ID のアプリを使う。

2026-05-21 のローカルプリフライトでは、`MonoKnight` scheme の Release build settings と生成済み `MonoKnightApp.app/Info.plist` で以下を確認済み。

- `PRODUCT_BUNDLE_IDENTIFIER = com.kokisato.MonoKnightApp`
- `MARKETING_VERSION = 1.0`
- `CURRENT_PROJECT_VERSION = 1`
- `DEVELOPMENT_TEAM = 5TAKV37ZM4`
- `CODE_SIGN_STYLE = Automatic`
- `CFBundleDisplayName = MonoKnight`
- `NSUserTrackingUsageDescription` が設定済み
- `SKAdNetworkItems` が空でない

`Config/Default.xcconfig` は共有の既定値として `com.kokisato.MonoKnightApp$(BUNDLE_ID_SUFFIX)` を持つが、配布対象の `MonoKnightApp` ターゲットは project 設定で `com.kokisato.MonoKnightApp` を明示している。TestFlight へ上げる時は、必ず shared scheme `MonoKnight` が `MonoKnightApp.app` を Archive 対象にしていることを確認する。

## 2. Archive とアップロード

1. Xcode で `MonoKnight.xcodeproj` を開く。
2. Scheme を `MonoKnight` にする。
3. 実機または `Any iOS Device` を選ぶ。
4. `Product > Archive` を実行する。
5. Organizer で作成された Archive を選び、App Store Connect へ配布する。
6. 内部テスター専用の選択肢が出る場合は TestFlight / Internal Testing 向けとして進める。

CLI の Release ビルド確認は、アップロード前の補助確認として扱う。
署名、Provisioning Profile、Apple ID セッション、App Store Connect 側の権限は Xcode / App Store Connect の状態に依存するため、最終アップロードは Organizer で確認する。

ローカルの補助確認として、2026-05-21 に次の Release build は成功済み。

```sh
xcodebuild -project MonoKnight.xcodeproj -scheme MonoKnight -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/MonoKnightPreflightDerivedData CODE_SIGNING_ALLOWED=NO build
```

この確認は署名を無効化しているため、Archive 作成可否、Provisioning Profile、App Store Connect へのアップロード可否は未確認のまま残す。

## 3. TestFlight の最小入力

内部 TestFlight 開始時点では、App Store 商品ページの全項目が完成していなくてもよい。
TestFlight タブでは次の最小情報を入力する。

- Beta App Description: `塔を登るダンジョンパズルゲームの開発中ビルドです。`
- What to Test: `通常プレイ開始、塔の進行、リザルト、広告/IAP導線、同意導線、iPhone/iPad Portraitの表示崩れを確認してください。`
- Feedback Email: 開発者が受け取れるメールアドレス
- Export Compliance: App Store Connect の質問に従って回答する

## 4. 内部テスター配布

1. App Store Connect でテスターをユーザーとして追加し、MonoKnight へのアクセス権を付ける。
2. MonoKnight の `TestFlight` タブを開く。
3. `Internal Testing` でグループを作成する。
4. アップロード済みビルドをグループへ追加する。
5. 内部テスターを招待する。

内部テスターは App Store Connect ユーザーが対象で、最大 100 人まで追加できる。
外部テスターへ配る場合は初回 TestFlight 審査が必要になるため、本書の初回内部配布とは別作業として扱う。

## 5. 初回 QA

実機にインストールできたら、まず [`release-checklist.md`](release-checklist.md) のうち次を優先して確認する。

- 起動できる
- タイトルから塔選択を開ける
- 1F から開始できる
- フロア出口到達で次フロアへ進める
- HP 0 や失敗リザルトから復帰導線を確認できる
- 広告、広告除去 IAP、購入復元、ATT / UMP 同意導線が壊れていない
- iPhone / iPad Portrait で主要画面に重大な表示崩れがない

重大な進行不能、クラッシュ、広告/IAP/同意まわりの不整合があれば、App Store 本審査用メタデータ整備より先に修正する。
