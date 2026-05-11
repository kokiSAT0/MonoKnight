# MonoKnight Architecture

本書は MonoKnight の技術選定、責務分離、ディレクトリ構成、依存ルールの Source of Truth とする。`docs/files.md` や個別ドキュメントに実行手順や補足は残してよいが、現在の構成判断は本書を正本として扱う。

## 1. 技術方針

- UI: `SwiftUI`
- ゲーム描画: `SpriteKit`
- 課金: `StoreKit 2`
- ランキング: `GameKit`（将来の試練塔向けに薄い境界だけ保持）
- 広告: `Google Mobile Ads SDK`
- 同意管理: `Google UMP` と `AppTrackingTransparency`
- 状態管理: `ObservableObject` と `@State`
- 乱数: `GameplayKit` の `GKMersenneTwisterRandomSource(seed:)`

## 2. 技術選定の意図

- `SwiftUI`
  - App 全体の画面遷移、設定、モーダルなど Apple 標準寄りの UI をシンプルに保つため
- `SpriteKit`
  - 2D グリッドと駒移動の描画を軽量に扱うため
- `StoreKit 2`
  - 永続 IAP の取得、監視、復元を Apple 標準 API で行うため
- `GameKit`
  - 将来の Game Center 認証と leaderboard 送信を Apple 標準 API で扱える境界を残すため
- `Google Mobile Ads SDK`
  - 結果画面のインタースティシャル配信に使うため
- `GameplayKit`
  - シード指定で再現性を持つ乱数を扱うため

## 3. アーキテクチャ原則

- 小規模アプリとして理解しやすさを優先する
- UI、ゲームロジック、外部連携の責務を分離する
- Apple 標準実装から大きく逸脱しない
- 過剰抽象化を避ける
- 外部サービスの依存は `Services` に閉じ込める
- ゲームルールは `Game` に閉じ込める

## 4. 依存ルール

### 4.1 最重要ルール

- `Game` ディレクトリ配下のゲームロジックは必ずローカル Swift Package の `Game` プロダクト経由で参照する
- `MonoKnightApp` ターゲットへ `Game` の個別ファイルを直接追加してはならない

このルールを破ると、パッケージ参照とアプリターゲット直参照の二重管理になり、重複シンボルやビルドエラーの原因になる。

### 4.2 責務による配置判断

- ルール、モデル、デッキ、塔フロア判定: `Game`
- 画面表示、レイアウト、操作導線: `UI`
- StoreKit、Game Center、AdMob などの外部サービス: `Services`
- アセットやローカライズ文字列: `Resources`
- 宝箱や報酬などのゲーム結果は `Game` が表示用イベントとして公開し、演出、詳細表示、確認タップ後の導線は `UI` が扱う

## 5. 現在の標準構成

```text
MonoKnight/
├─ MonoKnightApp.swift
├─ Game/
│  ├─ GameScene.swift
│  ├─ GameCore.swift
│  ├─ Deck.swift
│  ├─ MoveCard.swift
│  └─ Models.swift
├─ UI/
│  ├─ RootView.swift
│  ├─ GameView.swift
│  ├─ ResultView.swift
│  └─ SettingsView.swift
├─ Services/
│  ├─ StoreService.swift
│  ├─ AdsService.swift
│  └─ GameCenterService.swift
├─ Resources/
│  ├─ Assets.xcassets
│  └─ Localizable.strings
└─ AGENTS.md
```

## 6. レイヤごとの責務

### 6.1 App / Root

- アプリ起動
- 主要画面のナビゲーション
- サービス初期化の受け口

### 6.2 Game

- 盤面モデル
- 座標管理
- カード定義
- 山札と手札管理
- 手数、ペナルティ、クリア判定、塔フロア判定
- シード付き乱数による再現可能な抽選

### 6.3 UI

- SwiftUI ベースの画面構成
- `SpriteKit` ビューの埋め込み
- 結果画面や設定画面の表示
- iPhone / iPad のレイアウト調整

### 6.4 Services

- `StoreService`: StoreKit 2 を用いた広告除去 IAP
- `AdsService`: AdMob のロードと表示制御
- `GameCenterService`: 認証、スコア送信、leaderboard 導線の薄い境界
  - 現時点では旧モード用 leaderboard 設定を持たない dormant な基盤として保持する
  - サービス本体は façade とし、認証フロー・送信判定・leaderboard 提示は internal/private helper へ閉じ込め、UI へ GameKit 詳細を広げない

## 7. 状態管理方針

- 小規模アプリ前提で `ObservableObject` と `@State` を使う
- 画面ローカルの状態は View 側に寄せる
- ゲーム進行の主要状態はゲームロジック側で一貫して保持する
- 外部サービスの状態は Service 層で吸収し、UI から直接 SDK 詳細を扱わない

## 8. 乱数と再現性

- 抽選には `GKMersenneTwisterRandomSource(seed:)` を使う
- シード指定で再現可能な挙動を確保する
- 重み付き抽選のロジックは `Deck` 側へ集約する

## 9. ドキュメント運用との関係

- リファクタリング原則は [refactoring-guidelines.md](refactoring-guidelines.md) を参照する
- 詳細なファイル配置やローカル設定例は [files.md](files.md) を参照する
- 現在の構造判断と責務境界は本書を優先する

## 10. 変更時の注意

- Swift Package 境界を崩す変更は大変更として扱う
- `Game` と `UI` の責務を混ぜない
- 外部 SDK への直接依存を `UI` に広げない
- 構成変更時は本書と関連 docs を同じ変更で更新する
