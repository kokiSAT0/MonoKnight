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
| 完了 | 11 | 主責務の分離が完了し、今後は維持中心で進められるもの |
| 進行中 | 2 | 分割は始まっているが、継続監視が必要なもの |
| 未着手 | 0 | 大きい責務集中が残っているもの |
| 保留 | 0 | 現時点では該当なし |

## 主要対象ファイル一覧

| レイヤ | ファイル | 状態 | 現状 | 次の分割/整理先 | 完了条件 | 関連テスト/根拠 |
| --- | --- | --- | --- | --- | --- | --- |
| UI | `UI/RootView.swift` | 完了 | `RootView+GameFlow.swift`、`RootView+Diagnostics.swift`、`RootView+Shell.swift`、`RootViewStateStore.swift` へ責務別分割済みで、本体は依存注入・`StateObject` 保持・`body` 入口・初回認証 task にほぼ限定されている。toast/presentation glue と内部 state も shell support / facade store 側へ整理済み | 維持中心。app shell entry としての薄さを保ち、タイトル組み立て・presentation・state facade の逆流を防ぐ | `RootView.swift` 本体を読まずとも、タイトル組み立て・layout diagnostics・ルートイベント窓口・state facade・toast/presentation support を別責務として追える | `docs/refactor-plan.md` の責務表、`UI/RootView+GameFlow.swift`、`UI/RootView+Diagnostics.swift`、`UI/RootView+Shell.swift`、`UI/RootViewStateStore.swift`、`MonoKnightAppTests/RootViewCoordinatorTests.swift`、`MonoKnightAppTests/MonoKnightAppTests.swift`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| UI | `UI/GameViewModel.swift` | 進行中 | `SessionUIState`、`ResultPresentationState`、input/core binding/session reset、service bridge、初期表示同期に加え、公開 action / lifecycle 入口も `GameViewModelSupport.swift` 側の split-file extension へ寄せ済み。本体は stored state と同期 façade が中心になった | 現構成を維持しつつ、残る監視は最小限に留める。次の主対象は `Services/GameCenterService.swift` へ移す | `GameViewModel.swift` が GameCore の窓口・状態保持・同期 façade にほぼ限定され、入力/結果/ライフサイクル/サービス橋渡しの詳細が補助型へ逆流しない | `MonoKnightAppTests/GameViewIntegrationTests.swift`、`MonoKnightAppTests/GameViewModelTests.swift`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| Game | `Game/CampaignLibrary.swift` | 完了 | 本体は公開 API と chapter builder の組み立てに絞り、章定義は `CampaignLibrary+Chapter1.swift` 〜 `CampaignLibrary+Chapter8.swift` へ分割済み。共通 penalty / fixed spawn は shared helper へ集約した | 維持中心。章追加やバランス調整は該当 chapter source だけを触る運用を保つ | 章ごとの定義追加・調整が局所変更で済み、単一ファイル依存を避けられている | `Tests/GameTests/CampaignLibraryTests.swift`、`Tests/GameTests/GameModeIdentifierTests.swift`、`Tests/GameTests/DailyChallengeDefinitionTests.swift`、`swift test` |
| Game | `Game/GameSceneSupport.swift` | 完了 | `GameScene+LayoutSupport.swift`、`GameScene+DecorationRenderer.swift`、`GameScene+HighlightRenderer.swift`、`GameScene+KnightAnimator.swift`、`GameScene+AccessibilitySupport.swift` へ責務別分割済み。`GameSceneSupport.swift` 自体は shared support の薄い受け皿に縮退した | 維持中心。必要なら次段階で decoration renderer 内部の geometry/detail helper をさらに整理する | `GameScene` からの利用面を変えずに、layout / decoration / highlight / knight / accessibility の変更影響範囲がファイル単位で局所化されている | `MonoKnightAppTests/GameSceneAccessibilityTests.swift`、`MonoKnightAppTests/GameViewIntegrationTests.swift`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| App | `MonoKnightApp.swift` | 完了 | `MonoKnightApp+Bootstrap.swift` へ bootstrap、root composition、lifecycle sync を分離済みで、`ThemePreference` も独立ファイルへ移動した。本体は `@main` の入口、`scenePhase` 受け取り、`StateObject` 保持、`RootAppContent` 接続にほぼ限定されている | 維持中心。live/mock 依存束の契約と theme support の逆流を防ぐ | App 本体が Scene 接続専任として追え、bootstrap・consent gate・active 復帰同期・theme support の詳細が別責務として安定している | `MonoKnightAppTests/MonoKnightAppTests.swift`、`MonoKnightAppTests/GameSettingsStoreTests.swift`、`MonoKnightAppTests/AdsServiceCoordinatorIntegrationTests.swift`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| Services | `Services/GameCenterService.swift` | 進行中 | leaderboard config は `Info.plist <- xcconfig` 解決へ寄せ、submission state と presentation helper も内部整理済み。公開 API は維持したまま test 固定値の `FIXME` は解消したが、GameKit 依存の詳細は引き続き監視対象 | 現構成を維持しつつ、必要なら authentication / presentation の残存詳細をさらに薄くする | リーダーボード定義がコード直書きに戻らず、config・送信状態・表示フローの責務が局所化されている | `MonoKnightAppTests/MonoKnightAppTests.swift`、`docs/game-center-leaderboards.md`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| UI | `UI/SettingsView.swift` | 完了 | `SettingsViewSections.swift` は section 定義専任、`SettingsViewSupport.swift` は action coordinator / alert state / debug unlock 制御の受け皿として整理済み。本体は `NavigationStack`、section 配線、alert 入口、toolbar に寄った | 維持中心。設定項目追加時も section と support へ局所的に追記する運用を保つ | 設定画面本体が screen shell として追え、購入復元・Game Center 再認証・privacy refresh・debug unlock の詳細が UI レイアウトへ逆流しない | `UI/SettingsViewSections.swift`、`UI/SettingsViewSupport.swift`、`MonoKnightAppTests/MonoKnightAppTests.swift`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| UI | `UI/GameView.swift` | 完了 | 描画以外の責務を `GameViewModel`、`GameBoardBridgeViewModel`、レイアウト補助へ移譲済み | 維持中心。大きな再分割は前提としない | View 本体が描画と組み立てに集中し、状態管理の追加逆流が起きていない | `docs/refactoring-task-board.md`、`MonoKnightAppTests/GameViewLayoutCalculatorTests.swift` |
| UI | `UI/GameBoardBridgeViewModel.swift` | 完了 | SwiftUI と SpriteKit の橋渡し責務が独立し、状態管理の境界が明確 | 維持中心。描画連携の窓口として安定運用する | GameView 側へ SpriteKit 詳細を再流入させずに拡張できる | `docs/refactoring-task-board.md`、`MonoKnightAppTests/GameBoardBridgeViewModelHighlightTests.swift` |
| Game | `Game/BoardGeometry.swift` | 完了 | 盤面サイズや座標計算の共通ロジックを集約済み | 維持中心。盤面拡張時にテスト追加で対応する | 座標・初期位置・盤面列挙の共通処理がここを正本として維持されている | `Tests/GameTests/BoardGeometryTests.swift` |
| Game | `Game/GameModuleInterfaces.swift` | 完了 | UI からの `GameCore` 生成経路を一本化済み | 維持中心。依存注入の入口として保つ | `Game` 利用経路が分散せず、UI 側からの生成方法が統一されている | `docs/refactoring-task-board.md` |
| Services | `Services/AdsConsentCoordinator.swift` | 完了 | ATT/UMP の状態遷移を踏まえた同意制御とテストが整っている | 維持中心。シナリオ追加はテスト拡充で吸収する | 同意状態ごとの挙動が既存テストで守られ、設計の再分割を必要としない | `MonoKnightAppTests/AdsConsentCoordinatorTests.swift`、`docs/att-ump-consent-flow.md` |
| Services | `Services/StorageKeys.swift` | 完了 | 主要な `@AppStorage` / `UserDefaults` キー定義を集約済み | 維持中心。新規キー追加時の追記だけで済む | 保存キーの正本が一箇所に保たれ、文字列直書きの逆流が起きていない | `docs/refactor-plan.md` のベースライン整備 |

## 次に着手する順番

1. `UI/GameViewModel.swift`
2. `Services/GameCenterService.swift`

上記の進行中ファイルを優先監視対象とし、着手した PR では本書の対象行も同時に更新する。
