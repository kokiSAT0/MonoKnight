# ATT / UMP 同意状態の整理

<!-- 監査対応や審査質問に即答できるよう、状態遷移と実装ポイントをまとめる -->

## 1. 背景と目的
- Apple の **AppTrackingTransparency (ATT)** と Google の **User Messaging Platform (UMP)** は別個の同意フローだが、ユーザー視点では一連の「広告に関する許諾」として理解されることが多い。
- 審査時に挙動を説明できるよう、両者の組み合わせによってアプリがどう振る舞うかを明文化しておく。
- 本ドキュメントは `AdsConsentCoordinator` / `AdsService` の実装とテストに反映済みの仕様書として扱い、運用変更時は必ず更新する。

## 2. 状態遷移サマリ
ATT と UMP の状態を掛け合わせた場合のアプリ挙動を以下に整理する。`shouldUseNPA` は非パーソナライズ広告フラグ、`canRequestAds` は AdMob へのリクエスト可否を表す。

| ATT ステータス | UMP ステータス | shouldUseNPA | canRequestAds | 備考 |
|:---------------|:---------------|:-------------|:--------------|:-----|
| `.notDetermined` | 任意 | `true` | UMP 依存 | 許諾前は常に NPA を要求。許諾後に `refreshConsentStatus()` を呼び出して再評価する。 |
| `.authorized` | `.obtained` / `.notRequired` | `false` | `true` | パーソナライズ広告の配信が許可される唯一の組み合わせ。 |
| `.authorized` | `.required` / `.unknown` | `true` | UMP 依存 | UMP の同意が取れるまで NPA を維持。 |
| `.denied` / `.restricted` | 任意 | `true` | UMP 依存 | トラッキング不可のため常に NPA。UMP 側のフォーム表示は継続可能。 |
| `@unknown default` | 任意 | `true` | UMP 依存 | 将来のステータス追加時は保守的に NPA 扱い。 |

> **補足:** `canRequestAds` は UMP の `canRequestAds` をそのまま採用する。ATT で許可が得られなくても NPA 広告は配信できるため、AdMob のロード自体は妨げない。

## 3. 実装との対応
- `AdsConsentCoordinator` に ATT ステータスを提供するクロージャを導入し、`ConsentStatus` と掛け合わせて `shouldUseNPA` を算出する。
  - 生成直後に ATT が拒否済みであれば `shouldUseNPA` を即時 `true` へ引き上げ、AppStorage と UI 表示の整合性を確保する。
  - `requestConsentIfNeeded()` / `refreshConsentStatus()` 完了時は、ATT と UMP の最新値を再評価して `stateDelegate` へ通知する。
- `AdsService.requestTrackingAuthorization()` は ATT 許諾が取れた直後に `refreshConsentStatus()` を呼び出し、NPA 判定の再同期を行う。
- これらの変更は `MonoKnightAppTests/AdsConsentCoordinatorTests.swift` などのテストで検証しており、状態ごとの通知内容が期待通りになることを保証している。

## 4. 運用ポリシー
- 初回起動時のオンボーディング (`ConsentFlowView`) では **ATT → UMP** の順にダイアログを提示し、各 API が返す結果を上記ロジックで統合する。
- プライバシー設定画面から UMP の再表示を行った場合も同じ判定を用いるため、**ATT の変更があれば常に UMP の再同期を行う** 方針とする。
- 仕様変更やレギュレーション強化が発生した際は、まず本ドキュメントを更新し、その後コード・テストを順に整備する運用フローを徹底する。

## 5. チェックポイント
- [ ] ATT で `.authorized` を取得した直後に `AdsService.requestTrackingAuthorization()` が `refreshConsentStatus()` を呼び出すことを確認したか。
- [ ] `AdsConsentCoordinator` のログ出力で ATT/UMP 両方の状態が把握できるか。
- [ ] QA では `.authorized` / `.denied` / `.notDetermined` の 3 パターンをテスト端末で再現し、広告表示挙動を確認したか。

<!-- 同意フロー変更時は本書を必ず参照・更新すること -->
