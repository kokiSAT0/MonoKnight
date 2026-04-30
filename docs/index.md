# MonoKnight Docs Index

このページは Codex と開発者が最初に参照する docs 入口である。
現行判断は下記の正本を優先し、古い計画書やアーカイブは補助情報として扱う。

## 1. 最初に読むもの

- 最上位ルール: [`../AGENTS.md`](../AGENTS.md)
- 仕様判断: [`product-spec.md`](product-spec.md)
- 実装レベルのゲームルール: [`game-rules-handbook.md`](game-rules-handbook.md)
- 構成と責務境界: [`architecture.md`](architecture.md)
- 作業フローと検証方針: [`dev-workflow.md`](dev-workflow.md)

## 2. Source of Truth

| 知りたいこと | 正本 |
| --- | --- |
| プロダクト要件、正式リリース範囲、非スコープ | [`product-spec.md`](product-spec.md) |
| 盤面、カード、目的地、フォーカス、スコアなどの詳細ルール | [`game-rules-handbook.md`](game-rules-handbook.md) |
| Swift Package 境界、UI / Game / Services の責務 | [`architecture.md`](architecture.md) |
| Codex の作業手順、変更粒度、検証、コミット方針 | [`dev-workflow.md`](dev-workflow.md) |
| Game Center / AdMob / IAP / ATT / UMP | [`integrations.md`](integrations.md) |
| Info.plist とビルド設定由来の値 | [`info-plist-guidelines.md`](info-plist-guidelines.md) |
| TestFlight / App Store 提出前チェック | [`release-checklist.md`](release-checklist.md) |

## 3. 補助ドキュメント

- キャンペーン規定: [`campaign-stage-regulations.md`](campaign-stage-regulations.md)
- GameMode パラメータ: [`game-mode-parameters.md`](game-mode-parameters.md)
- カード重み調整: [`card-weight-adjustment-guide.md`](card-weight-adjustment-guide.md)
- ATT / UMP 詳細: [`att-ump-consent-flow.md`](att-ump-consent-flow.md)
- Game Center ID 管理: [`game-center-leaderboards.md`](game-center-leaderboards.md)
- IAP カタログ: [`iap-product-catalog.md`](iap-product-catalog.md)
- CLI ビルドとテスト: [`development-basics.md`](development-basics.md)
- Xcode / ローカル設定: [`files.md`](files.md)
- リファクタリング原則: [`refactoring-guidelines.md`](refactoring-guidelines.md)
- リファクタリング進捗: [`refactoring-progress-tracker.md`](refactoring-progress-tracker.md)

## 4. アーカイブの扱い

- [`agents_legacy.md`](agents_legacy.md) は旧 `AGENTS.md` の退避アーカイブであり、現行仕様の正本ではない。
- 旧仕様と現行仕様が食い違う場合は、`product-spec.md`、`game-rules-handbook.md`、実装コードを優先する。
- `refactor-plan.md`、`refactoring-roadmap.md`、`refactoring-task-board.md` は過去計画や進捗確認に使い、現在の作業判断は `dev-workflow.md` と `refactoring-guidelines.md` を優先する。

## 5. 現行仕様の短縮メモ

- スタンダードモードは目的地を 12 個獲得するとクリアする。
- 任意の全引き直しは廃止し、フォーカスを使う。
- 目的地制のスコアは `移動手数 × 10 + 所要秒数 + フォーカス回数 × 15` とする。
- Game Center へ送信するスコアも同じ式を使う。
