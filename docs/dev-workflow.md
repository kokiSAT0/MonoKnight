# MonoKnight Development Workflow

本書は MonoKnight の日常的な開発サイクル、作業判断、ドキュメント運用の Source of Truth とする。CLI 手順の詳細は `docs/development-basics.md`、リファクタリング原則の詳細は `docs/refactoring-guidelines.md` を参照しつつ、本書では実務フローを自己完結で整理する。

## 1. 開発サイクル

MonoKnight は以下のサイクルで開発する。

1. Windows 11 + VSCode + Codex で実装や文書更新を進める
2. mac mini + Xcode Simulator で挙動確認を行う
3. 仕上げとして実機で TestFlight テストを行う

最終目標は、App Store 提出に耐える品質で安定リリースすることとする。

## 2. 基本作業フロー

1. 既存コードと関連 docs を読む
2. 最小変更で目的を達成する
3. 必要な範囲だけ局所リファクタリングする
4. 編集後はビルド、テスト、シミュレーター確認などのエラーチェックを行う
5. 問題がなければ変更内容を修正単位でコミットする
6. 結果を簡潔に共有する

Codex の通常作業は「変更 → 確認 → コミット → 結果共有」までを完了条件とする。エラーチェックで問題が出た場合はコミットせず、原因と未解決点を共有する。

## 3. 実装判断の優先順位

迷ったときは以下の順で判断する。

1. クラッシュしない
2. 既存仕様を壊さない
3. シンプルで理解しやすい UI / 実装にする
4. Swift 初心者でも追えるコードにする
5. 局所的な改善に留める
6. 見た目や抽象化は最後に回す

## 4. 変更の扱い

### 4.1 小変更

- UI 微調整
- バグ修正
- 文言修正
- 軽微なリファクタリング

上記は通常の説明付き作業として進めてよい。

### 4.2 中変更

- ファイル分割や統合
- 状態管理の変更
- Service 層の修正

変更意図と影響範囲を明示して進める。

### 4.3 大変更

- データ構造変更
- プロジェクト構成変更
- Swift Package 境界変更
- 外部サービス仕様変更

影響を明示し、関連 docs 更新とセットで扱う。

## 5. リファクタリング運用

- 不必要な大規模リファクタリングは避ける
- 意味の薄い抽象化を増やさない
- 動いている機能の無断仕様変更をしない
- リファクタリング前に `docs/refactoring-guidelines.md` を確認する
- 新しい判断基準や運用ルールが出た場合は docs へ反映する

### 5.1 再開発フェーズの標準運用

- 現在は「再開発を開始してよい段階」とし、新機能追加やステージ追加を優先する
- 事前の包括的なリファクタリングは原則として行わない
- リファクタリングは「触った箇所だけ局所的に整える」運用を標準とする
- 仕様や責務境界を崩す変更は、実装前に影響範囲を明示してから進める
- `Game/GameCore.swift`、`Game/Deck.swift`、`UI/TitleFlowView.swift`、`UI/MoveCardIllustrationView.swift` は肥大化監視対象として扱い、変更時は同時に小さく整理してよい

### 5.2 再開発フェーズの受け入れ基準

- 変更単位で `swift test` をグリーンに保つ
- UI を含む変更では `xcodebuild` による App ビルド成功を確認する
- 新ステージ追加時は `CampaignLibraryTests` と `GameModeIdentifierTests` 系を維持する
- ゲーム進行変更時は `GameCoreTests` と `DeckTests` の近傍テストを追加または更新する

### 5.3 必須ルール

- `Game` は Swift Package 経由のみで参照する
- App ターゲットへ `Game` ファイルを直接追加しない
- 責務が曖昧な変更は `Game / UI / Services` の境界から再確認する

## 6. ドキュメント運用

- docs 更新は必要なときに行う
- 開発を止めないことを優先する
- ただし以下は必ず更新する
  - 大きな仕様変更
  - 再利用される知識
  - 初見で理解困難な設計
  - 運用手順の変更

## 7. テストと確認

- ロジックは自動テストを優先する
- UI はシミュレーターと実機確認を優先する
- 変更後は対象に応じたエラーチェックを必ず行う
- エラーチェックで問題がなければ、その変更単位でコミットまで進める
- 1 つの作業目的に対して 1 コミットを基本とし、無関係な変更を混ぜない
- エラーチェックで問題が残る場合はコミットせず、原因と未解決点を共有する
- 最低限確認すること
  - 起動できる
  - 1 プレイ完走できる
  - リザルトが正しい
  - Game Center / 広告 / IAP の主要導線が壊れていない

詳細な CLI ビルド手順は [development-basics.md](development-basics.md) を参照する。

## 8. AI エージェント運用メモ

`docs/agents_legacy.md` にあった AI エージェント別タスク分解は恒久仕様ではなく、現時点の運用メモとして扱う。

- Agent A: ゲームロジック
  - 主要コンポーネントと各種テストは実装済み
  - 今後は盤面パラメータ追加時の整合性テスト強化が主眼
- Agent B: 描画と UI
  - 主要画面構成は実装済み
  - 今後は `GameView` の責務分割と iPad 余白調整の確認が主眼
- Agent C: プラットフォーム機能
  - Game Center、StoreKit、広告、同意管理の必須機能は実装済み
  - 今後は TestFlight 通し QA と自動テストシナリオの整備が主眼

## 9. 補助参照

- CLI ビルドとテスト: [development-basics.md](development-basics.md)
- リファクタリング原則: [refactoring-guidelines.md](refactoring-guidelines.md)
- リファクタリング品質確認: [refactoring-quality-checklist.md](refactoring-quality-checklist.md)
- リリース前確認: [release-checklist.md](release-checklist.md)
