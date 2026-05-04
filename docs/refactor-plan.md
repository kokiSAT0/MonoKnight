# MonoKnight Refactor Plan

ファイル単位の最新進捗は `docs/refactoring-progress-tracker.md` を正本とする。

## 目的
- 振る舞いを原則維持したまま、再開発・機能追加・保守を安全に進めやすい構造へ寄せる。
- Swift 初心者でも追いやすいコードを保ち、App Store 提出品質を落とさない。

## 現状構造
| レイヤ | 現在の主責務 | 主なボトルネック |
| --- | --- | --- |
| `Game` | 盤面、移動、モード、塔フロア定義 | `MoveCard.swift` の façade 化は完了。旧キャンペーン定義は削除済みで、今後は `GameCore.swift` / `Deck.swift` / `DungeonDefinition.swift` の監視を継続する |
| `UI` | タイトル、ゲーム表示、設定、遷移 | `RootView.swift` / `GameViewModel.swift` / `AppTheme.swift` の主要整理は完了。今後は `TitleFlowView.swift` や `MoveCardIllustrationView.swift` など高利用画面の監視を継続する |
| `Services` | Ads / Game Center / StoreKit / 永続化ストア | 保存キーと責務の流儀が散っている |
| `SharedSupport` | ログとクラッシュ補助 | 基盤は安定しているが利用点が散在 |
| `MonoKnightApp.swift` | 起動、DI、同意フロー切替 | 設定キー依存が点在しやすい |

## 今回反映したベースライン整備
- `HandManagerTests` が前提にしていた固定ワープ目的地の順序を、テストデッキで安定再現できるようにした。
- `StorageKey` を追加し、`@AppStorage` / `UserDefaults` キーの主要な定義を 1 箇所へ集約した。
- `GameMode` の表示用ロジック、`Regulation` 補助、built-in mode 生成を拡張ファイルへ分離し、定義本体を façade として薄く保てる状態にした。
- 旧 `CampaignStage` 系は塔攻略専用化で削除し、塔フロア定義は `DungeonDefinition.swift` へ集約した。
- `GameViewModelSupport` の helper type 群を presentation / interaction / lifecycle support へ分割し、さらに action / lifecycle surface も input / flow / lifecycle / bindings extension へ再分割して、support 本体を state sync glue へ縮退させた。
- `MoveCard` の第2段階として `MovePattern` 本体を pattern support へ、registry・解決・テスト override を resolution extension へ移し、本体を case 定義と façade へ整理した。
- `AppTheme` のトークンを badges / cards / board / controls / overlays / status chrome / platform bridge / bridge palette へ整理し、ベーステーマの入口を薄くした。
- `RootView` の旧キャンペーン分岐を削除し、塔選択への導線へ集約した。

## RootView / GameViewModel 責務表
### RootView
| 区分 | 現在の責務 | 今後の移管先 |
| --- | --- | --- |
| App shell | 起動後の Root 画面構成、設定シート、同意後の入口 | 維持 |
| Navigation | タイトル / ゲーム / 準備オーバーレイの切替 | `Navigation/Preparation coordinator` |
| Title flow | タイトルカード、各メニュー遷移、即時開始導線 | `TitleFlow` |
| Game flow | ゲーム準備完了待ち、タイトル復帰、塔攻略復帰 | `GameFlow` |
| Diagnostics | レイアウトログ、top bar 監視 | 凍結または削除候補 |

### GameViewModel
| 区分 | 現在の責務 | 今後の移管先 |
| --- | --- | --- |
| Session state | `GameCore` の監視、スコア、ペナルティ、進行状態 | 維持 |
| Overlay/UI state | ポーズ、警告、ペナルティバナー、結果表示 | `Session UI state` |
| Flow handling | タイトル復帰、再挑戦、次ステージ開始 | `Result/transition handling` |
| Timer policy | ポーズ理由別の停止・再開 | `Pause/overlay/timer policy` |
| Service bridge | Ads / dormant Game Center 呼び出し | 必要最小限を残す |

## 不変条件
- `Game` は Swift Package 経由のみで参照する。
- 広告表示ポリシー、IAP 後の広告停止、ATT/UMP の順序は変えない。
- 削除済み旧コンテンツのルール結果は現行仕様の不変条件に含めない。
- UI は真実の源泉を持たず、ルール判定は `Game` に置く。

## フェーズ方針
### Phase 1
- テストと docs を足場にして現状挙動を固定する。
- 保存キー、塔フロア ID、top bar のような横断的な前提を明文化する。

### Phase 2
- `RootView` を App shell / Title flow / Game flow / coordinator に分割する。
- top bar 基盤は現状 `statusContent == EmptyView` で停止中のため、削除候補として扱う。

### Phase 3
- `GameViewModel` は façade と state sync glue を維持しつつ、追加 action は input / flow / lifecycle / bindings extension 単位で継続整理する。
- helper type と action surface の責務境界が崩れないよう、小さな PR 単位で維持する。

### Phase 4
- `AppTheme` は色値を維持したまま責務整理を完了し、今後は extension 単位の運用を維持する。
- Game Center は将来の試練塔 leaderboard 仕様が固まるまで dormant な境界として保つ。

### Phase 5
- `GameScene`、Services、各種 Store の責務をさらに整える。
- 次の tracked 候補として `GameCore.swift` / `Deck.swift` / `TitleFlowView.swift` を再評価する。

## 今やるべきこと
- `swift test` を常時グリーンに保つ。
- `AppTheme` は色値を変えず、extension 単位での変更運用を維持する。
- `Game` レイヤでは `MoveCard` 分離後も既存テストを維持し、移動仕様変更は小さな単位で固定する。
