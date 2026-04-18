# リファクタ進捗台帳

継続的な開発で影響の大きい主要ファイルだけを対象に、ファイル単位のリファクタ進捗を管理する。
テーマ単位の方針やタスクは `docs/refactor-plan.md` と `docs/refactoring-task-board.md` を参照し、本書は「どのファイルがどこまで整理できているか」の把握に専念する。

## 目的と更新ルール

- 本書をファイル単位の進捗管理における正本とする。
- 対象は主要リファクタ対象ファイルのみとし、細かい補助ファイルや安定済みの小ファイルは原則含めない。
- 更新は自動生成ではなく、リファクタ PR ごとに人手で行う軽量運用とする。
- 各 PR で最低限更新する項目は `状態`、`現状`、`次の分割/整理先`、`完了条件`、必要に応じて `関連テスト/根拠` とする。
- 初期ベースラインとして、2026-04-17 時点の `swift test` は `103 tests, 0 failures` を確認済み。

### 状態の判定基準

- `完了`: 主責務が分離済みで、今後は機能追加中心。大きな再分割を前提にしない。
- `進行中`: 分割は始まっているが、状態・依存・ロジックがまだ集中している。
- `未着手`: 主要な肥大化や責務集中が残っているが、分割方針がまだ反映されていない。
- `保留`: 問題はあるが、今は触らない判断が明文化されている。

## 進捗サマリ

| 指標 | 件数 | 補足 |
| --- | ---: | --- |
| 完了 | 7 | 主責務の分離が完了し、今後は維持中心で進められるもの |
| 進行中 | 4 | 分割は始まっているが、継続監視が必要なもの |
| 未着手 | 1 | 大きい責務集中が残っているもの |
| 保留 | 0 | 現時点では該当なし |

## 主要対象ファイル一覧

| レイヤ | ファイル | 状態 | 現状 | 次の分割/整理先 | 完了条件 | 関連テスト/根拠 |
| --- | --- | --- | --- | --- | --- | --- |
| UI | `UI/RootView.swift` | 進行中 | `RootView+GameFlow.swift`、`RootView+Diagnostics.swift`、`RootView+Shell.swift` へ分割が進み、本体は依存注入・`StateObject` 保持・`body` 入口・初回認証 task にかなり寄った。いっぽう shell composition の公開入口と state store 集約はまだ残る | shell composition の公開入口を監視しつつ、state store を含む残存責務が逆流しない状態を保つ。次の主対象は `Game/GameSceneSupport.swift` へ移す | `RootView.swift` が app shell の入口にほぼ限定され、タイトル組み立て・layout diagnostics・ルートイベント窓口が別ファイルで追える | `docs/refactor-plan.md` の責務表、`UI/RootView+GameFlow.swift`、`UI/RootView+Diagnostics.swift`、`UI/RootView+Shell.swift`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| UI | `UI/GameViewModel.swift` | 進行中 | `SessionUIState`、`ResultPresentationState`、input/core binding/session reset に加え、service bridge と初期表示同期も `GameViewModelSupport.swift` 側へ分離済み。公開 API の入口と helper 調停は本体に残るが、責務集中はかなり薄くなった | 残る公開入口の監視を続けつつ、次の主対象を `Game/CampaignLibrary.swift` へ移す | `GameViewModel.swift` が GameCore の窓口と helper 調停にほぼ限定され、設定反映・認証同期・広告/キャンペーン橋渡しの詳細が補助型へ逆流しない | `MonoKnightAppTests/GameViewIntegrationTests.swift`、`MonoKnightAppTests/GameViewModelTests.swift`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| Game | `Game/CampaignLibrary.swift` | 完了 | 本体は公開 API と chapter builder の組み立てに絞り、章定義は `CampaignLibrary+Chapter1.swift` 〜 `CampaignLibrary+Chapter8.swift` へ分割済み。共通 penalty / fixed spawn は shared helper へ集約した | 維持中心。章追加やバランス調整は該当 chapter source だけを触る運用を保つ | 章ごとの定義追加・調整が局所変更で済み、単一ファイル依存を避けられている | `Tests/GameTests/CampaignLibraryTests.swift`、`Tests/GameTests/GameModeIdentifierTests.swift`、`Tests/GameTests/DailyChallengeDefinitionTests.swift`、`swift test` |
| Game | `Game/GameSceneSupport.swift` | 未着手 | SpriteKit 補助責務が 1 ファイルに集中し、layout / decoration / animation / highlight 系が混在している | layout、decoration、animation、highlight 系の補助を責務別に分割する | 描画補助ごとの変更影響範囲が限定され、ハイライトや装飾の修正が局所化されている | ファイル行数 1600 行超、`GameScene` 補助ロジックが集約 |
| App | `MonoKnightApp.swift` | 進行中 | 起動、DI、同意フロー切替、`scenePhase` 処理は整理されているが、bootstrap と環境切替の集中が残る | bootstrap 初期化と環境別サービス組み立ての責務を整理する | App 本体がライフサイクル入口に集中し、モック/本番切替の詳細が追いやすい構造になる | `MonoKnightAppTests/AdsServiceCoordinatorIntegrationTests.swift`、`MonoKnightAppUITests` |
| Services | `Services/GameCenterService.swift` | 進行中 | プロトコル化と UI からの利用経路は整理済みだが、本番 leaderboard ID の `FIXME` が残る | xcconfig 経由の本番値注入と定義整理を進める | テスト値と本番値の切替方針がコードと docs で一致し、`FIXME` を解消できている | `docs/game-center-leaderboards.md`、ファイル内 `FIXME` コメント |
| UI | `UI/SettingsView.swift` | 進行中 | `SettingsViewSections.swift` と `SettingsViewSupport.swift` が存在し、分割途中として扱える | セクション構築と表示用補助をさらに寄せ、設定画面本体を薄く保つ | `SettingsView.swift` が画面構成中心になり、詳細セクションや補助ロジックが外出しされている | `UI/SettingsViewSections.swift`、`UI/SettingsViewSupport.swift` |
| UI | `UI/GameView.swift` | 完了 | 描画以外の責務を `GameViewModel`、`GameBoardBridgeViewModel`、レイアウト補助へ移譲済み | 維持中心。大きな再分割は前提としない | View 本体が描画と組み立てに集中し、状態管理の追加逆流が起きていない | `docs/refactoring-task-board.md`、`MonoKnightAppTests/GameViewLayoutCalculatorTests.swift` |
| UI | `UI/GameBoardBridgeViewModel.swift` | 完了 | SwiftUI と SpriteKit の橋渡し責務が独立し、状態管理の境界が明確 | 維持中心。描画連携の窓口として安定運用する | GameView 側へ SpriteKit 詳細を再流入させずに拡張できる | `docs/refactoring-task-board.md`、`MonoKnightAppTests/GameBoardBridgeViewModelHighlightTests.swift` |
| Game | `Game/BoardGeometry.swift` | 完了 | 盤面サイズや座標計算の共通ロジックを集約済み | 維持中心。盤面拡張時にテスト追加で対応する | 座標・初期位置・盤面列挙の共通処理がここを正本として維持されている | `Tests/GameTests/BoardGeometryTests.swift` |
| Game | `Game/GameModuleInterfaces.swift` | 完了 | UI からの `GameCore` 生成経路を一本化済み | 維持中心。依存注入の入口として保つ | `Game` 利用経路が分散せず、UI 側からの生成方法が統一されている | `docs/refactoring-task-board.md` |
| Services | `Services/AdsConsentCoordinator.swift` | 完了 | ATT/UMP の状態遷移を踏まえた同意制御とテストが整っている | 維持中心。シナリオ追加はテスト拡充で吸収する | 同意状態ごとの挙動が既存テストで守られ、設計の再分割を必要としない | `MonoKnightAppTests/AdsConsentCoordinatorTests.swift`、`docs/att-ump-consent-flow.md` |
| Services | `Services/StorageKeys.swift` | 完了 | 主要な `@AppStorage` / `UserDefaults` キー定義を集約済み | 維持中心。新規キー追加時の追記だけで済む | 保存キーの正本が一箇所に保たれ、文字列直書きの逆流が起きていない | `docs/refactor-plan.md` のベースライン整備 |

## 次に着手する順番

1. `Game/GameSceneSupport.swift`
2. `UI/RootView.swift`
3. `UI/GameViewModel.swift`
4. `MonoKnightApp.swift`
5. `Services/GameCenterService.swift`

上記 5 本柱を優先監視対象とし、着手した PR では本書の対象行も同時に更新する。
