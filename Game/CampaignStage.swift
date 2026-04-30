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

/// キャンペーンのスター評価に使う加点式スコア
public enum CampaignScoring {
    /// 保存済みベストスコアとの混在を避けるための方式バージョン
    public static let currentVersion = 2
    public static let targetCapturePoints = 100
    public static let moveCost = 10
    public static let focusCost = 15

    /// 目的地獲得を加点、移動とフォーカスを小さなコストとして計算する
    public static func score(capturedTargetCount: Int, moveCount: Int, focusCount: Int) -> Int {
        max(
            capturedTargetCount * targetCapturePoints
            - moveCount * moveCost
            - focusCount * focusCost,
            0
        )
    }
}

/// ステージ解放に必要な条件
public enum CampaignStageUnlockRequirement: Equatable {
    /// 常に解放済み
    case always
    /// 合計スター数が指定値以上
    case totalStars(minimum: Int)
    /// 指定章で獲得したスター数の合計が閾値以上
    case chapterTotalStars(chapter: Int, minimum: Int)
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
        /// ペナルティを指定合計値以下に抑えてクリア
        case finishWithPenaltyAtMost(maxPenaltyCount: Int)
        /// 既踏マスを再訪せずにクリア
        case avoidRevisitingTiles
        /// ペナルティ合計を指定値以下へ抑えつつ、指定手数以内でクリア
        case finishWithPenaltyAtMostAndWithinMoves(maxPenaltyCount: Int, maxMoves: Int)
        /// フォーカス使用回数を指定値以下に抑えてクリア
        case finishWithFocusAtMost(maxFocusCount: Int)
        /// フォーカス使用回数を指定値以下へ抑えつつ、指定手数以内でクリア
        case finishWithFocusAtMostAndWithinMoves(maxFocusCount: Int, maxMoves: Int)
    }

    /// スコア目標の比較方式
    public enum ScoreTargetComparison: Equatable {
        /// 指定値以下（≦）
        case lessThanOrEqual
        /// 指定値未満（＜）
        case lessThan


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
    /// 2 個目のスター獲得に必要なスコア上限
    public let twoStarScoreTarget: Int?
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
        twoStarScoreTarget: Int? = nil,
        scoreTarget: Int?,
        scoreTargetComparison: ScoreTargetComparison = .lessThanOrEqual,
        unlockRequirement: CampaignStageUnlockRequirement
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.regulation = regulation
        self.secondaryObjective = secondaryObjective
        self.twoStarScoreTarget = twoStarScoreTarget
        self.scoreTarget = scoreTarget
        self.scoreTargetComparison = scoreTargetComparison
        self.unlockRequirement = unlockRequirement
    }

}

/// クリア時の統計値をまとめた構造体
public struct CampaignStageClearMetrics {
    public let moveCount: Int
    public let penaltyCount: Int
    public let focusCount: Int
    public let elapsedSeconds: Int
    public let totalMoveCount: Int
    public let score: Int
    public let hasRevisitedTile: Bool
    public let capturedTargetCount: Int

    public var campaignScore: Int {
        CampaignScoring.score(
            capturedTargetCount: capturedTargetCount,
            moveCount: moveCount,
            focusCount: focusCount
        )
    }

    public init(
        moveCount: Int,
        penaltyCount: Int,
        focusCount: Int = 0,
        elapsedSeconds: Int,
        totalMoveCount: Int,
        score: Int,
        hasRevisitedTile: Bool,
        capturedTargetCount: Int = 0
    ) {
        self.moveCount = moveCount
        self.penaltyCount = penaltyCount
        self.focusCount = focusCount
        self.elapsedSeconds = elapsedSeconds
        self.totalMoveCount = totalMoveCount
        self.score = score
        self.hasRevisitedTile = hasRevisitedTile
        self.capturedTargetCount = capturedTargetCount
    }
}

/// ステージ評価結果
public struct CampaignStageEvaluation {
    public let stageID: CampaignStageID
    public let earnedStars: Int
    public let achievedTwoStarScoreGoal: Bool
    public let achievedThreeStarScoreGoal: Bool
    public let achievedSecondaryObjective: Bool
    public let achievedScoreGoal: Bool

    // Swift パッケージ外でも初期化できるよう明示的に public イニシャライザを用意する
    public init(
        stageID: CampaignStageID,
        earnedStars: Int,
        achievedSecondaryObjective: Bool,
        achievedScoreGoal: Bool,
        achievedTwoStarScoreGoal: Bool? = nil,
        achievedThreeStarScoreGoal: Bool? = nil
    ) {
        self.stageID = stageID
        self.earnedStars = earnedStars
        self.achievedTwoStarScoreGoal = achievedTwoStarScoreGoal ?? achievedSecondaryObjective
        self.achievedThreeStarScoreGoal = achievedThreeStarScoreGoal ?? achievedScoreGoal
        self.achievedSecondaryObjective = achievedSecondaryObjective
        self.achievedScoreGoal = achievedScoreGoal
    }
}
