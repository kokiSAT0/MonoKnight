# Game Center リーダーボード管理表

MonoKnight で利用する Game Center リーダーボードの参照名と Leaderboard ID を一覧化したドキュメント。
既定値は `Config/Default.xcconfig` に置き、`Info.plist` 経由で `GameCenterService` が解決する。
正式リリース時に本番用のリーダーボードへ移行する場合は、`Local.xcconfig` または CI 用 xcconfig から同名キーを上書きし、
本表もあわせて更新すること。

## テスト運用中のリーダーボード

| 対応モード | ステータス | リファレンス名 (Reference Name) | Leaderboard ID | 備考 |
| --- | --- | --- | --- | --- |
| スタンダードモード (5x5) | テスト | `[TEST] Standard Leaderboard` | `test_standard_moves_v1` | スタンダードモードのプレイ結果を送信。正式版では本番 ID へ差し替える。 |
| クラシカルチャレンジ | テスト | `[TEST] Classical Challenge Leaderboard` | `test_classical_moves_v1` | クラシカルチャレンジ専用の桂馬デッキ向けランキング。正式リリース時に本番 ID へ切り替え予定。 |
| 日替わり固定シード | テスト | `[TEST] Daily Fixed Leaderboard` | `test_daily_fixed_v1` | スタンダード設定の固定シードを日替わりで共有するモード向け。`GAMECENTER_LEADERBOARD_DAILY_FIXED_*` で上書き可能。 |
| 日替わりランダムシード | テスト | `[TEST] Daily Random Leaderboard` | `test_daily_random_v1` | 日替わりで乱数シードを配信するモード。`GAMECENTER_LEADERBOARD_DAILY_RANDOM_*` で上書き可能。 |

### 運用メモ

- 上記リファレンス名は App Store Connect の Game Center 設定画面で入力する値と一致させること。
- Leaderboard ID はアプリのバイナリから送信する ID と完全一致していないとスコアが反映されない。
- 実際にアプリが参照する値は `Info.plist` の以下キー経由で解決される。
  - `GameCenterLeaderboardStandardReferenceName` / `GameCenterLeaderboardStandardID`
  - `GameCenterLeaderboardClassicalReferenceName` / `GameCenterLeaderboardClassicalID`
  - `GameCenterLeaderboardDailyFixedReferenceName` / `GameCenterLeaderboardDailyFixedID`
  - `GameCenterLeaderboardDailyRandomReferenceName` / `GameCenterLeaderboardDailyRandomID`
- 新しいモードを追加してテスト用リーダーボードが必要になった場合は、上表と `GameCenterServiceConfiguration`
  の定義を追加し、必要に応じて `GameView` / `ResultView` の送信ロジックを拡張する。
- テスト用リーダーボードから正式名称へ切り替える際は、xcconfig 側の上書きに加えて、旧 ID の送信状況を
  `resetSubmittedFlag(for:)` でリセットし、ユーザーの再送信を促すことを推奨する。
- デイリーモードは日本時間 0:00 を基準に切り替え予定。日付は `YYYY-MM-DD` 形式の文字列で共有し、固定シードは共通配信、ランダムシードは各端末が共通シードから派生生成する想定。
- 日替わりリーダーボードは本番運用でのリセットを行わず、日付に応じたスコアが積み上がる前提。必要に応じて App Store Connect 側の期間限定イベント機能を検討する。
