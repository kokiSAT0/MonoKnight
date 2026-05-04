# Game Center リーダーボード管理表

MonoKnight の Game Center は、将来の `試練塔` leaderboard に備えた薄いサービス境界だけを現時点で保持する。
旧標準、クラシカル、Daily、ハイスコア用 leaderboard ID は現行設定から削除済みであり、現行の塔プレイからスコア送信や自動サインイン促しは行わない。

## 現行設定

| 対応モード | ステータス | リファレンス名 | Leaderboard ID | 備考 |
| --- | --- | --- | --- | --- |
| 試練塔 | 未定 | 未定 | 未定 | スコア式、対象フロア、提出タイミングを決めてから追加する。 |

## 運用メモ

- Leaderboard ID を追加するまでは `GameCenterServiceConfiguration` は空の設定を返す。
- 新しい leaderboard を追加する場合は、試練塔のスコア式、送信対象、再送信方針、表示導線を先に `product-spec.md` と本書へ記録する。
- 旧モード用 ID を復活させない。必要なランキングは塔攻略文脈の新仕様として作り直す。
