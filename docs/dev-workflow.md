# MonoKnight Development Workflow

本書は MonoKnight の日常的な開発サイクル、Codex の自律作業、変更粒度、検証、コミット方針の正本である。
詳細な CLI 手順は [`development-basics.md`](development-basics.md)、構成判断は [`architecture.md`](architecture.md)、リファクタリング原則は [`refactoring-guidelines.md`](refactoring-guidelines.md) を参照する。

## 1. 基本方針

- App Store 提出に耐える品質を目指す
- 最小変更で目的を達成する
- 既存仕様、Swift Package 境界、外部連携の責務分離を壊さない
- Swift 初心者でも追える実装を優先する
- 過剰設計より、動くものを安全に少しずつ良くする

## 2. 標準作業フロー

1. 関連コードと関連 docs を読む
2. 目的を満たす最小変更を決める
3. 必要な範囲だけ局所リファクタリングする
4. 変更に合うテスト、ビルド、またはシミュレーター確認を実施する
5. 問題がなければ変更単位でコミットする
6. 結果、検証内容、残リスクを簡潔に共有する

エラーや未解決点が残る場合はコミットせず、原因と次に見るべき箇所を共有する。

## 3. 変更粒度

### 小変更

- UI 微調整
- バグ修正
- 文言修正
- 軽微なリファクタリング
- テスト追加

通常の説明付き作業として進めてよい。

### 中変更

- ファイル分割や統合
- 状態管理の変更
- Service 層の修正
- 複数画面にまたがる UI 導線変更

変更意図、影響範囲、検証方法を明示して進める。

### 大変更

- データ構造変更
- プロジェクト構成変更
- Swift Package 境界変更
- 外部サービス仕様変更
- 既存ゲーム仕様の変更

影響を明示し、関連 docs 更新とセットで扱う。

## 4. Codex の自律作業ルール

Codex は実装、バグ修正、UI 調整、局所リファクタリング、テスト追加、ビルドエラー修正を自律的に行ってよい。

ただし以下は禁止する。

- 不必要な大規模リファクタリング
- 意味の薄い抽象化
- Swift Package 構造の破壊
- Apple 標準から逸脱した実装
- 動いている機能の無断仕様変更
- App ターゲットへ `Game` ファイルを直接追加すること

## 5. 検証方針

優先順位は次の通り。

1. 起動できる
2. 1 プレイ完走できる
3. リザルトとスコアが仕様通りである
4. Game Center / 広告 / IAP の主要導線が壊れていない

Codex 経由の終盤検証は、PC の安定性を優先して `Scripts/codex-safe-validate.sh` を既定ルートにする。
ロジック変更は `Scripts/codex-safe-validate.sh logic` を優先する。
UI や外部連携を含む変更は、必要に応じて限定 app test、Xcode ビルド、シミュレーター、実機、TestFlight で確認する。
アプリ側の単体テストは共有 scheme の `MonoKnight` から実行する。
UI テストは実行時間と状態依存が大きいため、必要なケースだけ個別に実行する。
重い全体 `xcodebuild test` は既定では実行せず、必要なテストだけ `app-test` で個別指定する。

塔ダンジョンをメイン開発対象とし、標準検証は塔攻略本線に寄せる。
`swift test` は塔攻略本線とその土台を確認するロジック全体テストとして扱う。
新規テストは原則として `DungeonModeTests`、`DungeonGrowthStoreTests`、`DungeonSelectionViewTests`、`GameViewModelTests` の塔文脈へ追加する。
スタンダード、Daily、Target Lab、クラシカル、旧目的地制キャンペーン前提のテストは削除済み旧コンテンツとして復活させない。削った旧テストが守っていた観点を塔攻略でも必要と判断した場合は、塔文脈のテストとして書き直す。

安全検証スクリプトは Xcode 系コマンドの並列数、診断収集、DerivedData 出力先を抑える。
空きディスク容量が既定で 3GB 未満の場合は、シミュレーターや Xcode を使う重い検証を中止する。
閾値を一時的に変えたい場合は `CODEX_SAFE_MIN_FREE_GB` を指定する。

代表コマンド:

- `Scripts/codex-safe-validate.sh logic`
- `Scripts/codex-safe-validate.sh app-test MonoKnightAppTests/GameViewModelTests`
- `Scripts/codex-safe-validate.sh build`

## 6. コミット方針

- 1 つの作業目的に対して 1 コミットを基本とする
- 無関係な変更を混ぜない
- 既存の未コミット変更がある場合は、今回の作業範囲だけを分けて扱う
- 検証できなかった場合は、その理由を結果共有に含める

## 7. ドキュメント更新方針

docs 更新は必要時のみ行い、開発を止めないことを優先する。
ただし以下は必ず更新する。

- 大きな仕様変更
- 再利用される知識
- 初見で理解困難な設計
- 運用手順の変更
- リリース条件や外部連携の変更

## 8. 現在の開発フェーズ

- 現在は再開発を進めながら局所的に整える段階とする
- 事前の包括的リファクタリングは原則行わない
- `Game/GameCore.swift`、`Game/Deck.swift`、`UI/TitleFlowView.swift`、`UI/MoveCardIllustrationView.swift` は肥大化監視対象として扱う
- リファクタリングの詳細判断は [`refactoring-guidelines.md`](refactoring-guidelines.md) を参照する
