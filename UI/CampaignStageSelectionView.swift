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
    /// 展開中の章 ID を保持し、Disclosure 表現の開閉状態を制御する
    @State private var expandedChapters: Set<Int> = []

    init(
        campaignLibrary: CampaignLibrary,
        progressStore: CampaignProgressStore,
        selectedStageID: CampaignStageID?,
        onClose: @escaping () -> Void,
        onSelectStage: @escaping (CampaignStage) -> Void,
        showsCloseButton: Bool = true
    ) {
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
                CampaignStageSelectionEmptyState(
                    theme: theme,
                    chapterCount: campaignLibrary.chapters.count,
                    stageCount: campaignLibrary.allStages.count,
                    onClose: onClose
                )
                .onAppear {
                    debugLog("CampaignStageSelectionView.body: 章数=\(campaignLibrary.chapters.count) ステージ総数=\(campaignLibrary.allStages.count) -> emptyStateView を表示")
                }
            } else {
                CampaignStageSelectionListView(
                    campaignLibrary: campaignLibrary,
                    progressStore: progressStore,
                    selectedStageID: selectedStageID,
                    theme: theme,
                    expandedChapters: $expandedChapters,
                    onSelectStage: onSelectStage
                )
                .onAppear {
                    debugLog("CampaignStageSelectionView.body: 章数=\(campaignLibrary.chapters.count) ステージ総数=\(campaignLibrary.allStages.count) -> stageListView を表示")
                }
            }
        }
        .navigationTitle("キャンペーン")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                CampaignStageSelectionBackButton(onClose: onClose)
            }
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    CampaignStageSelectionCloseButton(onClose: onClose)
                }
            }
        }
        .onAppear {
            let unlockedCount = campaignLibrary.allStages.filter { progressStore.isStageUnlocked($0) }.count
            let chapterSummaries = campaignLibrary.chapters
                .map { chapter in "Chapter \(chapter.id):\(chapter.stages.count)" }
                .joined(separator: ", ")
            let selectedDescription = selectedStageID?.displayCode ?? "なし"
            debugLog("CampaignStageSelectionView: onAppear -> ステージ総数=\(campaignLibrary.allStages.count) 解放済=\(unlockedCount) 章内訳=[\(chapterSummaries)] 選択中=\(selectedDescription)")
            if campaignLibrary.chapters.isEmpty {
                debugLog("CampaignStageSelectionView: 章定義が空です。CampaignLibrary.buildChapters() の戻り値を確認してください。")
            }
        }
        .onDisappear {
            debugLog("CampaignStageSelectionView: onDisappear")
        }
    }
}
