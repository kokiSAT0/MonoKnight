import SwiftUI
import Game
import SharedSupport

/// キャンペーンのステージ一覧を表示し、挑戦するステージを選択するビュー
struct CampaignStageSelectionView: View {
    /// ステージ定義
    let campaignLibrary: CampaignLibrary
    /// 進捗ストア
    @ObservedObject var progressStore: CampaignProgressStore
    /// 既に選択済みのステージ
    let selectedStageID: CampaignStageID?
    /// クローズハンドラ
    let onClose: () -> Void
    /// ナビゲーションバーに閉じるボタンを表示するかどうか
    let showsCloseButton: Bool
    /// ステージ決定時のハンドラ
    let onSelectStage: (CampaignStage) -> Void

    /// テーマカラー
    private var theme = AppTheme()

    /// メンバーごとの初期化処理を明示しておき、外部ファイルからの生成時にアクセスレベルの問題が発生しないようにする
    /// - Parameters:
    ///   - campaignLibrary: キャンペーンの章とステージ情報
    ///   - progressStore: 進捗管理を担当するストア（ObservableObject）
    ///   - selectedStageID: すでに選択済みのステージ ID
    ///   - onClose: ビューを閉じるためのコールバック
    ///   - onSelectStage: ステージ選択確定時に呼び出されるコールバック
    ///   - showsCloseButton: ナビゲーションバーへ「閉じる」ボタンを表示するかどうか
    init(
        campaignLibrary: CampaignLibrary,
        progressStore: CampaignProgressStore,
        selectedStageID: CampaignStageID?,
        onClose: @escaping () -> Void,
        onSelectStage: @escaping (CampaignStage) -> Void,
        showsCloseButton: Bool = true
    ) {
        // @ObservedObject プロパティはラッパー経由で代入する必要があるため、明示的に初期化する
        self.campaignLibrary = campaignLibrary
        _progressStore = ObservedObject(wrappedValue: progressStore)
        self.selectedStageID = selectedStageID
        self.onClose = onClose
        self.onSelectStage = onSelectStage
        self.showsCloseButton = showsCloseButton
    }

    var body: some View {
        Group {
            if campaignLibrary.chapters.isEmpty {
                emptyStateView
            } else {
                stageListView
            }
        }
        .navigationTitle("キャンペーン")
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { onClose() }
                }
            }
        }
    }

    /// ステージ行の描画
    /// - Parameter stage: 表示対象のステージ
    /// - Returns: ステージを選択するためのボタン
    private func stageRow(for stage: CampaignStage) -> some View {
        let isUnlocked = progressStore.isStageUnlocked(stage)
        let earnedStars = progressStore.progress(for: stage.id)?.earnedStars ?? 0
        let isSelected = stage.id == selectedStageID

        return Button {
            guard isUnlocked else { return }
            debugLog("CampaignStageSelectionView: ステージを選択 -> \(stage.id.displayCode)")
            onSelectStage(stage)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(stage.displayCode)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(theme.backgroundElevated.opacity(0.8))
                        )
                        .foregroundColor(theme.textPrimary)
                    Text(stage.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(theme.accentPrimary)
                            .font(.system(size: 18, weight: .bold))
                    } else if !isUnlocked {
                        Image(systemName: "lock.fill")
                            .foregroundColor(theme.textSecondary.opacity(0.7))
                            .font(.system(size: 15, weight: .medium))
                    }
                }

                Text(stage.summary)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundColor(theme.textSecondary)

                starIcons(for: earnedStars)

                if let objective = stage.secondaryObjectiveDescription {
                    Text("★2: \(objective)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textSecondary.opacity(0.85))
                }

                if let scoreText = stage.scoreTargetDescription {
                    Text("★3: \(scoreText)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textSecondary.opacity(0.85))
                }

                if !isUnlocked {
                    Text("解放条件: \(stage.unlockDescription)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(theme.accentPrimary)
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
    }

    /// 星アイコンを生成する
    /// - Parameter earnedStars: 獲得済みの星の数
    /// - Returns: 星 3 つの並び
    private func starIcons(for earnedStars: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < earnedStars ? "star.fill" : "star")
                    .foregroundColor(index < earnedStars ? theme.accentPrimary : theme.textSecondary.opacity(0.6))
            }
        }
        .accessibilityLabel("スター獲得数: \(earnedStars) / 3")
        .padding(.top, 4)
    }

    /// 章とステージが正しく読み込めた場合の一覧表示
    /// - Returns: 既存仕様と同じスタイルの List
    @ViewBuilder
    private var stageListView: some View {
        List {
            ForEach(campaignLibrary.chapters) { chapter in
                Section {
                    ForEach(chapter.stages) { stage in
                        stageRow(for: stage)
                    }
                } header: {
                    Text("Chapter \(chapter.id) \(chapter.title)")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                } footer: {
                    Text(chapter.summary)
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// キャンペーン情報のロードに失敗した際に表示する案内ビュー
    /// - Returns: 再試行導線を含む縦方向の案内
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            // ユーザーへ発生状況を説明するメインメッセージ
            Text("ステージ情報を読み込めませんでした")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .multilineTextAlignment(.center)

            // 状況を補足し再試行の導線を案内するサブメッセージ
            Text("通信状況をご確認のうえ、画面を閉じて再度開き直してください。")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

            // 再試行用のボタン。閉じるハンドラを通じて呼び出し元へ制御を戻す
            Button {
                debugLog("CampaignStageSelectionView: キャンペーンライブラリが空のため再試行ボタンからクローズを要求")
                onClose()
            } label: {
                Text("閉じて再試行")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.accentOnPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(theme.accentPrimary)
                    )
            }
            .accessibilityLabel("キャンペーン画面を閉じて再読み込みを試す")
            .padding(.horizontal, 32)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundPrimary)
        .onAppear {
            // データ欠落の発生タイミングを把握するためログを出力
            debugLog("CampaignStageSelectionView: campaignLibrary.chapters が空のためエンプティビューを表示")
        }
    }

}

