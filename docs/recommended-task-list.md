# 今後の開発おすすめタスク一覧

<!-- このファイルは今後の開発タスクをおすすめの程度別に整理したものです -->
<!-- コメントアウトは読みやすさを高めるため日本語で詳しく記載しています -->

## 必須（優先度: 高）
<!-- 正式リリース直前に必ず完了させたいクリティカルタスク群 -->
- [ ] TestFlight ビルドでの総合 QA<!-- Game Center 送信・広告除去 IAP・ATT/UMP 同意フローの通し確認を行い、リリースチェックリストの必須項目を埋める。`docs/att-ump-consent-flow.md` の状態表を参照しつつ実端末で検証する -->
- [ ] App Store Connect のメタデータ最終更新<!-- プライバシー回答・広告設定・スクリーンショットを最新仕様へ合わせ、審査リジェクト要因を排除する -->
- [ ] Info.plist / xcconfig の本番値整備<!-- 本番用 ID（Leaderboard / AdMob / IAP）を xcconfig 経由で管理し、テンプレートとの差分を確認できるようにする -->

## 推奨（優先度: 中）
<!-- リリース後の改善も見据えた優先タスク群 -->
- [ ] `GameViewModel` / `GameBoardBridgeViewModel` の統合テスト整備<!-- `GameViewLayoutCalculatorTests` に続き、Combine 購読やハプティクス制御をモック化して自動テストで検証できるようにする -->
- [ ] `BoardLayoutSnapshot` ログの閲覧導線を整備<!-- 設定画面に開発者メニューを設け、レイアウト関連ログを `DebugLogHistory` へ蓄積した内容から即座に確認できるようにする -->
- [ ] エラーハンドリングとログポリシーの整理<!-- `SharedSupport` の `DebugLogHistory` / `CrashFeedbackCollector` を活用し、サービス層のログ粒度と公開ビルドでの無効化手順を明文化する -->
- [ ] 広告頻度と同意 UI の UX 検証<!-- インターバルや再表示タイミングをユーザーテストで検証し、ATT/UMP の結果を `AdsConsentCoordinator` からログ出力して回帰分析を容易にする -->

## 完了済み（参考）
<!-- タスク棚卸しの結果、完了したものはここで記録しておく -->
- [x] ATT / UMP 状態遷移ドキュメント整備<!-- `docs/att-ump-consent-flow.md` を作成し、`AdsConsentCoordinator` / `AdsService` へ反映 -->
- [x] リファクタリング品質チェックリストの策定<!-- `docs/refactoring-quality-checklist.md` に PR 向けの必須確認項目を整理 -->
- [x] GameView の責務分割<!-- `GameViewModel`・`GameBoardBridgeViewModel`・`GameViewLayoutCalculator` を導入し、レイアウトテストとログ診断の仕組みを整備 -->

## アイデア（優先度: 低）
<!-- 余裕があるときに検討したい拡張アイデア -->
- [ ] デイリーチャレンジの追加<!-- シード共有によりリプレイ性を高める -->
- [ ] iPad や英語対応の検討<!-- 将来的な市場拡大を視野に入れる -->
- [ ] テーマ配色のカスタマイズ機能<!-- ユーザーの好みに合わせた見た目を提供する -->
