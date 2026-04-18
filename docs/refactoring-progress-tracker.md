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
| 完了 | 16 | 主責務の分離が完了し、今後は維持中心で進められるもの |
| 進行中 | 2 | 分割は始まっているが、継続監視が必要なもの |
| 未着手 | 0 | 主要対象として追加済みのものは未着手なし |
| 保留 | 0 | 現時点では該当なし |

## 主要対象ファイル一覧

| レイヤ | ファイル | 状態 | 現状 | 次の分割/整理先 | 完了条件 | 関連テスト/根拠 |
| --- | --- | --- | --- | --- | --- | --- |
| UI | `UI/RootView.swift` | 完了 | `RootView+GameFlow.swift`、`RootView+Diagnostics.swift`、`RootView+Shell.swift`、`RootViewStateStore.swift` へ責務別分割済みで、本体は依存注入・`StateObject` 保持・`body` 入口・初回認証 task にほぼ限定されている。toast/presentation glue と内部 state も shell support / facade store 側へ整理済み | 維持中心。app shell entry としての薄さを保ち、タイトル組み立て・presentation・state facade の逆流を防ぐ | `RootView.swift` 本体を読まずとも、タイトル組み立て・layout diagnostics・ルートイベント窓口・state facade・toast/presentation support を別責務として追える | `docs/refactor-plan.md` の責務表、`UI/RootView+GameFlow.swift`、`UI/RootView+Diagnostics.swift`、`UI/RootView+Shell.swift`、`UI/RootViewStateStore.swift`、`MonoKnightAppTests/RootViewCoordinatorTests.swift`、`MonoKnightAppTests/MonoKnightAppTests.swift`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| UI | `UI/GameViewModel.swift` | 完了 | `GameViewModelSupport.swift` 側へ input/core binding/session reset、service bridge、初期表示同期、公開 action / lifecycle 入口、shared UI type、state sync glue を整理済み。本体は GameCore の保持、公開 `@Published` state、initializer、最小 façade にほぼ限定されている | 維持中心。shared UI type や同期 helper を support 側へ保ち、状態更新の詳細が本体へ逆流しないよう監視する | `GameViewModel.swift` を読まずとも、入力/結果/ライフサイクル/サービス橋渡し/状態同期を別責務として追え、GameCore の窓口と公開 state の façade として安定している | `MonoKnightAppTests/GameViewIntegrationTests.swift`、`MonoKnightAppTests/GameViewModelTests.swift`、`UI/GameViewModelSupport.swift`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| Game | `Game/CampaignLibrary.swift` | 完了 | 本体は公開 API と chapter builder の組み立てに絞り、章定義は `CampaignLibrary+Chapter1.swift` 〜 `CampaignLibrary+Chapter8.swift` へ分割済み。共通 penalty / fixed spawn は shared helper へ集約した | 維持中心。章追加やバランス調整は該当 chapter source だけを触る運用を保つ | 章ごとの定義追加・調整が局所変更で済み、単一ファイル依存を避けられている | `Tests/GameTests/CampaignLibraryTests.swift`、`Tests/GameTests/GameModeIdentifierTests.swift`、`Tests/GameTests/DailyChallengeDefinitionTests.swift`、`swift test` |
| Game | `Game/GameSceneSupport.swift` | 完了 | `GameScene+LayoutSupport.swift`、`GameScene+DecorationRenderer.swift`、`GameScene+HighlightRenderer.swift`、`GameScene+KnightAnimator.swift`、`GameScene+AccessibilitySupport.swift` へ責務別分割済み。`GameSceneSupport.swift` 自体は shared support の薄い受け皿に縮退した | 維持中心。必要なら次段階で decoration renderer 内部の geometry/detail helper をさらに整理する | `GameScene` からの利用面を変えずに、layout / decoration / highlight / knight / accessibility の変更影響範囲がファイル単位で局所化されている | `MonoKnightAppTests/GameSceneAccessibilityTests.swift`、`MonoKnightAppTests/GameViewIntegrationTests.swift`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| App | `MonoKnightApp.swift` | 完了 | `MonoKnightApp+Bootstrap.swift` へ bootstrap、root composition、lifecycle sync を分離済みで、`ThemePreference` も独立ファイルへ移動した。本体は `@main` の入口、`scenePhase` 受け取り、`StateObject` 保持、`RootAppContent` 接続にほぼ限定されている | 維持中心。live/mock 依存束の契約と theme support の逆流を防ぐ | App 本体が Scene 接続専任として追え、bootstrap・consent gate・active 復帰同期・theme support の詳細が別責務として安定している | `MonoKnightAppTests/MonoKnightAppTests.swift`、`MonoKnightAppTests/GameSettingsStoreTests.swift`、`MonoKnightAppTests/AdsServiceCoordinatorIntegrationTests.swift`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| Services | `Services/GameCenterService.swift` | 完了 | `GameCenterAuthenticationCoordinator`、`GameCenterScoreSubmissionCoordinator`、`GameCenterLeaderboardPresenter` を同一ファイル内 private helper として整理し、本体は façade として公開 API 実装と状態公開にほぼ限定された。`GameCenterServiceTestHooks` でモジュール内テストだけ最小限差し替えられるようにしつつ、GameKit 依存は Services 層内へ閉じ込めている | 維持中心。新モード追加時も設定解決と leaderboard presenter へ局所追記する運用を保ち、UI へ SDK 詳細を逆流させない | `GameCenterService.swift` 本体を読まずとも、認証・スコア送信・ランキング提示・送信記録の責務を helper 単位で追え、公開契約を維持したままテストで主要分岐を固定できる | `MonoKnightAppTests/MonoKnightAppTests.swift`、`docs/game-center-leaderboards.md`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| UI | `UI/SettingsView.swift` | 完了 | `SettingsViewSections.swift` は section 定義専任、`SettingsViewSupport.swift` は action coordinator / alert state / debug unlock 制御の受け皿として整理済み。本体は `NavigationStack`、section 配線、alert 入口、toolbar に寄った | 維持中心。設定項目追加時も section と support へ局所的に追記する運用を保つ | 設定画面本体が screen shell として追え、購入復元・Game Center 再認証・privacy refresh・debug unlock の詳細が UI レイアウトへ逆流しない | `UI/SettingsViewSections.swift`、`UI/SettingsViewSupport.swift`、`MonoKnightAppTests/MonoKnightAppTests.swift`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| UI | `UI/GameView.swift` | 完了 | 描画以外の責務を `GameViewModel`、`GameBoardBridgeViewModel`、レイアウト補助へ移譲済み | 維持中心。大きな再分割は前提としない | View 本体が描画と組み立てに集中し、状態管理の追加逆流が起きていない | `docs/refactoring-task-board.md`、`MonoKnightAppTests/GameViewLayoutCalculatorTests.swift` |
| UI | `UI/GameBoardBridgeViewModel.swift` | 完了 | SwiftUI と SpriteKit の橋渡し責務が独立し、状態管理の境界が明確 | 維持中心。描画連携の窓口として安定運用する | GameView 側へ SpriteKit 詳細を再流入させずに拡張できる | `docs/refactoring-task-board.md`、`MonoKnightAppTests/GameBoardBridgeViewModelHighlightTests.swift` |
| Game | `Game/BoardGeometry.swift` | 完了 | 盤面サイズや座標計算の共通ロジックを集約済み | 維持中心。盤面拡張時にテスト追加で対応する | 座標・初期位置・盤面列挙の共通処理がここを正本として維持されている | `Tests/GameTests/BoardGeometryTests.swift` |
| Game | `Game/GameMode.swift` | 完了 | `GameMode+Presentation.swift` へ表示文言、`GameMode+RegulationSupport.swift` へ `Regulation` の validation / Codable / tile effect 合成、`GameMode+BuiltIn.swift` へ built-in mode 生成を分離し、本体は公開型定義・主要公開プロパティ・`Equatable` の façade に整理済み | 維持中心。新モード追加時は built-in helper か presentation / regulation support 側へ局所変更し、定義本体へロジックを逆流させない | `GameMode.swift` 本体を読まずとも、表示・built-in 生成・Regulation 補助の責務が別ファイルで追え、公開契約を維持したままテストで encode/decode・fallback・文言を固定できる | `Tests/GameTests/GameModeIdentifierTests.swift`、`Tests/GameTests/GameModePenaltyTests.swift`、`Tests/GameTests/GameModeRegulationTests.swift`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| Game | `Game/CampaignStage.swift` | 完了 | 本体は公開データ構造と initializer にほぼ限定され、表示は `CampaignStage+Presentation.swift`、評価は `CampaignStage+Evaluation.swift`、進行用変換は `CampaignStage+Progression.swift` へ分離済み | 維持中心。ステージ追加時は定義元を触りつつ、表示文言・評価・`GameMode` 変換の逆流を防ぐ | `CampaignStage.swift` を読まずとも、表示・評価・進行用変換を別ファイルで追え、本体がデータ定義の façade として安定している | `Tests/GameTests/CampaignStagePresentationTests.swift`、`Tests/GameTests/GameModeIdentifierTests.swift`、`MonoKnightAppTests/CampaignStageSelectionViewTests.swift`、`swift test` |
| UI | `UI/GameViewModelSupport.swift` | 完了 | state sync glue は `GameViewModelSupport.swift` に残しつつ、action / lifecycle surface を `GameViewModel+InputActions.swift`、`GameViewModel+FlowActions.swift`、`GameViewModel+Lifecycle.swift`、`GameViewModel+Bindings.swift` へ責務別に分割済み。既存の presentation / interaction / lifecycle helper type 群とも役割境界が揃い、support 本体は最小共通補助へ縮退した | 維持中心。新しい action 追加時は責務に対応する extension file へ寄せ、state sync glue へ逆流させない | `GameViewModelSupport.swift` を読まずとも、入力・結果/遷移・設定/ライフサイクル同期・GameCore binding をファイル単位で追え、`GameViewModel.swift` は façade のまま維持されている | `MonoKnightAppTests/GameViewIntegrationTests.swift`、`MonoKnightAppTests/GameViewModelTests.swift`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| Game | `Game/MoveCard.swift` | 完了 | `MoveCard+Registry.swift` へ集合定義、`MoveCard+Presentation.swift` へ表示メタデータ、`MoveCard+PatternSupport.swift` へ `MovePattern` 本体、`MoveCard+Resolution.swift` へ registry・解決・テスト override を分離済みで、本体は case 定義と公開 façade に整理された | 維持中心。新カード追加時は pattern support / resolution / presentation の責務境界を保ち、本体へロジックを逆流させない | `MoveCard.swift` を読まずとも、公開 enum・pattern 実装・registry 解決・表示責務を別ファイルで追え、既存 API を維持したまま回帰テストで fallback 順序と override 優先を固定できる | `Tests/GameTests/DeckTests.swift`、`Tests/GameTests/BoardMovementTests.swift`、`Tests/GameTests/GameCoreAvailableMovesTests.swift`、`Tests/GameTests/GameCoreFixedWarpCardTests.swift`、`Tests/GameTests/MoveCardPresentationTests.swift`、`Tests/GameTests/MoveCardResolutionTests.swift`、`swift test` |
| UI | `UI/Theme/AppTheme.swift` | 進行中 | `AppTheme+Badges.swift`、`AppTheme+Cards.swift`、`AppTheme+Chrome.swift`、`AppTheme+Board.swift`、`AppTheme+PlatformBridge.swift` へ用途別トークンを分離し、本体はベースカラーとカラースキーム解決の入口に整理した | 必要なら card / board 系で再利用補助を追加しつつ、色値そのものは変えずに extension 単位の調整性を高める | API 名は維持したまま責務は薄くなったが、UI 見た目変更時の変更履歴をもう少し extension 単位で安定運用したい | `MonoKnightAppTests/GameViewIntegrationTests.swift`、`UI/Theme/AppTheme+*.swift`、`swift test`、`xcodebuild -scheme MonoKnightApp -project MonoKnight.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build` |
| Game | `Game/GameModuleInterfaces.swift` | 完了 | UI からの `GameCore` 生成経路を一本化済み | 維持中心。依存注入の入口として保つ | `Game` 利用経路が分散せず、UI 側からの生成方法が統一されている | `docs/refactoring-task-board.md` |
| Services | `Services/AdsConsentCoordinator.swift` | 完了 | ATT/UMP の状態遷移を踏まえた同意制御とテストが整っている | 維持中心。シナリオ追加はテスト拡充で吸収する | 同意状態ごとの挙動が既存テストで守られ、設計の再分割を必要としない | `MonoKnightAppTests/AdsConsentCoordinatorTests.swift`、`docs/att-ump-consent-flow.md` |
| Services | `Services/StorageKeys.swift` | 完了 | 主要な `@AppStorage` / `UserDefaults` キー定義を集約済み | 維持中心。新規キー追加時の追記だけで済む | 保存キーの正本が一箇所に保たれ、文字列直書きの逆流が起きていない | `docs/refactor-plan.md` のベースライン整備 |

## 次に着手する順番

1. `UI/Theme/AppTheme.swift` は extension 単位の運用を継続し、テーマ調整時に責務逆流がないか監視する。

上記の進行中ファイルを優先監視対象とし、着手した PR では本書の対象行も同時に更新する。
