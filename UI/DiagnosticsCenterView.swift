import SharedSupport  // DebugLogHistory や CrashFeedbackCollector を利用して診断ログを表示するため読み込む
import SwiftUI

/// 開発者向けにデバッグログとクラッシュ履歴を一覧表示する画面
/// - Important: TestFlight での運用を想定し、記録有無の切り替えや履歴の完全削除を UI から行えるようにしている。
@MainActor
struct DiagnosticsCenterView: View {
    /// 表示中のデバッグログ一覧
    @State private var logEntries: [DebugLogEntry] = DebugLogHistory.shared.snapshot()
    /// 表示中のクラッシュ・フィードバック履歴
    @State private var crashEvents: [CrashFeedbackEvent] = CrashFeedbackCollector.shared.recentEvents()
    /// フロントエンド向けログ保持の有効状態
    @State private var isCaptureEnabled: Bool = DebugLogHistory.shared.isFrontEndViewerEnabled
    /// ログ全消去の確認ダイアログ表示フラグ
    @State private var showingClearLogAlert = false
    /// クラッシュ履歴削除の確認ダイアログ表示フラグ
    @State private var showingClearCrashAlert = false
    /// 通知購読の解除に利用するトークン
    @State private var logObserver: NSObjectProtocol?
    @State private var crashObserver: NSObjectProtocol?

    /// 日付表示用のフォーマッタ（短時間で何度も生成するとパフォーマンスに響くため共有する）
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP_POSIX")
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter
    }()

    var body: some View {
        List {
            // MARK: - 収集設定セクション
            Section {
                Toggle("デバッグログを履歴に保持", isOn: $isCaptureEnabled)
                    .onChange(of: isCaptureEnabled) { _, newValue in
                        DebugLogHistory.shared.setFrontEndViewerEnabled(newValue)
                        logEntries = DebugLogHistory.shared.snapshot()
                    }
                Text("履歴保持を無効にすると記録済みログも消去され、公開ビルドでは利用者からアクセスできなくなります。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text("ログ記録")
            }

            // MARK: - デバッグログ一覧
            Section {
                if logEntries.isEmpty {
                    Text("記録されたデバッグログはありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(logEntries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(Self.timestampFormatter.string(from: entry.timestamp))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.message)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    }
                }
            } header: {
                Text("デバッグログ")
            } footer: {
                Button("デバッグログをすべて削除", role: .destructive) {
                    showingClearLogAlert = true
                }
                .disabled(logEntries.isEmpty)
            }

            // MARK: - クラッシュ・フィードバック履歴
            Section {
                if crashEvents.isEmpty {
                    Text("クラッシュやフィードバックの記録はありません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(crashEvents.reversed()) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Self.timestampFormatter.string(from: event.timestamp))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack {
                                Label(event.category.japaneseLabel, systemImage: symbol(for: event.category))
                                    .font(.callout)
                                Spacer()
                            }
                            Text(event.title)
                                .font(.headline)
                            Text(event.detail)
                                .font(.footnote.monospaced())
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 6)
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                    }
                }
            } header: {
                Text("クラッシュ / フィードバック")
            } footer: {
                Button("クラッシュ履歴を削除", role: .destructive) {
                    showingClearCrashAlert = true
                }
                .disabled(crashEvents.isEmpty)
            }
        }
        .navigationTitle("診断ログ")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    refreshAll()
                } label: {
                    Label("再読込", systemImage: "arrow.clockwise")
                }
                .accessibilityLabel(Text("最新のログを読み込み直す"))
            }
        }
        .alert("デバッグログを削除", isPresented: $showingClearLogAlert) {
            Button("削除する", role: .destructive) {
                DebugLogHistory.shared.clear()
                refreshLogEntries()
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("保持しているデバッグログをすべて削除します。この操作は取り消せません。")
        }
        .alert("クラッシュ履歴を削除", isPresented: $showingClearCrashAlert) {
            Button("削除する", role: .destructive) {
                CrashFeedbackCollector.shared.clearAll()
                refreshCrashEvents()
            }
            Button("キャンセル", role: .cancel) { }
        } message: {
            Text("記録済みのクラッシュおよびフィードバックイベントをすべて削除します。")
        }
        .onAppear {
            setupObserversIfNeeded()
            refreshAll()
        }
        .onDisappear {
            tearDownObservers()
        }
    }

    /// カテゴリに応じた SF Symbol 名を返す
    private func symbol(for category: CrashFeedbackEvent.Category) -> String {
        switch category {
        case .crash:
            return "exclamationmark.octagon.fill"
        case .feedback:
            return "bubble.left.and.exclamationmark"
        case .review:
            return "checkmark.seal"
        }
    }

    /// ログ履歴を最新状態へ更新する
    private func refreshLogEntries() {
        logEntries = DebugLogHistory.shared.snapshot()
    }

    /// クラッシュ履歴を最新状態へ更新する
    private func refreshCrashEvents() {
        crashEvents = CrashFeedbackCollector.shared.recentEvents()
    }

    /// ログとクラッシュ履歴をまとめて更新する
    private func refreshAll() {
        refreshLogEntries()
        refreshCrashEvents()
    }

    /// 通知購読を登録し、リアルタイムで UI を更新できるようにする
    private func setupObserversIfNeeded() {
        if logObserver == nil {
            logObserver = NotificationCenter.default.addObserver(
                forName: DebugLogHistory.didAppendEntryNotification,
                object: DebugLogHistory.shared,
                queue: .main
            ) { [weak self] _ in
                self?.refreshLogEntries()
            }
        }
        if crashObserver == nil {
            crashObserver = NotificationCenter.default.addObserver(
                forName: CrashFeedbackCollector.didAppendEventNotification,
                object: CrashFeedbackCollector.shared,
                queue: .main
            ) { [weak self] _ in
                self?.refreshCrashEvents()
            }
        }
    }

    /// 登録した通知購読を解除し、不要な更新を防ぐ
    private func tearDownObservers() {
        if let logObserver {
            NotificationCenter.default.removeObserver(logObserver)
            self.logObserver = nil
        }
        if let crashObserver {
            NotificationCenter.default.removeObserver(crashObserver)
            self.crashObserver = nil
        }
    }
}
