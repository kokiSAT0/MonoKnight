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
        // MARK: 章 1 は盤面と山札を段階的に拡張し、任意スポーンの導入までを網羅する。

        // 章内で複数ステージが共有するペナルティ設定を事前に用意し、可読性を高める。
        let penaltyStage11 = GameMode.PenaltySettings(
            deadlockPenaltyCost: 2,
            manualRedrawPenaltyCost: 2,
            manualDiscardPenaltyCost: 1,
            revisitPenaltyCost: 1
        )
        let penaltyStage12 = GameMode.PenaltySettings(
            deadlockPenaltyCost: 2,
            manualRedrawPenaltyCost: 2,
            manualDiscardPenaltyCost: 1,
            revisitPenaltyCost: 0
        )
        let penaltyStage13to14 = GameMode.PenaltySettings(
            deadlockPenaltyCost: 3,
            manualRedrawPenaltyCost: 1,
            manualDiscardPenaltyCost: 1,
            revisitPenaltyCost: 0
        )
        let penaltyStage15onward = GameMode.PenaltySettings(
            deadlockPenaltyCost: 3,
            manualRedrawPenaltyCost: 2,
            manualDiscardPenaltyCost: 1,
            revisitPenaltyCost: 0
        )

        // 1-1: 王将カードのみでタイムアタックを行う超入門ステージ。
        let stage11 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 1),
            title: "王将訓練",
            summary: "3×3 の盤で王将カードだけを使い、移動の基本を体験しましょう。",
            regulation: GameMode.Regulation(
                boardSize: 3,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingOnly,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 3)),
                penalties: penaltyStage11
            ),
            secondaryObjective: .finishWithinSeconds(maxSeconds: 120),
            scoreTarget: 900,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .always
        )

        // 1-2: 王将＋桂馬デッキでペナルティ管理を学ぶステージ。
        let stage12 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 2),
            title: "ナイト初見",
            summary: "王将と桂馬の混成デッキで、引き直しペナルティに気を付けながら攻略しましょう。",
            regulation: GameMode.Regulation(
                boardSize: 3,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingPlusKnightOnly,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 3)),
                penalties: penaltyStage12
            ),
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 5),
            scoreTarget: 800,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage11.id)
        )

        // 1-3: 4×4 盤でキングと桂馬のみを扱う基本演習。
        let stage13 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 3),
            title: "4×4基礎",
            summary: "4×4 盤でキングと桂馬の基本カードだけを使い、広い盤面へ慣れていきましょう。",
            regulation: GameMode.Regulation(
                boardSize: 4,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingAndKnightBasic,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 4)),
                penalties: penaltyStage13to14
            ),
            secondaryObjective: .finishWithinSeconds(maxSeconds: 60),
            scoreTarget: 600,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage12.id)
        )

        // 1-4: 任意スポーンで開幕位置を選び、ペナルティを 3 回以内に抑える応用演習。
        let stage14 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 4),
            title: "4×4応用",
            summary: "開始位置を自由に選び、キングと桂馬のデッキでルートを組み立てましょう。",
            regulation: GameMode.Regulation(
                boardSize: 4,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingAndKnightBasic,
                spawnRule: .chooseAnyAfterPreview,
                penalties: penaltyStage13to14
            ),
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 3),
            scoreTarget: 550,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage13.id)
        )

        // 1-5: 標準ライトデッキで 30 手以内を目指す持久戦練習。
        let stage15 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 5),
            title: "4×4持久",
            summary: "長距離カードを減らした標準ライト構成で、30 手以内の踏破を目指しましょう。",
            regulation: GameMode.Regulation(
                boardSize: 4,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 4)),
                penalties: penaltyStage15onward
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 30),
            scoreTarget: 500,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage14.id)
        )

        // 1-6: 任意スポーンでペナルティを 2 回以内へ抑える戦略演習。
        let stage16 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 6),
            title: "4×4戦略",
            summary: "任意スポーンを活かし、キングと桂馬の基本デッキでペナルティを最小限に抑えましょう。",
            regulation: GameMode.Regulation(
                boardSize: 4,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .kingAndKnightBasic,
                spawnRule: .chooseAnyAfterPreview,
                penalties: penaltyStage15onward
            ),
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 2),
            scoreTarget: 480,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage15.id)
        )

        // 1-7: 5×5 盤へ拡張し、40 手以内での踏破を目指す導入ステージ。
        let stage17 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 7),
            title: "5×5導入",
            summary: "標準ライト構成で 5×5 盤に挑戦し、40 手以内の安定した踏破を狙いましょう。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
                penalties: penaltyStage15onward
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 40),
            scoreTarget: 460,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage16.id)
        )

        // 1-8: 任意スポーンを駆使し、5×5 盤で 35 手以内の踏破を目指す総合演習。
        let stage18 = CampaignStage(
            id: CampaignStageID(chapter: 1, index: 8),
            title: "総合演習",
            summary: "任意スポーンと標準ライト構成を組み合わせ、35 手以内での総合攻略に挑みましょう。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardLight,
                spawnRule: .chooseAnyAfterPreview,
                penalties: penaltyStage15onward
            ),
            secondaryObjective: .finishWithinMoves(maxMoves: 35),
            scoreTarget: 440,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage17.id)
        )

        let chapter1 = CampaignChapter(
            id: 1,
            title: "基礎訓練",
            summary: "カード移動の定石を学ぶ章。",
            stages: [stage11, stage12, stage13, stage14, stage15, stage16, stage17, stage18]
        )

        // MARK: - 2 章のステージ群
        // (1,2) と (3,4) の指定は 1 始まりの座標と解釈し、内部表現の 0 始まりへ変換する。
        let doubleVisitOverrides: [GridPoint: Int] = [
            GridPoint(x: 0, y: 1): 2,
            GridPoint(x: 2, y: 3): 2
        ]

        let stage21 = CampaignStage(
            id: CampaignStageID(chapter: 2, index: 1),
            title: "重踏応用",
            summary: "二度踏まないと踏破できない特殊マスを活用する演習です。",
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
                ),
                additionalVisitRequirements: doubleVisitOverrides
            ),
            secondaryObjective: .finishWithPenaltyAtMost(maxPenaltyCount: 5),
            scoreTarget: 350,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage12.id)
        )

        let chapter2 = CampaignChapter(
            id: 2,
            title: "応用特訓",
            summary: "複数回踏むマスを扱う章。",
            stages: [stage21]
        )

        // MARK: - 3 章のステージ群
        // スタンダード 5×5 をベースに、複数方向候補カードの扱いを学ぶ章
        let standardPenalties = GameMode.standard.penalties

        // 3-1 は上下左右の選択キングに慣れる導入ステージ。まずはペナルティを抑えて丁寧に動いてもらう。
        let stage31 = CampaignStage(
            id: CampaignStageID(chapter: 3, index: 1),
            title: "縦横選択訓練",
            summary: "標準デッキに上下左右を選べるキングカードを加え、選択操作の基礎を体感しましょう。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithOrthogonalChoices,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: standardPenalties.deadlockPenaltyCost,
                    manualRedrawPenaltyCost: standardPenalties.manualRedrawPenaltyCost,
                    manualDiscardPenaltyCost: standardPenalties.manualDiscardPenaltyCost,
                    revisitPenaltyCost: standardPenalties.revisitPenaltyCost
                )
            ),
            // MARK: 2 個目のスター条件: ペナルティを完全に回避して選択操作を丁寧に行う
            secondaryObjective: .finishWithoutPenalty,
            scoreTarget: 600,
            unlockRequirement: .stageClear(stage21.id)
        )

        // 3-2 は斜めの選択キングだけで構成し、盤面を縦横斜めの三方向で把握する練習へ発展させる。
        let stage32 = CampaignStage(
            id: CampaignStageID(chapter: 3, index: 2),
            title: "斜め選択応用",
            summary: "標準デッキへ斜め 4 方向の選択キングを加え、角マス制圧のコツを学びましょう。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithDiagonalChoices,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: standardPenalties.deadlockPenaltyCost,
                    manualRedrawPenaltyCost: standardPenalties.manualRedrawPenaltyCost,
                    manualDiscardPenaltyCost: standardPenalties.manualDiscardPenaltyCost,
                    revisitPenaltyCost: standardPenalties.revisitPenaltyCost
                )
            ),
            // MARK: 2 個目のスター条件: 移動手数 32 以内を要求し、先読みと分岐判断の精度を高める
            secondaryObjective: .finishWithinMoves(maxMoves: 32),
            scoreTarget: 580,
            unlockRequirement: .stageClear(stage31.id)
        )

        // 3-3 は桂馬の選択カードのみ。斜めだけでは届かないマスを跳躍で埋める判断を身につける段階。
        let stage33 = CampaignStage(
            id: CampaignStageID(chapter: 3, index: 3),
            title: "桂馬選択攻略",
            summary: "標準デッキへ桂馬の選択カードを追加し、遠距離マスを効率良く踏破しましょう。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithKnightChoices,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: standardPenalties.deadlockPenaltyCost,
                    manualRedrawPenaltyCost: standardPenalties.manualRedrawPenaltyCost,
                    manualDiscardPenaltyCost: standardPenalties.manualDiscardPenaltyCost,
                    revisitPenaltyCost: standardPenalties.revisitPenaltyCost
                )
            ),
            // MARK: 2 個目のスター条件: 桂馬特有のルートを活かし 30 手以内の踏破を目指す
            secondaryObjective: .finishWithinMoves(maxMoves: 30),
            scoreTarget: 560,
            unlockRequirement: .stageClear(stage32.id)
        )

        // 3-4 は全種類の選択カードを混在させた最終チェック。すべての操作感を統合して素早く判断する。
        let stage34 = CampaignStage(
            id: CampaignStageID(chapter: 3, index: 4),
            title: "総合選択演習",
            summary: "標準デッキに全選択カードを加え、全方向の応用力を試しましょう。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: standardPenalties.deadlockPenaltyCost,
                    manualRedrawPenaltyCost: standardPenalties.manualRedrawPenaltyCost,
                    manualDiscardPenaltyCost: standardPenalties.manualDiscardPenaltyCost,
                    revisitPenaltyCost: standardPenalties.revisitPenaltyCost
                )
            ),
            // MARK: 2 個目のスター条件: 28 手以内で踏破し、多方向カードを自在に使い分けることを促す
            secondaryObjective: .finishWithinMoves(maxMoves: 28),
            scoreTarget: 540,
            scoreTargetComparison: .lessThan,
            unlockRequirement: .stageClear(stage33.id)
        )

        let chapter3 = CampaignChapter(
            id: 3,
            title: "多方向訓練",
            summary: "複数候補カードを使い分ける章。",
            stages: [stage31, stage32, stage33, stage34]
        )

        // MARK: - 4 章のステージ群
        // 4-1 では 5×5 盤にトグルマスを導入し、踏破の反転ギミックに慣れてもらう。
        // - Important: 指示された (1,2) と (3,4) は 1 始まりで提供されたため、内部表現の 0 始まり座標へ読み替える。
        let togglePointsChapter4: Set<GridPoint> = [
            GridPoint(x: 0, y: 1),
            GridPoint(x: 2, y: 3)
        ]

        let stage41 = CampaignStage(
            id: CampaignStageID(chapter: 4, index: 1),
            title: "反転制御訓練", // 章タイトルとの整合を意識した名前にする
            summary: "トグルマスで踏破状態が切り替わる 5×5 を攻略し、ギミック対応力を養いましょう。",
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standard,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: standardPenalties.deadlockPenaltyCost,
                    manualRedrawPenaltyCost: standardPenalties.manualRedrawPenaltyCost,
                    manualDiscardPenaltyCost: standardPenalties.manualDiscardPenaltyCost,
                    revisitPenaltyCost: standardPenalties.revisitPenaltyCost
                ),
                toggleTilePoints: togglePointsChapter4
            ),
            // MARK: 2 個目のスター条件: ギミックを理解したうえで 30 手以内の踏破を狙う
            secondaryObjective: .finishWithinMoves(maxMoves: 30),
            // MARK: 3 個目のスター条件: トグルで増える手数を抑えつつスコア 520 以下でまとめる
            scoreTarget: 520,
            // MARK: アンロック条件: 3-4 クリア後に開放し、章間の到達順を保つ
            unlockRequirement: .stageClear(stage34.id)
        )

        let chapter4 = CampaignChapter(
            id: 4,
            title: "反転応用", // 章全体のテーマとしてトグルギミックを強調
            summary: "トグルマスの挙動を扱う章。",
            stages: [stage41]
        )

        // MARK: - 5 章のステージ群
        // (1,2) と (3,4) の座標指定は 1 始まりで共有されたため、障害物マスとして 0 始まりへ読み替える。
        let impassablePointsChapter5: Set<GridPoint> = [
            GridPoint(x: 0, y: 1),
            GridPoint(x: 2, y: 3)
        ]

        // 5-1 は 5×5 盤で標準デッキを使い、移動不可マスを避けながらルートを組む終盤演習ステージ。
        // スター条件でも移動不可マスの存在を意識してもらえるよう、手数とスコアの両面から丁寧な経路計画を促す。
        let stage51 = CampaignStage(
            id: CampaignStageID(chapter: 5, index: 1),
            title: "障害物突破演習",
            summary: "移動不可マスで封鎖された 5×5 を突破し、障害物との距離感を把握しましょう。", // 説明文でも移動不可マスを明示
            regulation: GameMode.Regulation(
                boardSize: 5,
                handSize: 5,
                nextPreviewCount: 3,
                allowsStacking: true,
                deckPreset: .standardWithAllChoices,
                spawnRule: .fixed(BoardGeometry.defaultSpawnPoint(for: 5)),
                penalties: GameMode.PenaltySettings(
                    deadlockPenaltyCost: standardPenalties.deadlockPenaltyCost,
                    manualRedrawPenaltyCost: standardPenalties.manualRedrawPenaltyCost,
                    manualDiscardPenaltyCost: standardPenalties.manualDiscardPenaltyCost,
                    revisitPenaltyCost: standardPenalties.revisitPenaltyCost
                ),
                impassableTilePoints: impassablePointsChapter5
            ),
            // MARK: 2 個目のスター条件: 障害物を意識しながら 27 手以内にまとめ、無駄な踏破を抑える
            secondaryObjective: .finishWithinMoves(maxMoves: 27),
            // MARK: 3 個目のスター条件: 移動不可マスによる遠回りを最小限に抑え、スコア 500 未満でクリア
            scoreTarget: 500,
            scoreTargetComparison: .lessThan,
            // MARK: アンロック条件: トグル訓練の 4-1 を突破したプレイヤー向けに段階的な難度上昇を用意
            unlockRequirement: .stageClear(stage41.id)
        )

        let chapter5 = CampaignChapter(
            id: 5,
            title: "障害物攻略", // 章タイトルでも移動不可マスの攻略を強調する
            summary: "移動不可マスを回避しながら踏破する章。",
            stages: [stage51]
        )

        return [chapter1, chapter2, chapter3, chapter4, chapter5]
    }
}
