import SwiftUI
import Game

/// 章の進捗情報をまとめた内部利用向けモデル
/// - Note: 表示専用のため View からのみ参照する
struct ChapterProgressSummary {
    /// 獲得済みスター数の合計
    let earnedStars: Int
    /// 獲得可能なスターの合計
    let totalStars: Int
    /// クリア済みステージ数
    let clearedStageCount: Int
    /// 章内に存在するステージ総数
    let totalStageCount: Int
}

/// 章見出しで表示する進捗情報
struct CampaignChapterProgressPresentation {
    let title: String
    let stageCountText: String
    let summary: ChapterProgressSummary
}

/// 章単位の進捗サマリーを算出し、Disclosure が閉じている状態でも進捗を把握できるようにする
@MainActor
func campaignChapterProgressSummary(
    for chapter: CampaignChapter,
    progressStore: CampaignProgressStore
) -> ChapterProgressSummary {
    var earnedStars = 0
    var clearedStageCount = 0
    for stage in chapter.stages {
        let progress = progressStore.progress(for: stage.id)
        let stars = progress?.earnedStars ?? 0
        earnedStars += stars
        if stars > 0 {
            clearedStageCount += 1
        }
    }

    return ChapterProgressSummary(
        earnedStars: earnedStars,
        totalStars: chapter.stages.count * 3,
        clearedStageCount: clearedStageCount,
        totalStageCount: chapter.stages.count
    )
}

/// 章見出しで使う表示用メタ情報を生成する
@MainActor
func campaignChapterProgressPresentation(
    for chapter: CampaignChapter,
    progressStore: CampaignProgressStore
) -> CampaignChapterProgressPresentation {
    CampaignChapterProgressPresentation(
        title: "Chapter \(chapter.id) \(chapter.title)",
        stageCountText: "ステージ \(chapter.stages.count) 件",
        summary: campaignChapterProgressSummary(for: chapter, progressStore: progressStore)
    )
}

/// ステージ一覧のログ向け詳細テキストを生成する
func campaignChapterDetailsDescription(library: CampaignLibrary) -> String {
    library.chapters
        .map { chapter in "Chapter \(chapter.id) \(chapter.title): \(chapter.stages.count)件" }
        .joined(separator: ", ")
}

/// 未クリアかつ解放済みステージを含む章 ID を抽出し、画面初期表示時の展開対象を決定する
/// - Parameters:
///   - library: 章とステージ定義を含むキャンペーンライブラリ
///   - progressStore: ステージ解放状況と獲得スター数を保持する進捗ストア
/// - Returns: 展開すべき章 ID の集合。該当章が無い場合は最新の解放章、さらに無い場合は先頭章を返す。
@MainActor
internal func chapterIDsWithUnlockedUnclearedStages(
    library: CampaignLibrary,
    progressStore: CampaignProgressStore
) -> Set<Int> {
    var unlockedUnclearedChapterIDs = Set<Int>()
    for chapter in library.chapters {
        var hasUnlockedUnclearedStage = false
        for stage in chapter.stages {
            guard progressStore.isStageUnlocked(stage) else { continue }
            let earnedStars = progressStore.progress(for: stage.id)?.earnedStars ?? 0
            if earnedStars == 0 {
                hasUnlockedUnclearedStage = true
                break
            }
        }
        if hasUnlockedUnclearedStage {
            unlockedUnclearedChapterIDs.insert(chapter.id)
        }
    }

    if !unlockedUnclearedChapterIDs.isEmpty {
        return unlockedUnclearedChapterIDs
    }

    var latestUnlockedChapterID: Int?
    for chapter in library.chapters {
        for stage in chapter.stages where progressStore.isStageUnlocked(stage) {
            latestUnlockedChapterID = chapter.id
        }
    }

    if let latestUnlockedChapterID {
        return [latestUnlockedChapterID]
    }

    if let firstChapterID = library.chapters.first?.id {
        return [firstChapterID]
    }

    return []
}
