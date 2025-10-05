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
        /// ペナルティ加算なしでクリア
        case finishWithoutPenalty
        /// ペナルティを指定合計値以下に抑えてクリア
        case finishWithPenaltyAtMost(maxPenaltyCount: Int)
        /// 既踏マスを再訪せずにクリア
        case avoidRevisitingTiles
        /// ペナルティなしかつ指定手数以内でクリア
        case finishWithoutPenaltyAndWithinMoves(maxMoves: Int)

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
            case .finishWithoutPenaltyAndWithinMoves(let maxMoves):
                return metrics.penaltyCount == 0 && metrics.moveCount <= maxMoves
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
                // VoiceOver などでも「回」や「手」といった単位を付けない統一表現とする
                return "ペナルティ合計 \(maxPenaltyCount) 以下でクリア"
            case .avoidRevisitingTiles:
                return "同じマスを 2 回踏まずにクリア"
            case .finishWithoutPenaltyAndWithinMoves(let maxMoves):
                return "ペナルティなしで \(maxMoves) 手以内にクリア"
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
        case .chapterTotalStars(_, let minimum) where minimum <= 0:
            // 閾値が 0 以下の場合は常時解放と等価であるため、利用者へもその旨を伝える
            return "最初から解放済み"
        case .chapterTotalStars(let chapter, let minimum):
            return "第\(chapter)章でスターを合計 \(minimum) 個集める"
        case .stageClear(let requiredID):
            // ステージ番号を簡潔に伝えるため、重複した「ステージ」表現は省いている
            return "\(requiredID.displayCode) をクリア"
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
        // 1-1 は 3×3 盤かつ王将型カードのみで構成された超短距離訓練ステージ。
        // ペナルティは +2 系で揃え、序盤のリトライに優しい難度へ調整する。
        let stage11 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 1),
            title: "王将訓練",
            summary: "3×3 の盤で王将カードだけを使い、基本の詰めを体験しましょう。",
            regulation: GameMode.Regulation(
                boardSize: 3,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingOnly,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 3)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 2,
                    manualRedrawPenaltyCost: 2,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 1
                )
            ),
            // MARK: 2 個目のスター条件: 60 秒以内クリアで序盤からテンポを意識させる
            secondaryObjective: .finishWithinSeconds(maxSeconds: 60),
            scoreTarget: 300,
            scoreTargetComparison: .lessThan,
            // MARK: スタート地点となるため常時解放として整理する
            unlockRequirement: .always
        )

        // 1-2 はキングと桂馬の最小構成で、ペナルティ合計 5 以下を目指す導入ステージ。
        let stage12 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 2),
            title: "ナイト初見",
            summary: "キングと桂馬だけの 3×3 で、跳躍移動の感覚を掴みましょう。",
            regulation: GameMode.Regulation(
                boardSize: 3,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingPlusKnightOnly,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 3)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 2,
                    manualRedrawPenaltyCost: 2,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 0
                )
            ),
            // MARK: 2 個目のスター条件: ペナルティ合計 3 以下で締め、リトライ負荷を抑える
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 3),
            scoreTarget: 300,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage11.id)
        )

        // 1-3 は 4×4 盤への移行。キング＆桂馬基礎デッキで持ち時間 60 秒以内を狙う。
        let stage13 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 3),
            title: "4×4基礎",
            summary: "4×4 盤でキングと桂馬の動きを整理し、視野を一段広げましょう。",
            regulation: GameMode.Regulation(
                boardSize: 4,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingAndKnightBasic,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 4)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 3,
                    manualRedrawPenaltyCost: 1,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 0
                )
            ),
            // MARK: 2 個目のスター条件: 60 秒以内に踏破してテンポ良く盤面を巡回する
            secondaryObjective: .finishWithinSeconds(maxSeconds: 60),
            scoreTarget: 400,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage12.id)
        )

        // 1-4 は同じデッキで任意スポーンを導入し、ルート計画力を育てる。
        let stage14 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 4),
            title: "4×4応用",
            summary: "好きな開始マスを選び、4×4 で最適な踏破順を描きましょう。",
            regulation: GameMode.Regulation(
                boardSize: 4,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingAndKnightBasic,
                spawnRule: .chooseAnyAfterPreview,
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 3,
                    manualRedrawPenaltyCost: 1,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 0
                )
            ),
            // MARK: 2 個目のスター条件: ペナルティ合計 5 以下へ抑え、冷静な判断を促す
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 5),
            scoreTarget: 400,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage13.id)
        )

        // 1-5 はスタンダード軽量デッキで持久戦。手数 30 以内を目指す。
        let stage15 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 5),
            title: "4×4持久",
            summary: "長距離カードを抑えた 4×4 で、丁寧にルートを構築しましょう。",
            regulation: GameMode.Regulation(
                boardSize: 4,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 4)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 3,
                    manualRedrawPenaltyCost: 2,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 0
                )
            ),
            // MARK: 2 個目のスター条件: 手数 30 以内を要求し、正確な踏破計画を促す
            secondaryObjective: .finishWithinMoves(maxMoves: 30),
            scoreTarget: 400,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage14.id)
        )

        // 1-6 は再び任意スポーンを採用し、ペナルティ合計 3 以下を狙う実戦訓練。
        let stage16 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 6),
            title: "4×4戦略",
            summary: "開始位置を自由に選び、ペナルティ合計 3 以下で踏破する戦略を組みましょう。",
            regulation: GameMode.Regulation(
                boardSize: 4,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingAndKnightBasic,
                spawnRule: .chooseAnyAfterPreview,
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 3,
                    manualRedrawPenaltyCost: 2,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 0
                )
            ),
            // MARK: 2 個目のスター条件: ペナルティ合計 3 以下で終える集中力を養う
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 3),
            scoreTarget: 400,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage15.id)
        )

        // 1-7 は 5×5 盤を初めて扱う導入ステージ。スタンダード軽量構成で手数 40 以内を狙う。
        let stage17 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 7),
            title: "5×5導入",
            summary: "5×5 盤に挑み、長丁場でも安定して踏破する力を養いましょう。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 3,
                    manualRedrawPenaltyCost: 2,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 0
                )
            ),
            // MARK: 2 個目のスター条件: 40 手以内にまとめ、5×5 の巡回感覚を掴んでもらう
            secondaryObjective: .finishWithinMoves(maxMoves: 40),
            scoreTarget: 460,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage16.id)
        )

        // 1-8 は 5×5 での総合演習。任意スポーンを活かし、35 手以内を狙う。
        let stage18 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 8),
            title: "総合演習",
            summary: "任意の開始位置から 5×5 全域を巡り、総仕上げとして踏破しましょう。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: .chooseAnyAfterPreview,
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: 3,
                    manualRedrawPenaltyCost: 2,
                    manualDiscardPenaltyCost: 1,
                    revisitPenaltyCost: 0
                )
            ),
            // MARK: 2 個目のスター条件: 35 手以内に踏破し、戦略・リスク管理の両立を狙う
            secondaryObjective: .finishWithinMoves(maxMoves: 35),
            scoreTarget: 440,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage17.id)
        )

        let chapter1 = CampaignChapter(
            id: 1,
            title: "基礎訓練",
            summary: "小盤面から 5×5 まで段階的に学ぶ章。",
            stages: [stage11, stage12, stage13, stage14, stage15, stage16, stage17, stage18]
        )

        // MARK: - 2 章のステージ群
        // (1,2) と (3,4) の指定は 1 始まりの座標と解釈し、内部表現の 0 始まりへ変換する。
        // MARK: - 2 章のステージ群
        // 多重踏破マスの回数管理を段階的に学ぶ章。すべて `kingAndKnightBasic` デッキで統一する。
        let chapter2Penalties = GameMode.PenaltySettings(
            deadlockPenaltyCost: 3,
            manualRedrawPenaltyCost: 1,
            manualDiscardPenaltyCost: 1,
            revisitPenaltyCost: 0
        )

        // 2-1: 4×4 盤で二度踏みマスの基礎を学ぶ導入。中央固定スポーンで落ち着いて操作する。
        let stage21DoubleVisit: [GridPoint: Int] = [
            GridPoint(x: 0, y: 1): 2,
            GridPoint(x: 2, y: 3): 2
        ]
        let stage21 = CampaignStage(
            id: CampaignStageID(chapter: 2, index: 1),
            title: "重踏チュートリアル",
            summary: "左列と右上を 2 回踏む練習です。ペナルティ合計 5 以下でリズムを掴みましょう。",
            regulation: GameMode.Regulation(
                boardSize: 4,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingAndKnightBasic,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 4)),
                penalties: chapter2Penalties,
                additionalVisitRequirements: stage21DoubleVisit
            ),
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 5),
            scoreTarget: 450,
            scoreTargetComparison: .lessThanOrEqual,
            // MARK: 第 2 章開始条件は第 1 章で十分なスターを獲得しているかを基準にする
            unlockRequirement: .chapterTotalStars(chapter: 1, minimum: 16)
        )

        // 2-2: 5×5 盤で対角二度踏みを巡回し、任意スポーンでも 45 手以内へ収める判断力を育てる。
        let stage22DoubleVisit: [GridPoint: Int] = [
            GridPoint(x: 1, y: 1): 2,
            GridPoint(x: 3, y: 3): 2
        ]
        let stage22 = CampaignStage(
            id: CampaignStageID(chapter: 2, index: 2),
            title: "基礎演習",
            summary: "広い 5×5 で二度踏みマスを巡り、45 手以内のルート構築を練習します。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingAndKnightBasic,
                spawnRule: .chooseAnyAfterPreview,
                penalties: chapter2Penalties,
                additionalVisitRequirements: stage22DoubleVisit
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 45),
            scoreTarget: 450,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage21.id)
        )

        // 2-3: 中央三重踏みのテンポを身体で覚えるステージ。40 手以内が目標。
        let stage23TripleVisit: [GridPoint: Int] = [
            GridPoint(x: 2, y: 2): 3
        ]
        let stage23 = CampaignStage(
            id: CampaignStageID(chapter: 2, index: 3),
            title: "三重踏み入門",
            summary: "中央マスを 3 回踏む課題です。ペナルティを抑えつつ 40 手以内を目指しましょう。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingAndKnightBasic,
                spawnRule: .chooseAnyAfterPreview,
                penalties: chapter2Penalties,
                additionalVisitRequirements: stage23TripleVisit
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 40),
            scoreTarget: 450,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage22.id)
        )

        // 2-4: 三重踏みマスを左右へ分散し、ペナルティ合計 3 以下でバランスよく踏破する。
        let stage24TripleVisit: [GridPoint: Int] = [
            GridPoint(x: 1, y: 1): 3,
            GridPoint(x: 3, y: 3): 3
        ]
        let stage24 = CampaignStage(
            id: CampaignStageID(chapter: 2, index: 4),
            title: "複数三重踏み",
            summary: "左右対称の三重踏みマス 2 箇所を巡り、ペナルティ合計 3 以下でまとめる演習です。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingAndKnightBasic,
                spawnRule: .chooseAnyAfterPreview,
                penalties: chapter2Penalties,
                additionalVisitRequirements: stage24TripleVisit
            ),
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 3),
            scoreTarget: 580,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage23.id)
        )

        // 2-5: 中央四重踏みを 40 手以内で攻略し、手順管理の精度を高める。
        let stage25QuadVisit: [GridPoint: Int] = [
            GridPoint(x: 2, y: 2): 4
        ]
        let stage25 = CampaignStage(
            id: CampaignStageID(chapter: 2, index: 5),
            title: "中央集中",
            summary: "中心マスを 4 回踏む必要があるため、40 手以内で効率良く往復しましょう。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingAndKnightBasic,
                spawnRule: .chooseAnyAfterPreview,
                penalties: chapter2Penalties,
                additionalVisitRequirements: stage25QuadVisit
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 40),
            scoreTarget: 570,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage24.id)
        )

        // 2-6: 左右対称の四重踏みを 130 秒以内で処理し、時間管理を意識させる。
        let stage26QuadVisit: [GridPoint: Int] = [
            GridPoint(x: 1, y: 1): 4,
            GridPoint(x: 3, y: 3): 4
        ]
        let stage26 = CampaignStage(
            id: CampaignStageID(chapter: 2, index: 6),
            title: "四重踏み分散",
            summary: "左右に配置した四重踏みマスを巡回し、130 秒以内でテンポ良く踏破する課題です。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingAndKnightBasic,
                spawnRule: .chooseAnyAfterPreview,
                penalties: chapter2Penalties,
                additionalVisitRequirements: stage26QuadVisit
            ),
            secondaryObjective: .finishWithinSeconds(maxSeconds: 130),
            scoreTarget: 560,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage25.id)
        )

        // 2-7: 2・3・4 回踏みを混在させ、38 手以内に収める応用課題。
        let stage27MixedVisit: [GridPoint: Int] = [
            GridPoint(x: 1, y: 1): 2,
            GridPoint(x: 2, y: 2): 3,
            GridPoint(x: 3, y: 3): 4
        ]
        let stage27 = CampaignStage(
            id: CampaignStageID(chapter: 2, index: 7),
            title: "複合課題",
            summary: "踏破回数の異なるマスを組み合わせ、38 手以内で全域を巡る応用ステージです。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingAndKnightBasic,
                spawnRule: .chooseAnyAfterPreview,
                penalties: chapter2Penalties,
                additionalVisitRequirements: stage27MixedVisit
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 38),
            scoreTarget: 550,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage26.id)
        )

        // 2-8: 盤面中央寄りの三重踏みをすべて達成する総合演習。任意スポーンでも 40 手以内を目指す。
        let stage28QuadCorners: [GridPoint: Int] = [
            GridPoint(x: 1, y: 1): 3,
            GridPoint(x: 3, y: 1): 3,
            GridPoint(x: 1, y: 3): 3,
            GridPoint(x: 3, y: 3): 3
        ]
        let stage28 = CampaignStage(
            id: CampaignStageID(chapter: 2, index: 8),
            title: "総合演習",
            summary: "盤面中央寄りの三重踏みを順序良く処理し、40 手以内で締める総仕上げです。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingAndKnightBasic,
                spawnRule: .chooseAnyAfterPreview,
                penalties: chapter2Penalties,
                additionalVisitRequirements: stage28QuadCorners
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 40),
            scoreTarget: 540,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage27.id)
        )

        let chapter2 = CampaignChapter(
            id: 2,
            title: "応用特訓（重踏）",
            summary: "多重踏破マスの扱いを習得する章。",
            stages: [stage21, stage22, stage23, stage24, stage25, stage26, stage27, stage28]
        )

        // MARK: - 3 章のステージ群
        // 選択カードを段階導入し、終盤は複数踏破ギミックと組み合わせる。
        let standardPenalties = GameMode.PenaltySettings(
            deadlockPenaltyCost: 5,
            manualRedrawPenaltyCost: 5,
            manualDiscardPenaltyCost: 1,
            revisitPenaltyCost: 0
        )
        let noPenaltyPenalties = GameMode.PenaltySettings(
            deadlockPenaltyCost: 0,
            manualRedrawPenaltyCost: 0,
            manualDiscardPenaltyCost: 1,
            revisitPenaltyCost: 0
        )

        // 3-1: 4×4 盤で縦横選択カードを体験。ノーペナルティで丁寧な操作を促す。
        let stage31 = CampaignStage(
            id: CampaignStageID(chapter: 3, index: 1),
            title: "縦横選択チュートリアル",
            summary: "4×4 盤で上下左右を選べるキングカードを試し、基本操作を確認しましょう。",
            regulation: GameMode.Regulation(
                boardSize: 4,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithOrthogonalChoices,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 4)),
                penalties: noPenaltyPenalties
            ),
            secondaryObjective: .finishWithoutPenalty,
            scoreTarget: 600,
            scoreTargetComparison: .lessThanOrEqual,
            // MARK: 第 3 章も前章のスター総数を指標とし、継続的なチャレンジを促す
            unlockRequirement: .chapterTotalStars(chapter: 2, minimum: 16)
        )

        // 3-2: 5×5 盤へ拡張し、縦横カードで 40 手以内の踏破を目指す。
        let stage32 = CampaignStage(
            id: CampaignStageID(chapter: 3, index: 2),
            title: "縦横基礎",
            summary: "5×5 盤で縦横選択カードを活用し、40 手以内で踏破する計画力を養います。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithOrthogonalChoices,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
                penalties: standardPenalties
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 40),
            scoreTarget: 590,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage31.id)
        )

        // 3-3: 斜め選択カードを導入し、ペナルティ合計 2 以下で角マス攻略を学ぶ。
        let stage33 = CampaignStage(
            id: CampaignStageID(chapter: 3, index: 3),
            title: "斜め選択入門",
            summary: "斜め 4 方向の選択キングを使い分け、ペナルティ合計 2 以下で角マスを制圧します。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithDiagonalChoices,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
                penalties: standardPenalties
            ),
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
            scoreTarget: 580,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage32.id)
        )

        // 3-4: 桂馬選択カードを導入し、38 手以内のジャンプ操作を習得する。
        let stage34 = CampaignStage(
            id: CampaignStageID(chapter: 3, index: 4),
            title: "桂馬選択入門",
            summary: "桂馬の選択カードで遠距離マスを埋め、38 手以内で巡回する応用演習です。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithKnightChoices,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
                penalties: standardPenalties
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 38),
            scoreTarget: 570,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage33.id)
        )

        // 3-5: 任意スポーン＋二度踏みで 36 手以内の調整力を試す。
        let stage35DoubleVisit: [GridPoint: Int] = [
            GridPoint(x: 1, y: 1): 2,
            GridPoint(x: 3, y: 3): 2
        ]
        let stage35 = CampaignStage(
            id: CampaignStageID(chapter: 3, index: 5),
            title: "選択＋二度踏み",
            summary: "任意スポーンで二度踏みマスを制御し、36 手以内でまとめる応用ステージです。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithOrthogonalChoices,
                spawnRule: .chooseAnyAfterPreview,
                penalties: standardPenalties,
                additionalVisitRequirements: stage35DoubleVisit
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 36),
            scoreTarget: 560,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage34.id)
        )

        // 3-6: 全選択カードで三重踏みを処理し、ペナルティ合計 1 以下で安定攻略する。
        let stage36TripleVisit: [GridPoint: Int] = [
            GridPoint(x: 2, y: 2): 3,
            GridPoint(x: 3, y: 1): 3
        ]
        let stage36 = CampaignStage(
            id: CampaignStageID(chapter: 3, index: 6),
            title: "全選択＋三重踏み",
            summary: "全方向の選択カードを駆使し、三重踏みマスをペナルティ合計 1 以下で処理します。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
                penalties: standardPenalties,
                additionalVisitRequirements: stage36TripleVisit
            ),
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 1),
            scoreTarget: 550,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage35.id)
        )

        // 3-7: 任意スポーン＋四重踏みで 34 手以内の高速巡回を狙う。
        let stage37QuadVisit: [GridPoint: Int] = [
            GridPoint(x: 1, y: 1): 4,
            GridPoint(x: 3, y: 3): 4
        ]
        let stage37 = CampaignStage(
            id: CampaignStageID(chapter: 3, index: 7),
            title: "全選択＋四重踏み",
            summary: "内側に配置された四重踏みを全選択カードで制御し、34 手以内を目指す高難度ステージです。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: .chooseAnyAfterPreview,
                penalties: standardPenalties,
                additionalVisitRequirements: stage37QuadVisit
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 34),
            scoreTarget: 540,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage36.id)
        )

        // 3-8: ノーペナルティかつ 32 手以内を同時達成する総合演習。
        let stage38MixedVisit: [GridPoint: Int] = [
            GridPoint(x: 1, y: 1): 2,
            GridPoint(x: 2, y: 2): 3,
            GridPoint(x: 3, y: 3): 4
        ]
        let stage38 = CampaignStage(
            id: CampaignStageID(chapter: 3, index: 8),
            title: "総合演習",
            summary: "2/3/4 回踏みを組み合わせ、ノーペナルティかつ 32 手以内を達成する総仕上げです。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
                penalties: noPenaltyPenalties,
                additionalVisitRequirements: stage38MixedVisit
            ),
            secondaryObjective: .finishWithoutPenaltyAndWithinMoves(maxMoves: 32),
            scoreTarget: 530,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage37.id)
        )

        let chapter3 = CampaignChapter(
            id: 3,
            title: "多方向訓練",
            summary: "選択カードと複数踏破を段階導入する章。",
            stages: [stage31, stage32, stage33, stage34, stage35, stage36, stage37, stage38]
        )

        // MARK: - 4 章のステージ群
        // トグルマスと複数踏破を組み合わせ、反転挙動への理解を深める。
        let chapter4Penalties = standardPenalties
        let chapter4NoPenalty = noPenaltyPenalties
        let fixedSpawn5 = GameMode.SpawnRule.fixed(BoardGeometry.defaultSpawnPoint(for: 5))

        // 4-1: 基本のトグル 2 箇所を 30 手以内で制御。
        let stage41Toggles: Set<GridPoint> = [
            GridPoint(x: 1, y: 1),
            GridPoint(x: 3, y: 3)
        ]
        let stage41 = CampaignStage(
            id: CampaignStageID(chapter: 4, index: 1),
            title: "トグル基礎",
            summary: "2 箇所のトグルマスを操作し、30 手以内で反転ギミックに慣れる導入ステージです。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: fixedSpawn5,
                penalties: chapter4Penalties,
                toggleTilePoints: stage41Toggles
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 30),
            scoreTarget: 520,
            scoreTargetComparison: .lessThanOrEqual,
            // MARK: 第 4 章開始条件は前章スター数の蓄積を基準にし、幅広い攻略を促す
            unlockRequirement: .chapterTotalStars(chapter: 3, minimum: 16)
        )

        // 4-2: トグル 3 箇所でペナルティ合計 2 以下に抑える。
        let stage42Toggles: Set<GridPoint> = [
            GridPoint(x: 2, y: 2),
            GridPoint(x: 1, y: 3),
            GridPoint(x: 3, y: 1)
        ]
        let stage42 = CampaignStage(
            id: CampaignStageID(chapter: 4, index: 2),
            title: "トグル応用",
            summary: "3 箇所のトグルを捌き、ペナルティ合計 2 以下で制御する応用演習です。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: fixedSpawn5,
                penalties: chapter4Penalties,
                toggleTilePoints: stage42Toggles
            ),
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
            scoreTarget: 510,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage41.id)
        )

        // 4-3: トグルと二度踏みを組み合わせ、40 手以内でまとめる。
        let stage43DoubleVisit: [GridPoint: Int] = [
            GridPoint(x: 0, y: 2): 2,
            GridPoint(x: 4, y: 2): 2
        ]
        let stage43 = CampaignStage(
            id: CampaignStageID(chapter: 4, index: 3),
            title: "トグル＋二度踏み",
            summary: "左右に伸びる二度踏みマスとトグル制御を両立し、40 手以内を目指す課題です。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: fixedSpawn5,
                penalties: chapter4Penalties,
                additionalVisitRequirements: stage43DoubleVisit,
                toggleTilePoints: stage41Toggles
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 40),
            scoreTarget: 500,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage42.id)
        )

        // 4-4: 全選択カードへ切り替え、三重踏みをペナルティ合計 1 以下で管理。
        let stage44TripleVisit: [GridPoint: Int] = [
            GridPoint(x: 2, y: 2): 3
        ]
        let stage44 = CampaignStage(
            id: CampaignStageID(chapter: 4, index: 4),
            title: "トグル＋三重踏み",
            summary: "中央の三重踏みとトグルを同時に管理し、ペナルティ合計 1 以下でクリアする応用です。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: fixedSpawn5,
                penalties: chapter4Penalties,
                additionalVisitRequirements: stage44TripleVisit,
                toggleTilePoints: stage41Toggles
            ),
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 1),
            scoreTarget: 490,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage43.id)
        )

        // 4-5: 任意スポーンで四隅のトグルを 38 手以内に制御。
        let stage45Toggles: Set<GridPoint> = [
            GridPoint(x: 0, y: 0),
            GridPoint(x: 4, y: 0),
            GridPoint(x: 0, y: 4),
            GridPoint(x: 4, y: 4)
        ]
        let stage45 = CampaignStage(
            id: CampaignStageID(chapter: 4, index: 5),
            title: "トグル集中制御",
            summary: "任意スポーンで四隅トグルの順番を調整し、38 手以内に踏破する訓練です。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: .chooseAnyAfterPreview,
                penalties: chapter4Penalties,
                toggleTilePoints: stage45Toggles
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 38),
            scoreTarget: 480,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage44.id)
        )

        // 4-6: 四重踏みを追加し、36 手以内で速度感を鍛える。
        let stage46QuadVisit: [GridPoint: Int] = [
            GridPoint(x: 2, y: 2): 4
        ]
        let stage46 = CampaignStage(
            id: CampaignStageID(chapter: 4, index: 6),
            title: "トグル＋四重踏み",
            summary: "中央の四重踏みとトグルを組み合わせ、36 手以内でまとめる高速課題です。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: .chooseAnyAfterPreview,
                penalties: chapter4Penalties,
                additionalVisitRequirements: stage46QuadVisit,
                toggleTilePoints: stage41Toggles
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 36),
            scoreTarget: 470,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage45.id)
        )

        // 4-7: ノーペナルティ条件で複合ギミックを扱う。
        let stage47Additional: [GridPoint: Int] = [
            GridPoint(x: 0, y: 2): 2,
            GridPoint(x: 4, y: 2): 2,
            GridPoint(x: 2, y: 2): 3
        ]
        let stage47 = CampaignStage(
            id: CampaignStageID(chapter: 4, index: 7),
            title: "トグル＋複合踏破",
            summary: "二度踏みと三重踏みをトグルと併用し、ノーペナルティで攻略する高難度課題です。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: .chooseAnyAfterPreview,
                penalties: chapter4NoPenalty,
                additionalVisitRequirements: stage47Additional,
                toggleTilePoints: stage41Toggles
            ),
            secondaryObjective: .finishWithoutPenalty,
            scoreTarget: 460,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage46.id)
        )

        // 4-8: 34 手以内＆ノーペナルティで締める総合試験。
        let stage48Additional: [GridPoint: Int] = [
            GridPoint(x: 0, y: 0): 2,
            GridPoint(x: 4, y: 0): 3,
            GridPoint(x: 2, y: 2): 4
        ]
        let stage48Toggles: Set<GridPoint> = [
            GridPoint(x: 1, y: 1),
            GridPoint(x: 3, y: 3),
            GridPoint(x: 2, y: 4)
        ]
        let stage48 = CampaignStage(
            id: CampaignStageID(chapter: 4, index: 8),
            title: "総合演習",
            summary: "トグルと複数踏破を総動員し、34 手以内かつノーペナルティで踏破する最終試験です。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: fixedSpawn5,
                penalties: chapter4NoPenalty,
                additionalVisitRequirements: stage48Additional,
                toggleTilePoints: stage48Toggles
            ),
            secondaryObjective: .finishWithoutPenaltyAndWithinMoves(maxMoves: 34),
            scoreTarget: 450,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage47.id)
        )

        let chapter4 = CampaignChapter(
            id: 4,
            title: "反転応用",
            summary: "トグルと複数踏破を組み合わせる章。",
            stages: [stage41, stage42, stage43, stage44, stage45, stage46, stage47, stage48]
        )

        // MARK: - 5 章のステージ群
        // 障害物マスと複数ギミックを組み合わせる総合章。
        let chapter5Penalties = standardPenalties
        let chapter5NoPenalty = noPenaltyPenalties

        // 5-1: 障害物 2 箇所で 30 手以内を目指す導入。
        let stage51Impassable: Set<GridPoint> = [
            GridPoint(x: 1, y: 1),
            GridPoint(x: 3, y: 3)
        ]
        let stage51 = CampaignStage(
            id: CampaignStageID(chapter: 5, index: 1),
            title: "障害物基礎",
            summary: "対角に置かれた障害物を避け、30 手以内で踏破するルート構築を学びます。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: fixedSpawn5,
                penalties: chapter5Penalties,
                impassableTilePoints: stage51Impassable
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 30),
            scoreTarget: 500,
            scoreTargetComparison: .lessThanOrEqual,
            // MARK: 最終章は直前の章で十分なスターを獲得したプレイヤーに解放する
            unlockRequirement: .chapterTotalStars(chapter: 4, minimum: 16)
        )

        // 5-2: 障害物を 3 箇所へ増やし、ペナルティ合計 2 以下で安定させる。
        let stage52Impassable: Set<GridPoint> = [
            GridPoint(x: 1, y: 1),
            GridPoint(x: 3, y: 3),
            GridPoint(x: 2, y: 2)
        ]
        let stage52 = CampaignStage(
            id: CampaignStageID(chapter: 5, index: 2),
            title: "障害物応用",
            summary: "中心を含む障害物 3 箇所を管理し、ペナルティ合計 2 以下で踏破する演習です。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: .chooseAnyAfterPreview, // 中央を含む障害物 `stage52Impassable` に合わせ、任意スポーンで初期詰みを回避
                penalties: chapter5Penalties,
                impassableTilePoints: stage52Impassable
            ),
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
            scoreTarget: 490,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage51.id)
        )

        // 5-3: 障害物と二度踏みを組み合わせ、40 手以内を狙う。
        let stage53Impassable: Set<GridPoint> = [
            GridPoint(x: 0, y: 1),
            GridPoint(x: 4, y: 3)
        ]
        let stage53DoubleVisit: [GridPoint: Int] = [
            GridPoint(x: 1, y: 3): 2,
            GridPoint(x: 3, y: 1): 2
        ]
        let stage53 = CampaignStage(
            id: CampaignStageID(chapter: 5, index: 3),
            title: "障害物＋二度踏み",
            summary: "障害物を避けながら二度踏みマスを処理し、40 手以内で踏破する実戦課題です。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: fixedSpawn5,
                penalties: chapter5Penalties,
                additionalVisitRequirements: stage53DoubleVisit,
                impassableTilePoints: stage53Impassable
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 40),
            scoreTarget: 480,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage52.id)
        )

        // 5-4: 任意スポーンで三重踏み＋障害物を扱い、ペナルティ合計 1 以下を目指す。
        let stage54Impassable: Set<GridPoint> = [
            GridPoint(x: 0, y: 2),
            GridPoint(x: 4, y: 2)
        ]
        let stage54TripleVisit: [GridPoint: Int] = [
            GridPoint(x: 2, y: 2): 3
        ]
        let stage54 = CampaignStage(
            id: CampaignStageID(chapter: 5, index: 4),
            title: "障害物＋三重踏み",
            summary: "任意スポーンで三重踏みと障害物を管理し、ペナルティ合計 1 以下で安定攻略します。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: .chooseAnyAfterPreview,
                penalties: chapter5Penalties,
                additionalVisitRequirements: stage54TripleVisit,
                impassableTilePoints: stage54Impassable
            ),
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 1),
            scoreTarget: 470,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage53.id)
        )

        // 5-5: 障害物とトグルを組み合わせ、38 手以内で制御する。
        let stage55Impassable: Set<GridPoint> = [
            GridPoint(x: 1, y: 1),
            GridPoint(x: 3, y: 3)
        ]
        let stage55Toggles: Set<GridPoint> = [
            GridPoint(x: 2, y: 1),
            GridPoint(x: 2, y: 3)
        ]
        let stage55 = CampaignStage(
            id: CampaignStageID(chapter: 5, index: 5),
            title: "障害物＋トグル",
            summary: "中央列のトグルと障害物を同時に捌き、38 手以内のルート最適化を図ります。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: fixedSpawn5,
                penalties: chapter5Penalties,
                toggleTilePoints: stage55Toggles,
                impassableTilePoints: stage55Impassable
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 38),
            scoreTarget: 460,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage54.id)
        )

        // 5-6: 任意スポーンで四重踏みとトグルを扱い、36 手以内を狙う。
        let stage56Impassable: Set<GridPoint> = [
            GridPoint(x: 1, y: 1),
            GridPoint(x: 3, y: 3)
        ]
        let stage56QuadVisit: [GridPoint: Int] = [
            GridPoint(x: 2, y: 2): 4
        ]
        let stage56Toggles: Set<GridPoint> = [
            GridPoint(x: 0, y: 4)
        ]
        let stage56 = CampaignStage(
            id: CampaignStageID(chapter: 5, index: 6),
            title: "複合 (四重踏み含む)",
            summary: "任意スポーンで四重踏みとトグルを裁き、36 手以内にまとめる複合課題です。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: .chooseAnyAfterPreview,
                penalties: chapter5Penalties,
                additionalVisitRequirements: stage56QuadVisit,
                toggleTilePoints: stage56Toggles,
                impassableTilePoints: stage56Impassable
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 36),
            scoreTarget: 450,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage55.id)
        )

        // 5-7: ノーペナルティ条件で障害物＋複数踏破＋トグルを管理。
        let stage57Impassable: Set<GridPoint> = [
            GridPoint(x: 1, y: 1),
            GridPoint(x: 3, y: 3),
            GridPoint(x: 2, y: 4)
        ]
        let stage57Additional: [GridPoint: Int] = [
            GridPoint(x: 0, y: 0): 2,
            GridPoint(x: 4, y: 4): 3
        ]
        let stage57Toggles: Set<GridPoint> = [
            GridPoint(x: 2, y: 2)
        ]
        let stage57 = CampaignStage(
            id: CampaignStageID(chapter: 5, index: 7),
            title: "複合 (多要素)",
            summary: "障害物と複数踏破・トグルを同時に管理し、ノーペナルティで攻略する最終調整です。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: .chooseAnyAfterPreview,
                penalties: chapter5NoPenalty,
                additionalVisitRequirements: stage57Additional,
                toggleTilePoints: stage57Toggles,
                impassableTilePoints: stage57Impassable
            ),
            secondaryObjective: .finishWithoutPenalty,
            scoreTarget: 440,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage56.id)
        )

        // 5-8: 34 手以内＆ノーペナルティで締める最終試験。
        let stage58Impassable: Set<GridPoint> = [
            GridPoint(x: 1, y: 1),
            GridPoint(x: 3, y: 3),
            GridPoint(x: 2, y: 2)
        ]
        let stage58Additional: [GridPoint: Int] = [
            GridPoint(x: 0, y: 4): 2,
            GridPoint(x: 4, y: 0): 3,
            GridPoint(x: 2, y: 4): 4
        ]
        let stage58Toggles: Set<GridPoint> = [
            GridPoint(x: 1, y: 3),
            GridPoint(x: 3, y: 1)
        ]
        let stage58 = CampaignStage(
            id: CampaignStageID(chapter: 5, index: 8),
            title: "最終試験",
            summary: "障害物・トグル・複数踏破を総動員し、34 手以内かつノーペナルティで仕上げる最終試験です。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: .chooseAnyAfterPreview, // 中央を塞ぐ障害物と多重踏破の同居に合わせ、任意スポーンで整合性を確保
                penalties: chapter5NoPenalty,
                additionalVisitRequirements: stage58Additional,
                toggleTilePoints: stage58Toggles,
                impassableTilePoints: stage58Impassable
            ),
            secondaryObjective: .finishWithoutPenaltyAndWithinMoves(maxMoves: 34),
            scoreTarget: 430,
            scoreTargetComparison: .lessThanOrEqual,
            unlockRequirement: .stageClear(stage57.id)
        )

        let chapter5 = CampaignChapter(
            id: 5,
            title: "障害物攻略",
            summary: "障害物と複合ギミックを乗り越える章。",
            stages: [stage51, stage52, stage53, stage54, stage55, stage56, stage57, stage58]
        )

        return [chapter1, chapter2, chapter3, chapter4, chapter5]
    }
}
