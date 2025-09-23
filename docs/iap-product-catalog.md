# アプリ内課金プロダクト一覧

MonoKnight で利用するアプリ内課金（In-App Purchase）の種類・参照名・Product ID を一元管理するためのドキュメント。App Store Connect 側の設定を変更した際は、必ず本書と `StoreService` の実装を更新し、プロジェクト全体で不整合が起きないようにする。

## 現在の登録プロダクト

| 機能カテゴリ | 参照名 (StoreService) | Product ID | 種別 (StoreKit) | 利用箇所 | 備考 |
| --- | --- | --- | --- | --- | --- |
| 広告除去 | `removeAdsMK` | `remove_ads_mk` | Non-Consumable | `StoreService` / `AdsService` / `SettingsView` | 購入すると `AdsService.disableAds()` を呼び出し、AdMob の読み込みと表示を完全に停止する。

- **参照名**: コード側で `StoreService` が保持するプロパティ名／商品検索時のシンボル。Swift ファイル内での命名に合わせてキャメルケースで記載する。
- **Product ID**: App Store Connect に登録する一意の識別子。`AdsService` など他クラスでも同一 ID を参照するため、変更時は影響範囲の確認が必須。
- **種別**: StoreKit 2 における ProductType。現状は買い切り型（Non-Consumable）のみを採用している。

## 運用ルール

1. 新しい IAP を追加する際は、まず App Store Connect の Product ID を確定させ、Sandbox テストアカウントで購入検証を行う。
2. `StoreService` に該当するプロダクトの取得・購入・復元ロジックを追加し、`AdsService` などの関連サービスが期待通りに動作することを確認する。
3. 追加した IAP を本書の表へ追記し、機能概要や参照クラスを明記する。
4. 将来的に Product ID を変更した場合は、古い ID との互換性維持手段（復元処理やマイグレーション）の検討結果もここに追記する。

## 追加時のチェックリスト

- [ ] Product ID を App Store Connect に登録し、審査用ローカライズ情報を整備した。
- [ ] `StoreService` の `products` 取得対象と購入処理を更新した。
- [ ] 関連サービス（広告／ゲーム内機能など）に新しいフラグの反映箇所を実装した。
- [ ] `SettingsView` など UI に価格表示や購入ボタンを追加した。
- [ ] テスト用の Sandbox アカウントで購入・復元・再起動後の挙動を確認した。
- [ ] 本ドキュメントを更新し、開発チーム内で共有した。

