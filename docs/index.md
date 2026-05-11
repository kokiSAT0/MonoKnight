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
| 盤面、カード、塔フロア、報酬、敵、床ギミックなどの詳細ルール | [`game-rules-handbook.md`](game-rules-handbook.md) |
| Swift Package 境界、UI / Game / Services の責務 | [`architecture.md`](architecture.md) |
| Codex の作業手順、変更粒度、検証、コミット方針 | [`dev-workflow.md`](dev-workflow.md) |
| Game Center / AdMob / IAP / ATT / UMP | [`integrations.md`](integrations.md) |
| Info.plist とビルド設定由来の値 | [`info-plist-guidelines.md`](info-plist-guidelines.md) |
| TestFlight / App Store 提出前チェック | [`release-checklist.md`](release-checklist.md) |

## 3. 補助ドキュメント

- 塔ダンジョン規定: [`campaign-stage-regulations.md`](campaign-stage-regulations.md)
- 塔ダンジョン開発方針: [`dungeon-development-roadmap.md`](dungeon-development-roadmap.md)
- GameMode パラメータ: [`game-mode-parameters.md`](game-mode-parameters.md)
- 塔カード候補調整: [`card-weight-adjustment-guide.md`](card-weight-adjustment-guide.md)
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

- 通常ユーザー向けのメインコンテンツは塔ダンジョンのみとする。
- タイトルの通常プレイ導線は `DungeonDefinition` / `DungeonLibrary` を使う塔選択へ集約する。
- 塔ダンジョンは出口到達でフロアクリアし、失敗は主に HP 0 で発生する。残り手数 0 後は即失敗ではなく、上限超過1手目と以後3手ごとに疲労ダメージを受ける。
- スタンダード、ハイスコア、デイリーチャレンジ、Target Lab、クラシカル、旧目的地制キャンペーンは通常導線と実コードから削除済みの旧コンテンツとして扱う。
- 削除済み旧コンテンツの保存データ移行や互換 UI は現行スコープに含めない。
- 当面は成長塔を本編として育て、20Fから50F以上へ伸ばせるように、10F区切り、周回成長、報酬選択の手触りを優先して固める。
