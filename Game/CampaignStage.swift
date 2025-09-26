import Foundation

/// キャンペーンに登場するステージを一意に識別するための構造体
/// - Note: 章番号と章内インデックスを組み合わせて管理し、UI 表示と永続化の双方で扱いやすいようにしている
public struct CampaignStageID: Hashable, Codable {
    /// 章番号（1 始まり）
    public let chapter: Int
    /// 章内でのステージ順序（1 始まり）
    public let index: Int

    /// 公開イニシャライザ
    /// - Parameters:
    ///   - chapter: 章番号
    ///   - index: 章内インデックス
    public init(chapter: Int, index: Int) {
        self.chapter = chapter
        self.index = index
    }

    /// "1-1" のような表示用コードを生成
    public var displayCode: String {
        "\(chapter)-\(index)"
    }

    /// UserDefaults へ保存する際のキー
    public var storageKey: String {
        displayCode
    }

    /// 保存済みキー文字列から `CampaignStageID` を復元
    /// - Parameter storageKey: "章-ステージ" 形式の文字列
    public init?(storageKey: String) {
        let components = storageKey.split(separator: "-")
        guard components.count == 2,
              let chapter = Int(components[0]),
              let index = Int(components[1])
        else { return nil }
        self.chapter = chapter
        self.index = index
    }
}

/// ステージ解放に必要な条件
public enum CampaignStageUnlockRequirement: Equatable {
    /// 常に解放済み
    case always
    /// 合計スター数が指定値以上
    case totalStars(minimum: Int)
    /// 指定ステージをクリア済み
    case stageClear(CampaignStageID)
}

/// キャンペーンステージの実体定義
public struct CampaignStage: Identifiable, Equatable {
    /// ステージ固有の追加条件
    public enum SecondaryObjective: Equatable {
        /// 指定手数以内でクリア
        case finishWithinMoves(maxMoves: Int)
        /// 指定時間以内でクリア
        case finishWithinSeconds(maxSeconds: Int)
        /// ペナルティ加算なしでクリア
        case finishWithoutPenalty
        /// ペナルティを指定回数以下に抑えてクリア
        case finishWithPenaltyAtMost(maxPenaltyCount: Int)
        /// 既踏マスを再訪せずにクリア
        case avoidRevisitingTiles

        /// 条件をプレイ結果に照らし合わせて判定
        /// - Parameter metrics: クリア時の統計値
        /// - Returns: 条件を満たしていれば true
        func isSatisfied(by metrics: CampaignStageClearMetrics) -> Bool {
            switch self {
            case .finishWithinMoves(let maxMoves):
                return metrics.moveCount <= maxMoves
            case .finishWithinSeconds(let maxSeconds):
                return metrics.elapsedSeconds <= maxSeconds
            case .finishWithoutPenalty:
                return metrics.penaltyCount == 0
            case .finishWithPenaltyAtMost(let maxPenaltyCount):
                return metrics.penaltyCount <= maxPenaltyCount
            case .avoidRevisitingTiles:
                return !metrics.hasRevisitedTile
            }
        }

        /// UI 表示向け説明文
        var description: String {
            switch self {
            case .finishWithinMoves(let maxMoves):
                return "移動 \(maxMoves) 手以内でクリア"
            case .finishWithinSeconds(let maxSeconds):
                return "\(maxSeconds) 秒以内でクリア"
            case .finishWithoutPenalty:
                return "ペナルティを受けずにクリア"
            case .finishWithPenaltyAtMost(let maxPenaltyCount):
                return "ペナルティを合計 \(maxPenaltyCount) 回以下に抑えてクリア"
            case .avoidRevisitingTiles:
                return "同じマスを 2 回踏まずにクリア"
            }
        }
    }

    /// スコア目標の比較方式
    public enum ScoreTargetComparison: Equatable {
        /// 指定値以下（≦）
        case lessThanOrEqual
        /// 指定値未満（＜）
        case lessThan

        /// 条件を満たしているか判定する
        /// - Parameters:
        ///   - score: 実際のスコア
        ///   - target: 目標値
        /// - Returns: 達成していれば true
        func isSatisfied(score: Int, target: Int) -> Bool {
            switch self {
            case .lessThanOrEqual:
                return score <= target
            case .lessThan:
                return score < target
            }
        }

        /// 表示用の比較記号を返す
        /// - Returns: "以下" などユーザーへ提示する文言
        var descriptionSuffix: String {
            switch self {
            case .lessThanOrEqual:
                return "以下"
            case .lessThan:
                return "未満"
            }
        }
    }

    public let id: CampaignStageID
    /// タイトル表示用の名称
    public let title: String
    /// 短い説明文
    public let summary: String
    /// 実際に利用するレギュレーション
    public let regulation: GameMode.Regulation
    /// 2 個目のスター獲得条件
    public let secondaryObjective: SecondaryObjective?
    /// 3 個目のスター獲得に必要なスコア上限
    public let scoreTarget: Int?
    /// スコア目標の比較方式
    public let scoreTargetComparison: ScoreTargetComparison
    /// ステージ解放条件
    public let unlockRequirement: CampaignStageUnlockRequirement

    /// 初期化
    public init(
        id: CampaignStageID,
        title: String,
        summary: String,
        regulation: GameMode.Regulation,
        secondaryObjective: SecondaryObjective?,
        scoreTarget: Int?,
        scoreTargetComparison: ScoreTargetComparison = .lessThanOrEqual,
        unlockRequirement: CampaignStageUnlockRequirement
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.regulation = regulation
        self.secondaryObjective = secondaryObjective
        self.scoreTarget = scoreTarget
        self.scoreTargetComparison = scoreTargetComparison
        self.unlockRequirement = unlockRequirement
    }

    /// UI で表示する際のコード表記
    public var displayCode: String { id.displayCode }

    /// 二つ目のスター条件説明
    public var secondaryObjectiveDescription: String? {
        secondaryObjective?.description
    }

    /// 三つ目のスター条件説明
    public var scoreTargetDescription: String? {
        guard let scoreTarget else { return nil }
        let suffix = scoreTargetComparison.descriptionSuffix
        return "スコア \(scoreTarget) pt \(suffix)でクリア"
    }

    /// ステージ解放条件の説明
    public var unlockDescription: String {
        switch unlockRequirement {
        case .always:
            return "最初から解放済み"
        case .totalStars(let minimum) where minimum <= 0:
            return "最初から解放済み"
        case .totalStars(let minimum):
            return "スターを合計 \(minimum) 個集める"
        case .stageClear(let requiredID):
            return "ステージ \(requiredID.displayCode) をクリア"
        }
    }

    /// クリア時の成績から獲得スター数を判定
    /// - Parameter metrics: クリア時の統計値
    /// - Returns: 達成状況の評価結果
    public func evaluateClear(with metrics: CampaignStageClearMetrics) -> CampaignStageEvaluation {
        let objectiveAchieved = secondaryObjective?.isSatisfied(by: metrics) ?? false
        let scoreAchieved: Bool
        if let scoreTarget {
            scoreAchieved = scoreTargetComparison.isSatisfied(score: metrics.score, target: scoreTarget)
        } else {
            scoreAchieved = false
        }

        var stars = 1 // クリアそのものが 1 個目のスター
        if objectiveAchieved { stars += 1 }
        if scoreAchieved { stars += 1 }

        return CampaignStageEvaluation(
            stageID: id,
            earnedStars: stars,
            achievedSecondaryObjective: objectiveAchieved,
            achievedScoreGoal: scoreAchieved
        )
    }

    /// ゲームプレイ用の `GameMode` を生成
    /// - Returns: ステージに対応するモード
    public func makeGameMode() -> GameMode {
        GameMode(
            identifier: .campaignStage,
            displayName: "\(displayCode) \(title)",
            regulation: regulation,
            leaderboardEligible: false,
            campaignMetadata: .init(stageID: id)
        )
    }
}

/// クリア時の統計値をまとめた構造体
public struct CampaignStageClearMetrics {
    public let moveCount: Int
    public let penaltyCount: Int
    public let elapsedSeconds: Int
    public let totalMoveCount: Int
    public let score: Int
    public let hasRevisitedTile: Bool

    public init(
        moveCount: Int,
        penaltyCount: Int,
        elapsedSeconds: Int,
        totalMoveCount: Int,
        score: Int,
        hasRevisitedTile: Bool
    ) {
        self.moveCount = moveCount
        self.penaltyCount = penaltyCount
        self.elapsedSeconds = elapsedSeconds
        self.totalMoveCount = totalMoveCount
        self.score = score
        self.hasRevisitedTile = hasRevisitedTile
    }
}

/// ステージ評価結果
public struct CampaignStageEvaluation {
    public let stageID: CampaignStageID
    public let earnedStars: Int
    public let achievedSecondaryObjective: Bool
    public let achievedScoreGoal: Bool

    // Swift パッケージ外でも初期化できるよう明示的に public イニシャライザを用意する
    public init(
        stageID: CampaignStageID,
        earnedStars: Int,
        achievedSecondaryObjective: Bool,
        achievedScoreGoal: Bool
    ) {
        self.stageID = stageID
        self.earnedStars = earnedStars
        self.achievedSecondaryObjective = achievedSecondaryObjective
        self.achievedScoreGoal = achievedScoreGoal
    }
}

/// 章単位でステージを束ねる定義
public struct CampaignChapter: Identifiable, Equatable {
    public let id: Int
    public let title: String
    public let summary: String
    public let stages: [CampaignStage]

    public init(id: Int, title: String, summary: String, stages: [CampaignStage]) {
        self.id = id
        self.title = title
        self.summary = summary
        self.stages = stages
    }
}

/// ステージ定義一式を提供するライブラリ
public struct CampaignLibrary {
    /// アプリ全体で共有するデフォルト定義
    public static let shared = CampaignLibrary()

    /// 章一覧
    public let chapters: [CampaignChapter]

    /// プライベートイニシャライザで定義を構築
    public init() {
        self.chapters = CampaignLibrary.buildChapters()
    }

    /// 指定 ID に一致するステージを検索
    /// - Parameter id: 探索したいステージ ID
    /// - Returns: 見つかった場合は該当ステージ
    public func stage(with id: CampaignStageID) -> CampaignStage? {
        for chapter in chapters {
            if let stage = chapter.stages.first(where: { $0.id == id }) {
                return stage
            }
        }
        return nil
    }

    /// 全ステージの一次元配列
    public var allStages: [CampaignStage] {
        chapters.flatMap { $0.stages }
    }

    /// 定義の実装本体
    private static func buildChapters() -> [CampaignChapter] {
        // MARK: - 1 章のステージ群
        // MARK: 章 1 のステージレギュレーション共通設定
        // 章内で複数のステージが同一ルールを参照する場合に備え、先に共通変数へ切り出しておく。
        let classicalChallengeRegulation = GameMode.classicalChallenge.regulationSnapshot

        let stage11 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 1),
            title: "序盤訓練",
            summary: "4×4 の小さな盤面で基本操作を確認しましょう。",
            regulation: GameMode.Regulation(
                boardSize: 4,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standard,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 4)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 3,
                    manualRedrawPenaltyCost: 1,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 0
                )
            ),
            // MARK: 2 個目のスター条件: ペナルティ発生を 5 回以下に抑える
            // - Note: 新米プレイヤーが多少の詰まりを経験しても達成可能な難易度に調整する。
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 5),
            scoreTarget: 350,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .totalStars(minimum: 0)
        )

        // 1-2 ステージはクラシカルチャレンジと同等のレギュレーションを採用し、大盤面での立ち回りを学ぶ想定。
        // リワード条件はユーザー指定に従い、2 個目のスターを 120 秒以内クリア、3 個目をスコア 900 未満達成としている。
        let stage12 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 2),
            title: "クラシカル演習",
            summary: "クラシカルチャレンジと同じ 8×8 盤で時間管理を意識しましょう。",
            regulation: classicalChallengeRegulation,
            secondaryObjective: .finishWithinSeconds(maxSeconds: 120),
            scoreTarget: 900,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(CampaignStageID(chapter: 1, index: 1))
        )

        let chapter1 = CampaignChapter(
            id: 1,
            title: "基礎訓練",
            summary: "カード移動の定石を学ぶ章。",
            stages: [stage11, stage12]
        )

        return [chapter1]
    }
}
