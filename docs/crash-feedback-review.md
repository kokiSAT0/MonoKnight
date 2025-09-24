# クラッシュログ・フィードバック定期検証ガイド

<!-- リファクタリング後の安定度を把握するため、クラッシュログとフィードバックを定期レビューする手順をまとめる -->

## 目的
- `CrashFeedbackCollector` で蓄積したクラッシュ情報・フィードバックを定期的に振り返り、リファクタリングの影響を定量的に確認する。
- TestFlight / 実機で発生した問題を素早く察知し、追加の改善計画へ繋げる。

## 収集方法の概要
1. **自動収集**
   - `ErrorReporter` が未捕捉例外や致命的シグナルを検知すると `CrashFeedbackCollector` へ記録する。
   - `MonoKnightApp` がフォアグラウンドへ復帰するたびに `logSummary(label:latestCount:)` を呼び、最新状況を `debugLog` へ出力する。
   - 直近に未確認のクラッシュやフィードバックがあれば `markReviewCompletedIfNeeded` がレビュー履歴を追加する。
2. **手動収集**
   - 開発チームやサポート窓口から得た問い合わせ内容は `recordUserFeedback(source:message:metadata:)` で追記する。
   - 端末名・OS バージョン・発生手順などのメタデータを合わせて保存しておくと調査が容易になる。

## レビュー手順（週次・スプリント末）
1. Xcode の `Console` で `CrashFeedbackCollector` のログを確認し、クラッシュ件数・最終発生日を把握する。
2. 追加調査が必要なイベントがあれば `CrashFeedbackCollector.shared.recentEvents(limit:)` で詳細を取得する。
3. 調査完了後は `markReviewCompletedIfNeeded(note:reviewer:)` を呼び、レビュー済みであることを履歴へ残す。
4. 調査により判明した改善点があれば `docs/recommended-task-list.md` へ次アクションとして記録する。

## 便利なユーティリティ呼び出し例
```swift
// 直近 5 件のイベントを Swift REPL やデバッグコンソールで確認
let events = CrashFeedbackCollector.shared.recentEvents(limit: 5)
for event in events {
    print("[\(event.category.rawValue)]", event.timestamp, event.title)
    print(event.detail)
}

// 手動レビューを記録（レビュー済みイベントがある場合のみ追加）
CrashFeedbackCollector.shared.markReviewCompletedIfNeeded(
    note: "スプリント 12 の QA でクラッシュ再発無しを確認",
    reviewer: "QA チーム"
)
```

## 注意事項
- 履歴の保存上限は `maximumStoredEvents` で調整可能。古い履歴が不要になったら `clearAll()` でリセットしてから再取得する。
- JSON 保存が失敗した場合は `debugLog` に警告が残るため、ディスク使用量や `UserDefaults` の状態を確認する。
- 公開ビルドでは個人情報を記録しないよう注意し、匿名化されたログのみを取り扱う。
