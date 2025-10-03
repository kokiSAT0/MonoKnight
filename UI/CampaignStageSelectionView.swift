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
                // 空配列の場合に章数とステージ数を記録し、データロード失敗の規模を把握できるようにする
                emptyStateView
                    .onAppear {
                        // onAppear 内でログを記録し、ViewBuilder が Void を評価しないようにしておく
                        debugLog("CampaignStageSelectionView.body: 章数=\(campaignLibrary.chapters.count) ステージ総数=\(campaignLibrary.allStages.count) -> emptyStateView を表示")
                    }
            } else {
                // 章が存在する場合にも章数とステージ数を残し、表示中リストの状態を可視化する
                stageListView
                    .onAppear {
                        // onAppear 内にログを移し、ResultBuilder の副作用評価を避ける
                        debugLog("CampaignStageSelectionView.body: 章数=\(campaignLibrary.chapters.count) ステージ総数=\(campaignLibrary.allStages.count) -> stageListView を表示")
                    }
            }
        }
        .navigationTitle("キャンペーン")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                backButton
            }
            if showsCloseButton {
                ToolbarItem(placement: .cancellationAction) {
                    closeButton
                }
            }
        }
        // ステージ一覧の表示状態を追跡し、遷移の成否をログで確認できるようにする
        .onAppear {
            let unlockedCount = campaignLibrary.allStages.filter { progressStore.isStageUnlocked($0) }.count
            // 章ごとのステージ数を列挙し、定義抜けによる空表示を切り分けやすくする
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

    /// 星アイコンを生成する
    /// - Parameter earnedStars: 獲得済みの星の数
    /// - Returns: 星 3 つの並び
    private func starIcons(for earnedStars: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < earnedStars ? "star.fill" : "star")
                    .foregroundColor(index < earnedStars ? theme.accentPrimary : theme.textSecondary.opacity(0.6))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            }
        }
        .accessibilityLabel("スター獲得数: \(earnedStars) / 3")
    }

    /// 章とステージが正しく読み込めた場合の一覧表示
    /// - Returns: DisclosureGroup 風のスクロールビュー
    private var stageListView: some View {
        // List 描画前に章ごとのステージ数を記録し、UI 側の表示内容と定義の整合性を検証しやすくする
        let chapterDetails = campaignLibrary.chapters
            .map { chapter in "Chapter \(chapter.id) \(chapter.title): \(chapter.stages.count)件" }
            .joined(separator: ", ")
        // ResultBuilder の返却型と副作用の整合性を保つため、ScrollView を戻り値として明示する
        return ScrollView {
            LazyVStack(spacing: 20, pinnedViews: []) {
                ForEach(campaignLibrary.chapters) { chapter in
                    chapterContainer(for: chapter)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .background(theme.backgroundPrimary)
        .onAppear {
            // onAppear 時に章一覧のサマリーを出力し、ViewBuilder の評価と副作用を分離する
            debugLog("CampaignStageSelectionView.stageListView: 表示対象章一覧 = [\(chapterDetails)]")
            if expandedChapters.isEmpty {
                // 最新の解放済みステージを含む章を優先して展開することで、進捗確認をしやすくする
                let targetChapterID = latestUnlockedChapterID() ?? campaignLibrary.chapters.first?.id
                if let targetChapterID {
                    // Set へ単一章 ID を格納し、意図的に 1 章だけを展開した状態にする
                    expandedChapters = [targetChapterID]
                    debugLog("CampaignStageSelectionView.stageListView: 初期展開章を最新解放章 (Chapter \(targetChapterID)) に設定")
                } else {
                    // 章が全く定義されていないケースでもログを残し、データ定義の見直しへ繋げられるようにする
                    debugLog("CampaignStageSelectionView.stageListView: 解放済みステージが見つからず、展開状態を変更しませんでした")
                }
            }
        }
    }

    /// 最新の解放済みステージが存在する章 ID を算出し、初期展開する章の判断材料とする
    /// - Returns: 解放済みステージを含む章 ID（存在しない場合は nil）
    private func latestUnlockedChapterID() -> Int? {
        // 章定義を昇順のまま走査し、最後に true となった章 ID を記録する
        var latestChapterID: Int?
        for chapter in campaignLibrary.chapters {
            for stage in chapter.stages {
                // ステージが解放済みなら、該当する章 ID を随時更新しておく
                if progressStore.isStageUnlocked(stage) {
                    latestChapterID = chapter.id
                }
            }
        }
        // 解放済みステージが無い場合は nil が返り、呼び出し元でフォールバックが適用される
        return latestChapterID
    }

    /// 章単位の Disclosure コンテナを生成し、開閉状態とステージグリッドを制御する
    /// - Parameter chapter: レイアウト対象の章データ
    /// - Returns: 見出しと LazyVGrid を組み合わせたビュー
    private func chapterContainer(for chapter: CampaignChapter) -> some View {
        let isExpanded = expandedChapters.contains(chapter.id)
        // 読みやすさ向上のため見出しとコンテンツを VStack でまとめ、背景カードを適用する
        return VStack(alignment: .leading, spacing: 16) {
            Button {
                toggleChapterExpansion(for: chapter)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textSecondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Chapter \(chapter.id) \(chapter.title)")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(theme.textPrimary)
                        Text("ステージ \(chapter.stages.count) 件")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "minus.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.accentPrimary)
                        .padding(.trailing, 4)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("campaign_stage_chapter_toggle_\(chapter.id)")
            .accessibilityLabel(Text("Chapter \(chapter.id) \(chapter.title)"))
            .accessibilityHint(Text(isExpanded ? "折りたたむ" : "展開する"))

            if isExpanded {
                if !chapter.summary.isEmpty {
                    // 章の概要は開いたときのみ表示し、情報量過多を防ぐ
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
                            starContent: { count in AnyView(starIcons(for: count)) },
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
            // 各章の表示タイミングでステージ数を記録し、展開状態と合わせて診断できるようにする
            debugLog("CampaignStageSelectionView.stageListView: Chapter \(chapter.id) のステージ数 = \(chapter.stages.count)件 (expanded=\(isExpanded))")
        }
    }

    /// LazyVGrid の列構成を返し、正方形カードが 4 列で並ぶようにする
    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 4)
    }

    /// 章の開閉状態をトグルし、ログとセット管理を同期する
    /// - Parameter chapter: 操作対象の章データ
    private func toggleChapterExpansion(for chapter: CampaignChapter) {
        if expandedChapters.contains(chapter.id) {
            expandedChapters.remove(chapter.id)
            debugLog("CampaignStageSelectionView: Chapter \(chapter.id) を折りたたみ")
        } else {
            expandedChapters.insert(chapter.id)
            debugLog("CampaignStageSelectionView: Chapter \(chapter.id) を展開")
        }
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
            // データ欠落の発生タイミングと再試行導線の提示状況を把握するためログを出力
            debugLog("CampaignStageSelectionView.emptyStateView: 再試行導線付きエンプティビューを表示 (章数=\(campaignLibrary.chapters.count) ステージ総数=\(campaignLibrary.allStages.count))")
        }
    }

}

/// キャンペーンのステージカードを 4 列グリッドで表示する専用ビュー
/// - Note: コメントは全て日本語に統一し、デザイン意図を明示する
private struct CampaignStageGridItemView<StarContent: View>: View {
    /// 表示対象のステージ
    let stage: CampaignStage
    /// ステージが解放済みかどうか
    let isUnlocked: Bool
    /// 現在選択中のステージかどうか
    let isSelected: Bool
    /// 獲得済みスター数
    let earnedStars: Int
    /// 親ビューと揃えたテーマ情報
    let theme: AppTheme
    /// スター表示を親から差し込むためのクロージャ（ヘルパー再利用を目的とする）
    let starContent: (Int) -> StarContent
    /// タップ時に親へ通知するコールバック
    let onTap: () -> Void

    var body: some View {
        Button {
            // ロック時は遷移させず、誤操作によるログ汚染を防ぐ
            guard isUnlocked else { return }
            onTap()
        } label: {
            ZStack {
                // ベースとなる正方形カード。解放状態で彩度を、ロック時に彩度を落とす
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
                            // 選択済み状態はチェックアイコンで強調する
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(theme.accentPrimary)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                        }
                    }

                    Spacer(minLength: 0)

                    // ステージ番号は中央寄せで大きく表示し、カード一覧で識別しやすくする
                    Text(stage.displayCode)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(theme.textPrimary)

                    Spacer(minLength: 0)

                    // スターアイコンは親のヘルパーを利用し一貫した見た目を保つ
                    starContent(earnedStars)

                    Spacer(minLength: 0)
                }
                .padding(12)

                if !isUnlocked {
                    // ロック中は暗幕と鍵アイコンを重ね、タップ不可能であることを示す
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.black.opacity(0.45))
                    Image(systemName: "lock.fill")
                        .foregroundColor(theme.textPrimary)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                }
            }
            .aspectRatio(1, contentMode: .fit)
        }
        .buttonStyle(.plain)
        .disabled(!isUnlocked)
        // UI テストで個別カードを操作できるよう識別子を設定する
        .accessibilityIdentifier("campaign_stage_button_\(stage.id.displayCode)")
        // 折り畳みグリッド内でも従来同様の VoiceOver 案内を提供する
        .accessibilityHint(Text("選択するとゲーム準備画面に戻り、選んだステージで開始準備が行われます。"))
        .accessibilityLabel(Text("ステージ \(stage.displayCode)"))
    }

    /// 選択状態に応じた枠線色を返す
    private var borderColor: Color {
        isSelected ? theme.accentPrimary : theme.textSecondary.opacity(0.35)
    }

    /// ロック状態に応じて背景色を切り替える
    private var cardBackgroundColor: Color {
        isUnlocked ? theme.backgroundElevated : theme.backgroundElevated.opacity(0.6)
    }
}

// MARK: - ツールバー構成要素

private extension CampaignStageSelectionView {
    /// タイトル画面へ戻るための独自戻るボタン
    var backButton: some View {
        Button {
            // ユーザーが戻る操作を行ったタイミングをログに残し、意図しない遷移がないか追跡しやすくする
            debugLog("CampaignStageSelectionView.toolbar: 戻るボタン押下 -> NavigationStackポップ要求")
            onClose()
        } label: {
            Label("戻る", systemImage: "chevron.backward")
                .font(.system(size: 15, weight: .medium, design: .rounded))
        }
        .accessibilityIdentifier("campaign_stage_back_button")
    }

    /// モーダル表示時に使用する「閉じる」ボタン
    var closeButton: some View {
        Button("閉じる") {
            // モーダルの閉鎖契機を明示的に記録し、想定外の dismiss が起きた際の比較材料とする
            debugLog("CampaignStageSelectionView.toolbar: 閉じるボタン押下 -> NavigationStackポップ要求")
            onClose()
        }
        .buttonStyle(.plain)
    }
}

