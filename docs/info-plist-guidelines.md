# Info.plist 設定ガイドライン（Xcode 管理推奨）

本ドキュメントは MonoKnight における `Info.plist` とビルド設定由来の値の運用ルール、および主要キー一覧の Source of Truth とする。

- `Info.plist` やビルド設定由来の値は **Xcode の GUI / .xcconfig で管理** する
- リポジトリ上では空テンプレートを維持し、**Git で直接編集しない**
- 具体的なキー設定はリリース直前に Xcode プロジェクト上で確認、適用する

本書はキー一覧と設定運用に専念し、Game Center / AdMob / IAP / ATT / UMP の挙動や連携方針は [integrations.md](integrations.md) を参照する。

## 1. バージョン関連

- `CFBundleShortVersionString`
  - 表示用のバージョン番号（例: `1.0.0`）。リリース毎にインクリメント。
- `CFBundleVersion`
  - ビルド番号（例: `1` から開始し、審査提出ごとに +1）。TestFlight/審査で一意である必要がある。

## 2. アプリ表示情報

- `CFBundleDisplayName`
  - ホーム画面に表示されるアプリ名。日本語版では `MonoKnight` または 12 文字以内の短縮名を設定。
- `LSApplicationCategoryType`
  - App Store のカテゴリ。パズルゲームに該当するため `public.app-category.games` + `puzzle` サブカテゴリを Xcode 上で選択。

## 3. プライバシー関連

- `NSUserTrackingUsageDescription`
  - ATT 許諾ダイアログに表示する文言。例: `広告の最適化のためにトラッキングの許可をお願いします。`
- `GADApplicationIdentifier`
  - AdMob のアプリ ID（`ca-app-pub-XXXXXXXX~YYYYYYYYYY` 形式）。
- `GADInterstitialAdUnitID`
  - 結果画面で利用するインタースティシャル広告ユニット ID（`ca-app-pub-XXXXXXXX/ZZZZZZZZZZ` 形式）。
- `SKAdNetworkItems`
  - Apple が公表する SKAdNetwork ID 一覧から、AdMob/自社広告で必要な ID を列挙。空要素を残さない。

## 4. Google UMP（ユーザー同意）

- `GADDebugGeography` 等のデバッグ設定はコード側で制御するため `Info.plist` に追加不要。
- UMP SDK のプライバシーポリシー URL は AdMob 管理画面で登録。アプリ内では `UMPConsentForm` を表示できる状態にしておく。

## 5. その他

- `UIApplicationSceneManifest`
  - 既存設定を維持し、必要に応じて `UISceneConfigurations` を更新。
- `UILaunchStoryboardName`
  - `LaunchScreen` ストーリーボードを指定。
  - Launch Screen は静的なブランド表示に留め、起動直後のタイトル画面と背景・トーンを近づける。
  - 強制待機、ローディング文言、バージョン表記、ゲーム説明、アニメーションは Launch Screen に入れない。必要な導入演出はアプリ起動後のオンボーディング側で扱う。

## 運用メモ

- 上記キーは **Xcode のターゲット設定 or .xcconfig で管理** し、Git 上では空テンプレートを維持する。
- 変更した値は TestFlight 用と App Store 審査用で整合性を取る。
- 本番値は `Config/Release.xcconfig` 等に追記し、平文でのコミットを避ける場合は環境変数や CI シークレットを活用する。
- リリース直前に Xcode 上で最終値を確認し、審査用説明文や広告設定と差異がないことを確認する。
