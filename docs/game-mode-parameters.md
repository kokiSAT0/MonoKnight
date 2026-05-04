# GameMode パラメータ仕様

MonoKnight の現行メインコンテンツは塔ダンジョンのみとする。`GameMode` は塔フロアのルールを `GameMode.Regulation` と `GameMode.DungeonMetadata` に束ね、旧目的地制キャンペーン、Daily、ハイスコア、旧標準/クラシカル/Target Lab 用の識別子は現行仕様として扱わない。

## 1. `GameMode.Regulation` の主なフィールド

| 項目 | 型 | 役割 |
| --- | --- | --- |
| `boardSize` | `Int` | フロア盤面の一辺の長さ |
| `handSize` | `Int` | 所持カードの最大種類数 |
| `deckPreset` | `GameDeckPreset` | フロア定義や報酬で使うカード構成 |
| `spawnRule` | `GameMode.SpawnRule` | 初期位置。成長塔では前フロア階段位置を反映する |
| `completionRule` | `GameMode.CompletionRule` | 塔では `.dungeonExit(exitPoint:)` を使う |
| `dungeonRules` | `DungeonRules?` | HP、手数、敵、床ギミック、基本移動、カード取得方式 |
| `bonusMoveCards` | `[MoveCard]?` | 報酬カードを初期手札へ反映するための補助 |

## 2. 塔ダンジョンの基準

- `GameMode.Identifier` は塔フロア用の `.dungeonFloor` を使う
- `completionRule` は出口到達で、目的地補充や旧スコア計算は行わない
- `DungeonRules.failureRule` で初期 HP と手数制限を管理する
- `DungeonRunState` を `GameMode.DungeonMetadata` に持たせ、HP、総手数、報酬カード、ラン seed、成長塔の開始区間を引き継ぐ
- `DungeonRules.cardAcquisitionMode == .inventoryOnly` の塔では、初期手札補充、NEXT補充、カード使用後の自動補充、手動引き直しを行わない
- 拾得カードはフロア限りの1回使い切り、報酬カードは残り回数つきでフロア間へ持ち越す
- 所持上限は10種類。同じカードは種類枠を増やさず、残り使用回数として積む
- 基本移動が許可された塔では、カードを消費しない上下左右1マス移動を許可する
- 移動後は `床ギミック → 出口判定 → 敵ターン → 失敗判定` の順で解決する

## 3. Game Center

Game Center は将来の試練塔向け leaderboard 基盤として、認証、スコア送信、leaderboard 表示のサービス境界だけを残す。現時点では旧モード用 leaderboard ID を設定せず、塔プレイから自動送信や自動サインイン促しを行わない。

## 4. 自動テスト方針

- `DungeonModeTests` で出口到達、HP 0、手数切れ、敵危険範囲、床割れ、報酬カード持ち越し、成長塔 seed 変化を確認する
- `DungeonSelectionViewTests` でタイトルから塔選択だけが主導線になること、成長塔の区間解放と成長表示を確認する
- 旧キャンペーン、Daily、ハイスコア、旧 leaderboard 設定前提のテストは削除対象とする
