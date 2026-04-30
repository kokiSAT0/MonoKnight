# AGENTS.md — MonoKnight

このファイルは本リポジトリにおける**最上位ルール（憲法）**である。
詳細仕様・実装手順・検証手順・設定値は `docs/` 配下を正本とし、本ファイルには短く安定した判断基準だけを置く。

---

## 1. 目的

- App Store 提出に耐える品質で MonoKnight を完成させる
- 個人開発 + Codex フルアクセス環境で、高速実装と安全性を両立する

---

## 2. 判断優先順位

迷った場合は以下の順で判断する。

1. クラッシュしない
2. 既存仕様を壊さない
3. シンプルで理解しやすい UI / 実装にする
4. Swift 初心者でも追えるコードにする
5. 局所的な改善に留める
6. 見た目や抽象化は最後に回す

---

## 3. 絶対ルール

- `Game` は Swift Package 経由でのみ参照する
- App ターゲットへ `Game` の個別ファイルを直接追加しない
- Apple 標準から大きく逸脱しない
- 動いている機能の仕様を無断で変えない
- 不必要な大規模リファクタリングや意味の薄い抽象化を行わない

責務判断に迷った場合は次を基準にする。

- ルール・モデル・スコア計算: `Game`
- 画面表示・レイアウト・操作導線: `UI`
- StoreKit / Game Center / AdMob などの外部連携: `Services`

---

## 4. Source of Truth

作業前に目的に応じて以下を参照する。

- docs 入口: `docs/index.md`
- 仕様: `docs/product-spec.md`
- ゲームルール詳細: `docs/game-rules-handbook.md`
- 構成: `docs/architecture.md`
- 開発手順: `docs/dev-workflow.md`
- 外部連携: `docs/integrations.md`
- 設定: `docs/info-plist-guidelines.md`
- リリース条件: `docs/release-checklist.md`

`docs/agents_legacy.md` は旧仕様アーカイブであり、現行判断の正本として使わない。

---

## 5. 完了条件

- 目的に対して最小限の変更である
- 関連するテスト、ビルド、または目視確認を実施している
- 仕様・構成・運用を変えた場合は関連 docs も同じ変更で更新している
- 未解決の問題がある場合は、原因と残リスクを簡潔に共有している
