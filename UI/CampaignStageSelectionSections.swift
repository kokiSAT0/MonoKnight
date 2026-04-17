import SwiftUI
import Game
import SharedSupport

struct CampaignStageSelectionListView: View {
    let campaignLibrary: CampaignLibrary
    @ObservedObject var progressStore: CampaignProgressStore
    let selectedStageID: CampaignStageID?
    let theme: AppTheme
    @Binding var expandedChapters: Set<Int>
    let onSelectStage: (CampaignStage) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20, pinnedViews: []) {
                ForEach(campaignLibrary.chapters) { chapter in
                    CampaignChapterSection(
                        chapter: chapter,
                        progressStore: progressStore,
                        selectedStageID: selectedStageID,
                        theme: theme,
                        isExpanded: expandedChapters.contains(chapter.id),
                        onToggle: { toggleChapterExpansion(for: chapter) },
                        onSelectStage: onSelectStage
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(theme.backgroundPrimary)
        .onAppear {
            let chapterDetails = campaignChapterDetailsDescription(library: campaignLibrary)
            debugLog("CampaignStageSelectionView.stageListView: 表示対象章一覧 = [\(chapterDetails)]")
            if expandedChapters.isEmpty {
                let targetChapterIDs = chapterIDsWithUnlockedUnclearedStages(
                    library: campaignLibrary,
                    progressStore: progressStore
                )
                if targetChapterIDs.isEmpty {
                    debugLog("CampaignStageSelectionView.stageListView: 初期展開対象が見つからず、展開状態を変更しませんでした")
                } else {
                    expandedChapters = targetChapterIDs
                    debugLog("CampaignStageSelectionView.stageListView: 初期展開章 ID を \(targetChapterIDs.sorted()) に設定（未クリア解放ステージを優先）")
                }
            }
        }
    }

    private func toggleChapterExpansion(for chapter: CampaignChapter) {
        if expandedChapters.contains(chapter.id) {
            expandedChapters.remove(chapter.id)
            debugLog("CampaignStageSelectionView: Chapter \(chapter.id) を折りたたみ")
        } else {
            expandedChapters.insert(chapter.id)
            debugLog("CampaignStageSelectionView: Chapter \(chapter.id) を展開")
        }
    }
}

struct CampaignChapterSection: View {
    let chapter: CampaignChapter
    @ObservedObject var progressStore: CampaignProgressStore
    let selectedStageID: CampaignStageID?
    let theme: AppTheme
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSelectStage: (CampaignStage) -> Void

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            chapterHeader

            if isExpanded {
                if !chapter.summary.isEmpty {
                    Text(chapter.summary)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                }

                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                    ForEach(chapter.stages) { stage in
                        let isUnlocked = progressStore.isStageUnlocked(stage)
                        let earnedStars = progressStore.progress(for: stage.id)?.earnedStars ?? 0
                        let isSelected = stage.id == selectedStageID

                        CampaignStageGridItemView(
                            stage: stage,
                            isUnlocked: isUnlocked,
                            isSelected: isSelected,
                            earnedStars: earnedStars,
                            theme: theme,
                            onTap: {
                                guard isUnlocked else { return }
                                debugLog("CampaignStageSelectionView: ステージカードをタップ -> \(stage.id.displayCode)")
                                onSelectStage(stage)
                            }
                        )
                    }
                }
                .transition(.opacity.combined(with: .scale))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.backgroundElevated.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(theme.textSecondary.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            debugLog("CampaignStageSelectionView.stageListView: Chapter \(chapter.id) のステージ数 = \(chapter.stages.count)件 (expanded=\(isExpanded))")
        }
    }

    private var chapterHeader: some View {
        let progress = campaignChapterProgressPresentation(for: chapter, progressStore: progressStore)
        return Button(action: onToggle) {
            HStack(spacing: 16) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundColor(theme.textSecondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.title)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)
                    Text(progress.stageCountText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                    CampaignChapterProgressView(summary: progress.summary, theme: theme)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("campaign_stage_chapter_toggle_\(chapter.id)")
        .accessibilityLabel(Text("Chapter \(chapter.id) \(chapter.title)"))
        .accessibilityHint(Text(isExpanded ? "折りたたむ" : "展開する"))
    }
}

struct CampaignChapterProgressView: View {
    let summary: ChapterProgressSummary
    let theme: AppTheme

    var body: some View {
        if summary.totalStageCount > 0 {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.accentPrimary)
                    Text("\(summary.earnedStars) / \(summary.totalStars)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                }
                .accessibilityLabel(Text("スター獲得状況 \(summary.earnedStars) 個 / \(summary.totalStars) 個"))

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.accentPrimary)
                    Text("\(summary.clearedStageCount) / \(summary.totalStageCount)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                }
                .accessibilityLabel(Text("クリア済みステージ \(summary.clearedStageCount) 件 / \(summary.totalStageCount) 件"))
            }
        }
    }
}

struct CampaignStageSelectionEmptyState: View {
    let theme: AppTheme
    let chapterCount: Int
    let stageCount: Int
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            Text("ステージ情報を読み込めませんでした")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(theme.textPrimary)
                .multilineTextAlignment(.center)

            Text("通信状況をご確認のうえ、画面を閉じて再度開き直してください。")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)

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
            debugLog("CampaignStageSelectionView.emptyStateView: 再試行導線付きエンプティビューを表示 (章数=\(chapterCount) ステージ総数=\(stageCount))")
        }
    }
}

struct CampaignStageSelectionBackButton: View {
    let onClose: () -> Void

    var body: some View {
        Button {
            debugLog("CampaignStageSelectionView.toolbar: 戻るボタン押下 -> NavigationStackポップ要求")
            onClose()
        } label: {
            Label("戻る", systemImage: "chevron.backward")
                .font(.system(size: 15, weight: .medium, design: .rounded))
        }
        .accessibilityIdentifier("campaign_stage_back_button")
    }
}

struct CampaignStageSelectionCloseButton: View {
    let onClose: () -> Void

    var body: some View {
        Button("閉じる") {
            debugLog("CampaignStageSelectionView.toolbar: 閉じるボタン押下 -> NavigationStackポップ要求")
            onClose()
        }
        .buttonStyle(.plain)
    }
}

/// キャンペーンのステージカードを 4 列グリッドで表示する専用ビュー
private struct CampaignStageGridItemView: View {
    let stage: CampaignStage
    let isUnlocked: Bool
    let isSelected: Bool
    let earnedStars: Int
    let theme: AppTheme
    let onTap: () -> Void

    var body: some View {
        Button {
            guard isUnlocked else { return }
            onTap()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(cardBackgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(borderColor, lineWidth: isSelected ? 3 : 1)
                    )

                VStack(spacing: 8) {
                    HStack {
                        Spacer(minLength: 0)
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(theme.accentPrimary)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                    }

                    Spacer(minLength: 0)

                    Text(stage.displayCode)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)

                    Spacer(minLength: 0)

                    stageStars

                    Spacer(minLength: 0)
                }
                .padding(12)

                if !isUnlocked {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                    VStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .foregroundColor(theme.textPrimary)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                        Text(stage.unlockDescription)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(theme.textPrimary.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .minimumScaleFactor(0.85)
                            .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 4)
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
        .accessibilityIdentifier("campaign_stage_button_\(stage.id.displayCode)")
        .accessibilityHint(accessibilityHintText)
        .accessibilityLabel(accessibilityLabelText)
    }

    private var stageStars: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < earnedStars ? "star.fill" : "star")
                    .foregroundColor(index < earnedStars ? theme.accentPrimary : theme.textSecondary.opacity(0.6))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
        }
        .accessibilityLabel("スター獲得数: \(earnedStars) / 3")
    }

    private var borderColor: Color {
        isSelected ? theme.accentPrimary : theme.textSecondary.opacity(0.35)
    }

    private var cardBackgroundColor: Color {
        isUnlocked ? theme.backgroundElevated : theme.backgroundElevated.opacity(0.6)
    }

    private var accessibilityLabelText: Text {
        if isUnlocked {
            Text("ステージ \(stage.displayCode)。解放条件: \(stage.unlockDescription) を達成済み")
        } else {
            Text("ステージ \(stage.displayCode)（ロック中）。解放条件: \(stage.unlockDescription)")
        }
    }

    private var accessibilityHintText: Text {
        if isUnlocked {
            Text("解放条件を満たしています。選択するとゲーム準備画面に戻り、選んだステージで開始準備が行われます。")
        } else {
            Text("解放条件: \(stage.unlockDescription)。条件を満たすと選択できるようになります。")
        }
    }
}
