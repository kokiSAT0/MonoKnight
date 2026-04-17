# MonoKnight Refactor Plan

## 目的
- 振る舞いを原則維持したまま、再開発・機能追加・保守を安全に進めやすい構造へ寄せる。
- Swift 初心者でも追いやすいコードを保ち、App Store 提出品質を落とさない。

## 現状構造
| レイヤ | 現在の主責務 | 主なボトルネック |
| --- | --- | --- |
| `Game` | 盤面、移動、モード、キャンペーン定義、スコア | `GameMode.swift` と `CampaignStage.swift` が定義・表示・変換を兼任 |
| `UI` | タイトル、ゲーム表示、設定、遷移 | `RootView.swift` と `GameViewModel.swift` に状態とフローが集中 |
| `Services` | Ads / Game Center / StoreKit / 永続化ストア | 保存キーと責務の流儀が散っている |
| `SharedSupport` | ログとクラッシュ補助 | 基盤は安定しているが利用点が散在 |
| `MonoKnightApp.swift` | 起動、DI、同意フロー切替 | 設定キー依存が点在しやすい |

## 今回反映したベースライン整備
- `HandManagerTests` が前提にしていた固定ワープ目的地の順序を、テストデッキで安定再現できるようにした。
- `StorageKey` を追加し、`@AppStorage` / `UserDefaults` キーの主要な定義を 1 箇所へ集約した。
- `GameMode` と `CampaignStage` の表示用ロジックを拡張ファイルへ分離し、定義本体の責務を少し軽くした。
- `RootView` 内の重複していた `campaignStage(for:)` ヘルパーを 1 箇所に整理した。

## RootView / GameViewModel 責務表
### RootView
| 区分 | 現在の責務 | 今後の移管先 |
| --- | --- | --- |
| App shell | 起動後の Root 画面構成、設定シート、同意後の入口 | 維持 |
| Navigation | タイトル / ゲーム / 準備オーバーレイの切替 | `Navigation/Preparation coordinator` |
| Title flow | タイトルカード、各メニュー遷移、即時開始導線 | `TitleFlow` |
| Game flow | ゲーム準備完了待ち、タイトル復帰、キャンペーン復帰 | `GameFlow` |
| Diagnostics | レイアウトログ、top bar 監視 | 凍結または削除候補 |

### GameViewModel
| 区分 | 現在の責務 | 今後の移管先 |
| --- | --- | --- |
| Session state | `GameCore` の監視、スコア、ペナルティ、進行状態 | 維持 |
| Overlay/UI state | ポーズ、警告、ペナルティバナー、結果表示 | `Session UI state` |
| Flow handling | タイトル復帰、再挑戦、次ステージ開始 | `Result/transition handling` |
| Timer policy | ポーズ理由別の停止・再開 | `Pause/overlay/timer policy` |
| Service bridge | Ads / Game Center / CampaignProgress 呼び出し | 必要最小限を残す |

## 不変条件
- `Game` は Swift Package 経由のみで参照する。
- スコア式、広告表示ポリシー、IAP 後の広告停止、ATT/UMP の順序は変えない。
- キャンペーン・日替わり・フリーモードのルール結果は原則維持する。
- UI は真実の源泉を持たず、ルール判定は `Game` に置く。

## フェーズ方針
### Phase 1
- テストと docs を足場にして現状挙動を固定する。
- 保存キー、日替わり ID、top bar のような横断的な前提を明文化する。

### Phase 2
- `RootView` を App shell / Title flow / Game flow / coordinator に分割する。
- top bar 基盤は現状 `statusContent == EmptyView` で停止中のため、削除候補として扱う。

### Phase 3
- `GameViewModel` を画面状態、結果遷移、タイマーポリシーに分ける。
- 設定は `StorageKey` と将来の settings store に寄せる。

### Phase 4
- `GameMode` / `CampaignStage` を定義と表示へ分離し続ける。
- 日替わりは「プレイ用 mode ID」と「leaderboard 用 ID」を明示的に区別し続ける。

### Phase 5
- `GameScene`、Services、各種 Store の責務をさらに整える。

## 今やるべきこと
- `swift test` を常時グリーンに保つ。
- `RootView` と `GameViewModel` の分割を小さい PR 単位で進める。
- top bar 基盤は「停止中の構造」として扱い、復活要件が出るまで広げない。
- 日替わりの ID 二重構造は docs と命名で明確化してから変更する。
