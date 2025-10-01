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
    /// ホームボタンを表示するかどうか（デフォルトで表示）
    let showsHomeButton: Bool
    /// ステージ決定時のハンドラ
    let onSelectStage: (CampaignStage) -> Void
    /// ホームボタン押下時のハンドラ
    private let onTapHome: () -> Void

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
    ///   - showsHomeButton: 画面上部にホームへ戻るボタンを表示するかどうか
    ///   - onTapHome: ホームボタン押下時に実行する処理（未指定時は `onClose` と同一挙動）
    init(
        campaignLibrary: CampaignLibrary,
        progressStore: CampaignProgressStore,
        selectedStageID: CampaignStageID?,
        onClose: @escaping () -> Void,
        onSelectStage: @escaping (CampaignStage) -> Void,
        showsCloseButton: Bool = true,
        showsHomeButton: Bool = true,
        onTapHome: (() -> Void)? = nil
    ) {
        // @ObservedObject プロパティはラッパー経由で代入する必要があるため、明示的に初期化する
        self.campaignLibrary = campaignLibrary
        _progressStore = ObservedObject(wrappedValue: progressStore)
        self.selectedStageID = selectedStageID
        self.onClose = onClose
        self.onSelectStage = onSelectStage
        self.showsCloseButton = showsCloseButton
        self.showsHomeButton = showsHomeButton
        self.onTapHome = onTapHome ?? onClose
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
        .safeAreaInset(edge: .top) {
            if showsCloseButton || showsHomeButton {
                HStack(spacing: 12) {
                    if showsHomeButton {
                        Button {
                            // ホームに戻る際の挙動を記録し、ナビゲーションの想定外遷移を追跡しやすくする
                            debugLog("CampaignStageSelectionView.toolbar: ホームボタン押下 -> Title画面へ戻る要求")
                            onTapHome()
                        } label: {
                            Label("ホーム", systemImage: "house.fill")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.textPrimary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(theme.backgroundElevated.opacity(0.9))
                                )
                        }
                        .accessibilityLabel("ホーム画面に戻る")
                        .buttonStyle(.plain)
                    }

                    Spacer()

                    if showsCloseButton {
                        Button("閉じる") {
                            // ナビゲーションスタックをポップする契機を記録し、手動クローズのトレースを取りやすくする
                            debugLog("CampaignStageSelectionView.toolbar: 閉じるボタン押下 -> NavigationStackポップ要求")
                            onClose()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.thinMaterial)
            } else {
                // safeAreaInset の ResultBuilder が Void を返さないよう、非表示時は EmptyView を明示する
                EmptyView()
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
        // UI テストやアクセシビリティから特定ステージを一意に参照できるようにする
        .accessibilityIdentifier("campaign_stage_button_\(stage.id.displayCode)")
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
    private var stageListView: some View {
        // List 描画前に章ごとのステージ数を記録し、UI 側の表示内容と定義の整合性を検証しやすくする
        let chapterDetails = campaignLibrary.chapters
            .map { chapter in "Chapter \(chapter.id) \(chapter.title): \(chapter.stages.count)件" }
            .joined(separator: ", ")
        // ResultBuilder の返却型と副作用の整合性を保つため、List を戻り値として明示する
        return List {
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
                // onAppear でログを出力し、ResultBuilder の制約を満たしつつ診断情報を残す
                .onAppear {
                    // 各章ごとのステージ件数を記録し、データの欠損をタイムラインで追跡しやすくする
                    debugLog("CampaignStageSelectionView.stageListView: Chapter \(chapter.id) のステージ数 = \(chapter.stages.count)件")
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            // onAppear 時に章一覧のサマリーを出力し、ViewBuilder の評価と副作用を分離する
            debugLog("CampaignStageSelectionView.stageListView: 表示対象章一覧 = [\(chapterDetails)]")
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

