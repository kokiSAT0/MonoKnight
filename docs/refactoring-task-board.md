# リファクタリングタスクボード

<!-- この表はリファクタリング指針に基づく優先タスクを管理するためのもの -->
<!-- コメントは全て日本語で記載し、読みやすさを重視している -->

| 優先度 | 区分 | タスク内容 | 状態 | 備考 |
|:------:|:----|:-----------|:----:|:-----|
| 高     | UI | `GameBoardBridgeViewModel` と `GameViewModel` の統合テストを整備し、アニメーションとハイライトの回帰を検知する | [x] | <!-- ViewModel 切り出し後の安定性を担保する最優先タスク -->`MonoKnightAppTests/GameViewIntegrationTests.swift` にペナルティバナー／SpriteKit 連携の自動テストを追加し、Combine 購読と `DispatchWorkItem` のキャンセルを検証済み |
| 中     | UI | `BoardLayoutSnapshot` のログを設定画面の開発者メニューから閲覧できるようにし、レイアウト診断を迅速化する | [x] | <!-- レイアウトログの活用度を高める -->`SettingsView` の開発者メニューから `DiagnosticsCenterView` へ遷移できるよう実装し、`DebugLogHistory` に蓄積されたレイアウトログへ即座にアクセス可能 |
| 中     | 共通基盤 | `SharedSupport` の `DebugLogHistory` / `CrashFeedbackCollector` を UI から制御できる管理画面を整備する | [x] | <!-- TestFlight での運用を視野に入れた拡張 -->`DiagnosticsCenterView` で履歴閲覧・削除・保持切替を提供し、環境変数で公開ビルドから非表示にできる運用ガードを追加済み |
| 高     | UI | `GameView` の責務を ViewModel 層へ移譲し、描画とロジックの境界を明確化する | [x] | <!-- 1 ファイルに集中している状態管理を分離し、クラッシュリスクを減らす -->`GameViewModel`・`GameBoardBridgeViewModel`・`GameViewLayoutCalculator` を導入し、アニメーション制御とサービス呼び出しを分離済み |
| 高     | サービス | `AdsConsentCoordinator` と `AdsService` の統合テストシナリオを整備し、同意状態ごとの挙動を自動検証する | [x] | <!-- ATT/UMP 周りの回帰を防ぐ重要タスク -->ダミー環境とログ検証を組み合わせて QA を効率化し、ATT 連携を考慮した再実装を完了 |
| 中     | ゲームコア | モード定義 (`GameMode`) のパラメータをドキュメント化し、Free モードとの整合性チェックを自動化する | [x] | <!-- 盤面サイズ追加時の破綻を防ぐ -->`docs/game-mode-parameters.md` に仕様を整理し、`FreeModeRegulationStoreTests` で自動検証を追加済み |

| 高     | ゲームコア | `Game` パッケージの依存関係棚卸しと公開 API の命名・アクセス制御見直し | [x] | <!-- UI からの利用方法統一を狙う重要タスク -->`GameModuleInterfaces` を導入し、UI からの `GameCore` 生成経路を一本化 |
| 高     | ゲームコア | 盤面サイズや座標計算の定数を抽象化し、ユーティリティとして切り出す | [x] | <!-- 将来の盤面拡張を想定した設計 -->`BoardGeometry` ユーティリティで共通化し、関連テストも拡充済み |
| 高     | UI | SwiftUI と SpriteKit の橋渡し層に ViewModel を導入して状態管理を整理 | [x] | <!-- 状態の単一責務化で不具合を防ぐ -->`GameBoardBridgeViewModel` を新設し、描画更新とゲーム状態を分離 |
| 高     | サービス | StoreKit・Game Center・AdMob の共通プロトコル整備とモック実装作成 | [x] | <!-- 非同期処理の標準化で信頼性を高める -->依存注入を共通化し、UI からプロトコル経由でサービスを操作できる状態を確認済み |
| 中     | サービス | ATT・UMP の状態遷移をドキュメント化し、コードへ反映 | [x] | <!-- 審査対応を想定した整合性確保 -->`docs/att-ump-consent-flow.md` に状態遷移表を追記し、`AdsConsentCoordinator` で ATT を考慮するよう更新済み |
| 中     | ドキュメント | `docs/recommended-task-list.md` を更新して負債棚卸し結果を反映 | [x] | <!-- タスクの可視化を最新に保つ -->同意フロー整備完了の反映と次アクションの棚卸し |
| 中     | プロセス | リファクタリング後に `swift test` 実行を必須とするチェックリストを整備 | [x] | <!-- 品質基準を自動化 -->`docs/refactoring-quality-checklist.md` を追加し、PR 単位での確認項目を明文化 |
| 低     | 運用 | リファクタリング効果をクラッシュログ・フィードバックで定期検証 | [x] | <!-- スプリント末の見直しタスク -->`CrashFeedbackCollector` を導入し、自動ログ出力とレビュー履歴を保存 |
