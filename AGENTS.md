# AGENTS.md — MonoKnight

本リポジトリの開発方針・役割分担（AI エージェント含む）・作業手順を定義する文書。MVP の要件は達成済みとし、**正式リリースに耐える品質で App Store へ提出すること**を最優先とする。Swift 初心者・個人開発でも実装可能な範囲に限定しつつ、デザインは**シンプル＆モダン（モノクロ主体）**とし、**Apple HIG**に準拠する。
基本的な開発方針は Windows11・VScode と codex でバイヴコーディングを行い、mac mini・xcode のエミュレーターでテストを行うサイクルで開発する。最終的には実機で Testflight によるテストを行う。

---

## 0. プロダクト概要（正式リリース向け）

- タイトル: MonoKnight
- ジャンル: カード × 移動パズル（5×5 盤、中央開始）
- コア: 手札 3 枚／山札は重み付き抽選（王将型は他カードの 1.5 倍）。 先読み 1 枚。全マス踏破でクリア。 全手札が使えない場合は**手数+5**のペナルティで引き直し。
- スコア: **手数のみ**（少ないほど上位）。Game Center ランキング対応。

---

## 1. スコープ（正式リリース）

- 盤面: 5×5 固定。踏破済マスは**グレー**。トップダウン表示。
- 移動カード: 16 種（ナイト 8 ＋距離 2 の直線/斜め 8）。
- 手札 UI: 画面下に 3 枚、次カード 1 枚の先読み。
- ランキング: Game Center Leaderboard（Single leaderboard）。
- 広告: AdMob（ゲーム終了時の**インタースティシャル**のみ）
- IAP: 広告除去（永続アイテム `remove_ads` / StoreKit2）。
- 言語: 日本語（英語は後日）。
- 端末: iPhone / iPad（iOS 16+、Portrait 固定）。iPad でも UI が崩れないようサイズクラスへ対応させる。
- 収集/送信: Game Center へのスコア提出と、広告配信に伴う最小限の計測（AdMob/SKAdNetwork）のみ。IDFA は ATT 許諾時のみ利用し、同意が得られない場合は非パーソナライズ広告（NPA=1）を配信。

### 非スコープ（正式リリースで後回し）

- デッキ構築・特殊カード・日替わりチャレンジ
- クラウドセーブ・アカウント連携
- 高度な演出（パーティクル過多・3D）
- 多言語・ゲーム内チュートリアル動画（iPad 最適化は正式リリースの必須要件に移行済み）

---

## 2. 技術選定

- **UI**: SwiftUI（App/Navigation/設定/モーダル）
- **ゲーム描画**: SpriteKit（2D グリッド＆駒移動。軽量で学習コスト低）
- **課金**: StoreKit 2（`Product.products(for:)`, `Transaction.updates`）
- **ランキング**: GameKit（`GKAccessPoint` で露出、`GKLeaderboard.submitScore(\_:context:player:leaderboardIDs:)` で送信。MVP は単一 ID）。
- **広告**: Google Mobile Ads SDK（SPM 導入、インタースティシャル）

  - ユーザー同意: Apple ATT（IDFA 許諾）＋ Google UMP（GDPR/一部州規制）
  - 配信ロジック:
    - ATT 許諾 かつ UMP 同意 ⇒ パーソナライズ広告
    - いずれか不可 ⇒ 非パーソナライズ（NPA=1）
  - SKAdNetwork 有効化（Info.plist に SKAdNetworkItems を定義）

- **状態管理**: ObservableObject + @State（小規模）。
- **乱数**: GameplayKit `GKMersenneTwisterRandomSource(seed:)` を使用（シード指定で再現性確保）

---

## 3. リポジトリ構成（提案）

※**ビルド方針の明文化**: `Game` ディレクトリ配下のゲームロジックは**必ずローカル Swift Package（`Game` プロダクト）経由**で参照する。`MonoKnightApp` ターゲットへ個別ファイルを直接追加するとパッケージ経由の参照と二重管理になり、重複シンボルやビルドエラーの原因となるため**絶対に行わないこと**。

```
MonoKnight/
  ├─ MonoKnightApp.swift
  ├─ Game/
  │   ├─ GameScene.swift          # 盤面描画・タッチ入力
  │   ├─ GameCore.swift           # ルール・手番進行・スコア計算
  │   ├─ Deck.swift               # 重み付き山札と手札管理
  │   ├─ MoveCard.swift           # カード定義（16種）
  │   └─ Models.swift             # 盤面/座標/状態列挙
  ├─ UI/
  │   ├─ RootView.swift           # タブ/ナビ
  │   ├─ GameView.swift           # SpriteKitをSwiftUIに埋め込み
  │   ├─ ResultView.swift         # スコア表示+リトライ
  │   └─ SettingsView.swift       # BGM/SE, ハプティクス, 連絡先
  ├─ Services/
  │   ├─ StoreService.swift       # StoreKit2（広告除去）
  │   ├─ AdsService.swift         # AdMob（表示制御）
  │   └─ GameCenterService.swift  # 認証/スコア送信/リーダーボード
  ├─ Resources/
  │   ├─ Assets.xcassets          # アプリアイコン/色
  │   └─ Localizable.strings      # 文字列
  └─ AGENTS.md
```

---

## 4. ルール仕様（実装用要約）

- 盤面: 5×5、`(0...4, 0...4)`、原点は左下、中央 `(2,2)` 開始。
- 駒移動: カードで指定された `(dx, dy)` を 1 回適用。
- 使用不可: 盤外に出るカードは当ターン選択不可（UI で薄表示）。
- ペナルティ: 手札 3 枚すべて不可 → 手数+5 加算 → 手札全引き直し。
- クリア: 全 25 マスの**踏破フラグ**が true になったら終了。
- スコア: 実移動回数 + ペナルティ加算。Game Center 送信。

---

## 5. デザイン指針（HIG 準拠）

- **配色**: モノクロ基調（背景#000, グリッド白, 駒白, 踏破済は#888）。
- **タイポ**: SF Pro（標準）。大文字連呼しない。読みやすさ優先。
- **タップ領域**: 44pt 以上。カードは間隔 8–12pt で誤タップ防止。
- **アニメーション**: 150–250ms で短く。過度な点滅禁止（光過敏配慮）。
- **ハプティクス**: 成功/無効操作で軽いフィードバック（`UINotificationFeedbackGenerator`）。
- **アクセシビリティ**: VoiceOver ラベル（カード方向/使用可否/残り踏破数）。
- **iPad レイアウト**: レギュラー幅では余白を設けて中央寄せし、シート/モーダルは `.presentationDetents([.large])` などで全画面相当を確保する。
- **広告**: プレイ外でのみ表示（結果画面）。誤タップ誘導をしない。
- **同意 UI**: 初回起動は「説明 → ATT → UMP」の順に集約。設定画面に「プライバシー設定」（UMP Privacy Options 再表示）を常設。
- **広告頻度**: インタースティシャルは結果画面のみ、最低 90 秒のインターバルかつ 1 プレイ 1 回までを目安。

---

## 6. 障害物なしのカード定義（16 種）

- ナイト型（±1,±2）8 種
- 周囲 2 マス（±2,0）/（0,±2）/（±2,±2）8 種
- 山札: 王将型は重み 3、その他は重み 2 の比率で無限抽選する（合計比率 3:2）。

---

## 7. 永続化・フラグ

- `remove_ads`（Bool）: IAP 購入で true。UserDefaults に保存。
- `best_moves_5x5`（Int）: ベスト手数（ローカル）。
- `has_submitted_gc`（Bool）: 初回スコア送信済みフラグ。

---

## 8. Game Center / AdMob / IAP 設定

- **Leaderboard ID**: `kc_moves_5x5`（最小手数ランキング）
- **IAP Product ID**: `remove_ads`
- **AdMob**:
  - SDK: Google Mobile Ads（SPM）、Google UMP（同意管理）
  - **ATT**: Info.plist に `NSUserTrackingUsageDescription` を記載し、初回起動時に `ATTrackingManager.requestTrackingAuthorization(...)`
  - **UMP**: 地域要件に応じて同意フォームを表示し、結果に応じて **パーソナライズ or NPA=1** を設定
  - **SKAdNetwork**: `SKAdNetworkItems` に必要な ID を列挙
  - **頻度**: インタースティシャルは結果画面のみ、短時間の連続表示を回避（90 秒間隔, 1 プレイ 1 回）
- **プライバシー**: ATT/UMP の同意状態をアプリ内「プライバシー設定」から再表示/変更できる導線を用意
- **復元**: 設定画面に「購入の復元」を設置し、`await AppStore.sync()` を実行。成功時は `remove_ads` を再評価。

---

## 9. タスク分解（AI エージェント別）

### Agent A（ゲームロジック）

- [ ] `Models.swift`（座標/盤/状態）
- [ ] `MoveCard.swift`（16 種の dx,dy 定義・ユーティリティ）
- [ ] `Deck.swift`（重み付き山札・手札引き直し）
- [ ] `GameCore.swift`（ルール/ペナルティ/クリア判定/スコア）
- [ ] テスト（盤外判定/全踏破判定/重み付き抽選の検証）

### Agent B（描画・UI）

- [ ] `GameScene.swift`（SpriteKit で盤/駒/踏破描画・タップ）
- [ ] `GameView.swift`（SwiftUI ブリッジ・手札 UI・先読み表示）
- [ ] `ResultView.swift`（スコア/ベスト/再戦/ランキング）

### Agent C（プラットフォーム機能）

- [ ] `GameCenterService.swift`（認証/送信/表示）
- [ ] `StoreService.swift`（StoreKit2 で購入/復元/状態保持）
- [ ] `AdsService.swift`（AdMob 準備/表示/購入時停止）

---

## 10. リリース前チェックリスト（MVP）

- [ ] ランキングにスコアが送信される
- [ ] IAP で広告が完全に消える（表示・ロードとも）
- [ ] 広告はゲーム外のみ（結果画面）
- [ ] 盤外カードは選択不可の視覚表現
- [ ] ペナルティ挙動が仕様通り（手数+5/引き直し）
- [ ] アクセシビリティラベル確認（VoiceOver）
- [ ] クラッシュフリー（Xcode Organizer のテスト）
- [ ] App Store 審査メタデータ（Privacy/Ads 説明）
- [ ] 初回起動フローで「説明 → ATT → UMP」が表示され、同意に応じて広告のパーソナライズ/NPA が切り替わる
- [ ] 設定から UMP の Privacy Options を再表示できる
- [ ] Info.plist の `NSUserTrackingUsageDescription` と `SKAdNetworkItems` を確認済み（最新 ID）

---

## 11. 将来ロードマップ（メモ）

- 可変盤サイズ（7×7, 9×9）
- デッキ構築・特殊カード（香車・ワイルド）
- デイリーチャレンジ（シード共有）
- iPad/英語対応・テーマ配色
- リプレイ保存・共有
