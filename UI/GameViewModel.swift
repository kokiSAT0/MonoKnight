import Combine  // Combine を利用して GameCore の更新を ViewModel 経由で伝搬する
import Foundation
import Game
import SharedSupport
import SwiftUI
import UIKit

/// GameView のロジックとサービス連携を担う ViewModel
/// 描画に直接関係しない処理を SwiftUI View から切り離し、責務を明確化する
@MainActor
final class GameViewModel: ObservableObject {
    /// ゲームモードごとの設定
    let mode: GameMode
    /// Game パッケージが提供するファクトリセット
    let gameInterfaces: GameModuleInterfaces
    /// Game Center 連携を担当するサービス
    let gameCenterService: GameCenterServiceProtocol
    /// 広告表示の状態管理を担当するサービス
    let adsService: AdsServiceProtocol
    /// 塔ダンジョンの永続成長ストア
    let dungeonGrowthStore: DungeonGrowthStore
    /// 塔攻略の中断復帰ストア
    let dungeonRunResumeStore: DungeonRunResumeStore
    /// 試練塔のローカル最高到達記録ストア
    let rogueTowerRecordStore: RogueTowerRecordStore
    /// 基礎塔の完了状態と成長塔への初回誘導状態を管理するストア
    let tutorialTowerProgressStore: TutorialTowerProgressStore
    /// 遊び方辞典の発見状態ストア
    let encyclopediaDiscoveryStore: EncyclopediaDiscoveryStore
    /// Game Center サインインを再度促す要求を親へ伝えるクロージャ
    let onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?
    /// タイトル復帰時に親へ伝えるためのクロージャ
    let onRequestReturnToTitle: (() -> Void)?
    /// ダンジョンランで次のフロアへ遷移したい場合のリクエストクロージャ
    let onRequestStartDungeonFloor: ((GameMode) -> Void)?
    /// テスター向けに現在階の開始直後へ戻すための一時スナップショット
    let floorStartDungeonResumeSnapshot: DungeonRunResumeSnapshot?

    /// SwiftUI から観測するゲームロジック本体
    @Published private(set) var core: GameCore
    /// 初回描画から使う手札表示用スナップショット
    /// - Note: `core.$handStacks` の初回通知を待たず、塔の持ち越し報酬カードを開始直後から表示する。
    @Published var displayedHandStacks: [HandStack] = []
    /// 拾得などで直近に増えた手札スタック ID
    @Published var recentlyAddedHandStackIDs: Set<UUID> = []
    /// 直近に効果を発動した通常遺物 ID
    @Published var activeDungeonRelicActivationIDs: Set<DungeonRelicID> = []
    /// 手札増加エフェクトの差分検出に使う直前スナップショット
    var previousDisplayedHandStacksForAdditionEffect: [HandStack] = []
    /// 短命エフェクトを消すための世代番号
    var handAdditionEffectGeneration: Int = 0
    /// レリック発動エフェクトを出し続ける基準手数
    var dungeonRelicActivationMoveCounts: [DungeonRelicID: Int] = [:]
    /// 移動演出中だけ利用する HP 表示上書き
    @Published var movementPresentationDungeonHP: Int?
    /// 移動演出中は手札/HP の通常同期を一時停止する
    var isMovementPresentationActive = false
    /// 移動演出中、拾得/宝箱オーバーレイ確認のためにリプレイを止めている状態
    @Published var movementPresentationOverlayPause: MovementPresentationOverlayPause?
    enum MovementPresentationOverlayPause: Equatable {
        case cardPickupChoice
        case relicPickupChoice
        case relicAcquisition
    }
    /// 移動演出中に表示上到達済みになったカード拾得 ID
    var movementPresentationReachedCardPickupIDs: Set<String> = []
    /// 移動演出中に表示上到達済みになった宝箱 ID
    var movementPresentationReachedRelicPickupIDs: Set<String> = []
    /// 移動演出開始時点で既に消えていたカード拾得 ID
    var movementPresentationSeenCardPickupIDs: Set<String> = []
    /// 移動演出開始時点で既に消えていた宝箱 ID
    var movementPresentationSeenRelicPickupIDs: Set<String> = []
    /// 移動演出が終わってから反映する進行状態
    var deferredProgressDuringMovementPresentation: GameProgress?
    /// 移動演出が終わってから反映する落下イベント
    var deferredDungeonFallEventDuringMovementPresentation: DungeonFallEvent?
    /// 移動演出が終わってから反映する逆巻き復活イベント
    var deferredDungeonRewindReviveEventDuringMovementPresentation: DungeonRewindReviveEvent?
    /// 移動後に保留された敵ターンが終わるまで結果表示を待つかどうか
    var isWaitingForEnemyTurnPresentationAfterMovement = false
    static let maximumDungeonInventoryVisibleSlotCount = 9
    var dungeonInventoryVisibleSlotCount: Int {
        guard mode.usesDungeonExit else { return mode.handSize }
        let limit = core.dungeonInventoryKindLimit
        return limit > 0 ? limit : mode.handSize
    }
    var dungeonBasicMoveSlotIndex: Int {
        dungeonInventoryVisibleSlotCount
    }
    /// SpriteKit と SwiftUI を仲介するための ViewModel
    let boardBridge: GameBoardBridgeViewModel
    /// 盤面演出による全体入力ロックをかけるかどうか
    var isGlobalGameInteractionDisabled: Bool {
        boardBridge.isInputAnimationActive && movementPresentationOverlayPause == nil
    }
    /// 現在選択中の手札スタック ID
    /// - Important: 手札スロットの選択状態を SwiftUI から装飾できるよう公開し、候補マス確定後にリセットする。
    @Published var selectedHandStackID: UUID?
    /// 基本移動カードの表示用選択状態
    /// - Note: 入力処理中の `GameSessionState` へ SwiftUI が直接アクセスしないよう、表示用の値を分離する。
    var isBasicMoveCardSelectionVisible = false

    /// 結果画面表示フラグ
    @Published var showingResult = false {
        didSet {
            resultPresentationState.showingResult = showingResult
        }
    }
    /// 直近の塔クリアで得た成長報酬
    @Published var latestDungeonGrowthAward: DungeonGrowthAward?
    /// 同一クリア通知で成長報酬を二重登録しないためのキー
    var registeredDungeonGrowthAwardKey: String?
    /// 手詰まりバナーに表示するイベント情報
    @Published var activePenaltyBanner: PenaltyEvent? {
        didSet {
            sessionUIState.activePenaltyBanner = activePenaltyBanner
        }
    }
    /// メニューで確認待ちのアクション
    @Published var pendingMenuAction: GameMenuAction? {
        didSet {
            sessionUIState.pendingMenuAction = pendingMenuAction
        }
    }
    /// 取得直後に詳細表示する遺物/宝箱結果
    @Published var activeDungeonRelicAcquisitionPresentation: DungeonRelicAcquisitionPresentation?
    /// 怪しい宝箱で選択待ちの候補
    @Published var pendingDungeonRelicPickupChoice: PendingDungeonRelicPickupChoice?
    /// 拾得/宝箱選択を保留したまま盤面確認中かどうか
    @Published var isDungeonChoiceOverlayCollapsed = false
    var pendingDungeonRelicAcquisitionPresentations: [DungeonRelicAcquisitionPresentation] = []
    var observedDungeonRelicAcquisitionPresentationIDs: Set<UUID> = []
    /// ポーズメニューの表示状態
    @Published var isPauseMenuPresented = false {
        didSet {
            sessionUIState.setPauseMenuPresented(isPauseMenuPresented)
            handlePauseMenuVisibilityChange(isPresented: isPauseMenuPresented)
        }
    }
    /// 統計バッジ領域の高さ
    @Published var statisticsHeight: CGFloat = 0
    /// 手札セクションの高さ
    @Published var handSectionHeight: CGFloat = 0
    /// 画面に表示している経過秒数
    @Published var displayedElapsedSeconds: Int = 0 {
        didSet {
            sessionUIState.displayedElapsedSeconds = displayedElapsedSeconds
        }
    }
    /// 暫定スコア
    var displayedScore: Int {
        return core.totalMoveCount * 10 + displayedElapsedSeconds
    }
    /// 現在の移動回数
    /// - Note: 統計バッジ表示で利用し、View 側から GameCore への直接依存を減らす
    var moveCount: Int { core.moveCount }
    /// 累計ペナルティ手数
    /// - Note: ペナルティバナーや統計表示の数値として再利用する
    var penaltyCount: Int { core.penaltyCount }
    /// クリア確定時点の経過秒数
    /// - Note: 結果画面や統計表示で参照するための公開プロパティ
    var elapsedSeconds: Int { core.elapsedSeconds }
    /// 未踏破マスの残数
    /// - Note: 進行状況バッジに表示するために用意する
    var remainingTiles: Int { core.remainingTiles }
    /// 出口到達型ダンジョンかどうか
    var usesDungeonExit: Bool { mode.usesDungeonExit }
    /// ダンジョン HP
    var dungeonHP: Int { movementPresentationDungeonHP ?? core.dungeonHP }
    /// ダンジョン残り手数
    var remainingDungeonTurns: Int? { core.remainingDungeonTurns }
    /// ダンジョン手数上限
    var dungeonTurnLimit: Int? { core.effectiveDungeonTurnLimit }
    /// ダンジョン疲労インジケーター状態
    var dungeonFatigueIndicatorState: DungeonFatigueIndicatorState? { core.dungeonFatigueIndicatorState }
    /// 凍結の呪文で停止している敵ターンの残り回数
    var enemyFreezeTurnsRemaining: Int { core.enemyFreezeTurnsRemaining }
    /// 障壁の呪文で HP ダメージを無効化できる残り回数
    var damageBarrierTurnsRemaining: Int { core.damageBarrierTurnsRemaining }
    /// 足枷罠で現在フロア中の敵ターンが重くなっているかどうか
    var isShackled: Bool { core.isShackled }
    /// 幻惑罠で現在フロア中の移動カードが伏せられているかどうか
    var isIlluded: Bool { core.isIlluded }
    var staggerForcedMovesRemaining: Int { core.staggerForcedMovesRemaining }
    var isEmptyHandStaggerActive: Bool {
        core.isEmptyHandStaggerAutoActive
    }
    /// 毒状態の残りダメージ回数
    var poisonDamageTicksRemaining: Int { core.poisonDamageTicksRemaining }
    /// 次の毒ダメージまでの成功行動数
    var poisonActionsUntilNextDamage: Int { core.poisonActionsUntilNextDamage }
    /// ダンジョン出口座標
    var dungeonExitPoint: GridPoint? { mode.dungeonExitPoint }
    /// ダンジョン出口が解錠済みかどうか
    var isDungeonExitUnlocked: Bool { core.isDungeonExitUnlocked }
    /// ダンジョンラン状態
    var dungeonRunState: DungeonRunState? { mode.dungeonMetadataSnapshot?.runState }
    /// ダンジョンランの階層表示
    var dungeonRunFloorText: String? {
        guard let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID)
        else { return nil }
        if dungeon.supportsInfiniteFloors {
            return "\(dungeon.title) \(runState.floorNumber)F"
        }
        return "\(dungeon.title) \(runState.floorNumber)/\(dungeon.floors.count)F"
    }
    /// 試練塔のローカル最高到達表示
    var rogueTowerRecordText: String? {
        guard let metadata = mode.dungeonMetadataSnapshot,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID)
        else { return nil }
        return rogueTowerRecordStore.highestFloorText(for: dungeon)
    }
    /// リザルトの再挑戦ボタンに表示する開始階
    var dungeonRetryStartFloorText: String? {
        guard let metadata = mode.dungeonMetadataSnapshot,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID)
        else { return nil }

        let currentFloorIndex = metadata.runState?.currentFloorIndex ?? 0
        let startFloorIndex = dungeon.difficulty == .growth
            ? (currentFloorIndex / 10) * 10
            : 0
        return "\(startFloorIndex + 1)F"
    }
    /// リザルトの再挑戦ボタン文言
    var resultRetryButtonTitle: String {
        guard mode.usesDungeonExit else { return "リトライ" }
        return "\(dungeonRetryStartFloorText ?? "1F")から再挑戦"
    }
    /// ダンジョンランの累計移動手数
    var dungeonRunTotalMoveCount: Int? {
        dungeonRunState?.totalMoveCountIncludingCurrentFloor(core.moveCount)
    }
    /// ダンジョンランの累計所要時間
    var dungeonRunTotalElapsedSeconds: Int? {
        dungeonRunState?.totalElapsedSecondsIncludingCurrentFloor(core.elapsedSeconds)
    }
    /// リザルトに表示する所要時間
    var resultElapsedSeconds: Int {
        guard usesDungeonExit,
              !isResultFailed,
              nextDungeonFloorTitle == nil
        else { return core.elapsedSeconds }
        return dungeonRunTotalElapsedSeconds ?? core.elapsedSeconds
    }
    /// ラン中に持ち越している報酬カード
    var dungeonRewardInventoryEntries: [DungeonInventoryEntry] {
        core.dungeonInventoryEntries.compactMap { $0.carryingRewardUsesOnly() }
    }
    /// 塔で現在所持しているカード
    var dungeonInventoryEntries: [DungeonInventoryEntry] {
        core.dungeonInventoryEntries
    }
    /// 塔で現在所持している通常遺物
    var dungeonRelicEntries: [DungeonRelicEntry] {
        core.dungeonRelicEntries
    }
    /// 塔で現在所持している呪い遺物
    var dungeonCurseEntries: [DungeonCurseEntry] {
        core.dungeonCurseEntries
    }
    /// レリック/呪い効果の計算だけに使う通常遺物一覧
    var effectEnabledDungeonRelicEntries: [DungeonRelicEntry] {
        core.areDungeonRelicAndCurseEffectsEnabled ? core.dungeonRelicEntries : []
    }
    /// レリック/呪い効果の計算だけに使う呪い遺物一覧
    var effectEnabledDungeonCurseEntries: [DungeonCurseEntry] {
        core.areDungeonRelicAndCurseEffectsEnabled ? core.dungeonCurseEntries : []
    }
    var isDiagnosticShareAvailable: Bool {
        DebugLogHistory.shared.isFrontEndViewerAvailable
    }
    func makeTesterIssueReport() -> String {
        let reportIssueLogMessage = makeReportIssueOpenedLogMessage()
        let reproductionBlock = makeTesterReproductionBlock()
        var playLogEntries = DebugLogHistory.shared.snapshot().filter { $0.message.contains("[PLAY]") }
        if !playLogEntries.contains(where: { $0.message.contains(reportIssueLogMessage) }) {
            playLogEntries.append(DebugLogEntry(level: .info, message: reportIssueLogMessage))
        }
        return DebugLogShareReportFormatter.makeReport(
            context: DebugLogShareReportContext(
                title: dungeonRunFloorText ?? mode.displayName,
                details: [
                    ("モード", mode.displayName),
                    ("階層", dungeonRunFloorText ?? "なし"),
                    ("塔ID", mode.dungeonMetadataSnapshot?.dungeonID ?? "なし"),
                    ("フロアIndex", mode.dungeonMetadataSnapshot?.runState.map { String($0.currentFloorIndex) } ?? "なし"),
                    ("移動スタイル", mode.dungeonMetadataSnapshot?.runState?.movementStyle.displayName ?? "なし"),
                    ("試練塔seed", mode.dungeonMetadataSnapshot?.runState?.rogueTowerSeed.map(String.init) ?? "なし"),
                    ("カードseed", mode.dungeonMetadataSnapshot?.runState?.cardVariationSeed.map(String.init) ?? "なし"),
                    ("HP", String(dungeonHP)),
                    ("現在階の手数", String(core.moveCount)),
                    ("累計手数", mode.dungeonMetadataSnapshot?.runState.map { String($0.totalMoveCountIncludingCurrentFloor(core.moveCount)) } ?? String(core.moveCount)),
                    ("経過秒", mode.dungeonMetadataSnapshot?.runState.map { String($0.totalElapsedSecondsIncludingCurrentFloor(core.elapsedSeconds)) } ?? String(core.elapsedSeconds)),
                    ("残り手数", remainingDungeonTurns.map(String.init) ?? "なし"),
                    ("位置", DebugLogShareSupport.pointDescription(core.current)),
                    ("進行状態", String(describing: core.progress)),
                    ("手札上限", String(core.dungeonInventoryKindLimit)),
                    ("手札拡張確率段階", mode.dungeonMetadataSnapshot?.runState.map { String($0.rogueHandExpansionChanceStep) } ?? "なし"),
                    ("所持カード", DebugLogShareSupport.inventoryDescription(core.dungeonInventoryEntries)),
                    ("遺物", DebugLogShareSupport.relicDescription(core.dungeonRelicEntries)),
                    ("呪い", DebugLogShareSupport.curseDescription(core.dungeonCurseEntries)),
                    ("診断ログ保持", DebugLogHistory.shared.isFrontEndViewerEnabled ? "オン" : "オフ"),
                    ("選択中の手札", selectedHandStackDiagnosticDescription),
                    ("選択中の手札ID", selectedHandStackID?.uuidString ?? "なし"),
                    ("基本移動選択中", diagnosticBool(isBasicMoveCardSelected)),
                    ("拾得/宝箱選択待ち", pendingChoiceDiagnosticDescription),
                    ("選択オーバーレイ折りたたみ", diagnosticBool(isDungeonChoiceOverlayCollapsed)),
                    ("移動演出中", diagnosticBool(isMovementPresentationActive)),
                    ("移動演出一時停止", movementPresentationOverlayPauseDiagnosticDescription),
                    ("入力アニメーション", boardBridge.inputAnimationDiagnosticDescription),
                    ("盤面タップ警告", boardTapSelectionWarningDiagnosticDescription),
                    ("通常カード移動候補数", String(core.availableMoves().count)),
                    ("基本移動候補数", String(core.availableBasicOrthogonalMoves().count)),
                    ("使用可能な補助カード数", String(usableSupportCardCount)),
                    ("pending choice", pendingChoiceDiagnosticDescription)
                ],
                sections: [
                    DebugLogShareReportContext.Section(
                        title: "ラン履歴",
                        lines: DebugLogShareSupport.runLogDescription(core.dungeonRunLogEntries)
                    )
                ],
                footerBlocks: reproductionBlock.map { [$0] } ?? []
            ),
            entries: playLogEntries,
            appVersion: DebugLogShareSupport.appVersionDescription,
            deviceDescription: DebugLogShareSupport.deviceDescription
        )
    }

    private var selectedHandStackDiagnosticDescription: String {
        guard let selectedHandStackID else { return "なし" }
        let selectedStack = displayedHandStacks.first { $0.id == selectedHandStackID }
            ?? core.handStacks.first { $0.id == selectedHandStackID }
        return selectedStack?.topCard?.displayName ?? "不明"
    }

    private var pendingChoiceDiagnosticDescription: String {
        var descriptions: [String] = []
        if let choice = core.pendingDungeonPickupChoice {
            descriptions.append("拾得カード: \(choice.pickup.playable.displayName)")
        }
        if let choice = pendingDungeonRelicPickupChoice {
            descriptions.append("宝箱: \(choice.pickup.id)")
        }
        return descriptions.isEmpty ? "なし" : descriptions.joined(separator: ", ")
    }

    private var movementPresentationOverlayPauseDiagnosticDescription: String {
        guard let movementPresentationOverlayPause else { return "なし" }
        switch movementPresentationOverlayPause {
        case .cardPickupChoice:
            return "拾得カード選択"
        case .relicPickupChoice:
            return "宝箱選択"
        case .relicAcquisition:
            return "遺物取得表示"
        }
    }

    private var boardTapSelectionWarningDiagnosticDescription: String {
        guard let boardTapSelectionWarning else { return "なし" }
        let destination = DebugLogShareSupport.pointDescription(boardTapSelectionWarning.destination)
        return "\(boardTapSelectionWarning.message) @\(destination)"
    }

    private var usableSupportCardCount: Int {
        core.handStacks.filter { stack in
            guard stack.topCard?.supportCard != nil else { return false }
            return core.isSupportCardUsable(in: stack)
        }.count
    }

    private func makeReportIssueOpenedLogMessage() -> String {
        let currentPoint = DebugLogShareSupport.pointDescription(core.current)
        return [
            "[PLAY] event=report_issue_opened",
            "floor=\(mode.dungeonMetadataSnapshot?.runState?.floorNumber ?? 0)",
            "turn=\(core.moveCount)",
            "hp=\(dungeonHP)",
            "pos=\(currentPoint)",
            "progress=\(core.progress)",
            "moveCandidates=\(core.availableMoves().count)",
            "basicCandidates=\(core.availableBasicOrthogonalMoves().count)",
            "usableSupports=\(usableSupportCardCount)",
            "selected=\(selectedHandStackDiagnosticDescription)",
            "basicSelected=\(diagnosticBool(isBasicMoveCardSelected))",
            "pendingChoice=\(pendingChoiceDiagnosticDescription)",
            "movementActive=\(diagnosticBool(isMovementPresentationActive))",
            "movementPause=\(movementPresentationOverlayPauseDiagnosticDescription)",
            "inputAnimation=\"\(boardBridge.inputAnimationDiagnosticDescription)\"",
            "choiceCollapsed=\(diagnosticBool(isDungeonChoiceOverlayCollapsed))",
            "warning=\(boardTapSelectionWarning == nil ? "なし" : "あり")"
        ].joined(separator: " ")
    }

    private func diagnosticBool(_ value: Bool) -> String {
        value ? "はい" : "いいえ"
    }

    private func makeTesterReproductionBlock() -> String? {
        guard let snapshot = core.makeDungeonResumeSnapshot(),
              let encoded = TesterReproductionPayload(snapshot: snapshot).encodedString
        else { return nil }
        return """
        再現データ:
        \(encoded)
        """
    }
    /// 現在フロアのクリア後に選べる報酬カード
    var availableDungeonRewardMoveCards: [MoveCard] {
        availableDungeonRewardOffers.compactMap(\.move)
    }
    /// 現在フロアのクリア後に選べる報酬カードを、移動/補助/遺物を同じ枠として返す
    var availableDungeonRewardOffers: [DungeonRewardOffer] {
        guard !isResultFailed,
              let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID),
              dungeon.canAdvanceWithinRun(afterFloorIndex: runState.currentFloorIndex)
        else { return [] }
        let floor = dungeon.resolvedFloor(
            at: runState.currentFloorIndex,
            runState: runState
        )
        let nextFloor = dungeon.resolvedFloor(
            at: runState.currentFloorIndex + 1,
            runState: runState
        )
        let baseRewardCount = (floor?.rewardMoveCardsAfterClear.count ?? 0)
            + (floor?.rewardSupportCardsAfterClear.count ?? 0)
        let turnLimit = core.effectiveDungeonTurnLimit
        let isFastClearForRelic = turnLimit.map { $0 > 0 && core.moveCount * 2 <= $0 } ?? false
        let isSeventyPercentClear = turnLimit.map { $0 > 0 && core.moveCount * 10 <= $0 * 7 } ?? false
        let defeatedEnemyCount = core.currentFloorDefeatedEnemyCount
        let curseRewardChoicePenalty =
            (effectEnabledDungeonCurseEntries.contains { $0.curseID == .bottomlessPack } ? 1 : 0) +
            (effectEnabledDungeonCurseEntries.contains { $0.curseID == .ashHeart } ? 1 : 0)
        let rewardChoiceBonus = -curseRewardChoicePenalty
        let hasReducedRewardChoices = effectEnabledDungeonCurseEntries.contains {
            $0.curseID == .bottomlessPack || $0.curseID == .ashHeart
        }
        let minimumRewardCount = hasReducedRewardChoices ? 2 : 1
        let growthRewardChoiceCount = dungeonGrowthStore.maxRewardChoiceCount(for: dungeon)
        let adjustedRewardCount = max(baseRewardCount, growthRewardChoiceCount) + rewardChoiceBonus
        let rewardCount = baseRewardCount > 0
            ? min(max(adjustedRewardCount, minimumRewardCount), 4)
            : 0
        guard rewardCount > 0 else { return [] }
        if let clearedState = runState.clearedFloorState(for: runState.currentFloorIndex),
           !clearedState.rewardOffers.isEmpty {
            return clearedState.rewardOffers.filter { !clearedState.selectedRewardOffers.contains($0) }
        }

        let supportCategoryBonusPoints =
            (effectEnabledDungeonRelicEntries.contains { $0.relicID == .scoutCompass } && isSeventyPercentClear ? 5 : 0) +
            (effectEnabledDungeonRelicEntries.contains { $0.relicID == .slayerPouch } ? defeatedEnemyCount * 3 : 0) +
            (effectEnabledDungeonRelicEntries.contains { $0.relicID == .trapperGloves && $0.remainingUses == 1 } ? 5 : 0) +
            (effectEnabledDungeonCurseEntries.contains { $0.curseID == .crackedCompass } ? 5 : 0) +
            (effectEnabledDungeonCurseEntries.contains { $0.curseID == .cloudedMirror } ? 5 : 0) +
            (effectEnabledDungeonCurseEntries.contains { $0.curseID == .patrolBell } ? 5 : 0) +
            (effectEnabledDungeonCurseEntries.contains { $0.curseID == .foolsMask } ? 5 : 0) +
            (effectEnabledDungeonCurseEntries.contains { $0.curseID == .laughingDoor } ? 5 : 0) +
            (effectEnabledDungeonCurseEntries.contains { $0.curseID == .upsideDownKey } && core.isDungeonExitUnlocked ? 5 : 0) +
            (effectEnabledDungeonCurseEntries.contains { $0.curseID == .taxCollector } ? 5 : 0) +
            (effectEnabledDungeonCurseEntries.contains { $0.curseID == .royalIou } ? 10 : 0) +
            (effectEnabledDungeonCurseEntries.contains { $0.curseID == .firewalkingTalisman } && core.didStepOnLavaThisFloor ? 10 : 0)
        let relicCategoryBonusPoints =
            (effectEnabledDungeonRelicEntries.contains { $0.relicID == .victoryBanner } ? 2 : 0) +
            (effectEnabledDungeonRelicEntries.contains { $0.relicID == .royalCrown } ? 2 : 0) +
            (effectEnabledDungeonRelicEntries.contains { $0.relicID == .hunterBanner } ? defeatedEnemyCount : 0) +
            (effectEnabledDungeonRelicEntries.contains { $0.relicID == .gamblerCoin } && isFastClearForRelic ? 2 : 0) +
            (effectEnabledDungeonCurseEntries.contains { $0.curseID == .relicHunterBrand } && isFastClearForRelic ? 5 : 0)
        let preferredRewardPlayables: Set<PlayableCard> = effectEnabledDungeonCurseEntries.contains { $0.curseID == .tinkersToolbox }
            ? Set(core.dungeonInventoryEntries.filter(\.hasUsesRemaining).map(\.playable))
            : []
        let tuning = DungeonRewardDrawTuning(
            clearMoveCount: core.moveCount,
            turnLimit: turnLimit,
            suppressRelicQualityBonus: effectEnabledDungeonCurseEntries.contains { $0.curseID == .cloudedMirror },
            supportCategoryBonusPoints: supportCategoryBonusPoints,
            relicCategoryBonusPoints: relicCategoryBonusPoints,
            preferredPlayables: preferredRewardPlayables,
            forcesRareOrBetterRelics: effectEnabledDungeonCurseEntries.contains { $0.curseID == .gildedSeal }
        )
        let ownedRelics = Set(core.dungeonRelicEntries.map(\.relicID))
        let baseOffers: [DungeonRewardOffer]
        if (dungeon.difficulty == .growth || dungeon.supportsInfiniteFloors),
           let seed = dungeon.supportsInfiniteFloors ? runState.rogueTowerSeed : runState.cardVariationSeed {
            let drawnOffers = DungeonWeightedRewardPools.drawUniqueOffers(
                from: DungeonWeightedRewardPools.entries(
                    floorIndex: runState.currentFloorIndex,
                    context: .clearReward,
                    movementStyle: runState.movementStyle,
                    countering: nextFloor
                ),
                context: .clearReward,
                count: rewardCount,
                seed: seed,
                floorIndex: runState.currentFloorIndex,
                salt: 0xA11D,
                tuning: tuning,
                excludingRelics: ownedRelics
            )
            let fallbackMoveCards = runState.movementStyle == .knight
                ? (floor?.rewardMoveCardsAfterClear ?? []).map(\.cardForKnightMovementStyle)
                : (floor?.rewardMoveCardsAfterClear ?? [])
            let fallbackOffers = fallbackMoveCards.map { DungeonRewardOffer.playable(.move($0)) }
                + ((floor?.rewardSupportCardsAfterClear ?? []).map { DungeonRewardOffer.playable(.support($0)) })
            baseOffers = drawnOffers + fallbackOffers.filter { !drawnOffers.contains($0) }.prefix(max(rewardCount - drawnOffers.count, 0))
        } else {
            baseOffers = ((floor?.rewardMoveCardsAfterClear ?? []).map { DungeonRewardOffer.playable(.move($0)) })
                + ((floor?.rewardSupportCardsAfterClear ?? []).map { DungeonRewardOffer.playable(.support($0)) })
        }
        let offers = dungeonGrowthStore.rewardOffers(
            for: baseOffers,
            dungeon: dungeon,
            floorIndex: runState.currentFloorIndex,
            seed: runState.cardVariationSeed,
            tuning: tuning,
            ownedRelics: ownedRelics,
            minimumChoiceCount: rewardCount,
            movementStyle: runState.movementStyle
        )
        let adjustedOffers = offersAddingWarpedHourglassSupportIfNeeded(
            to: offers,
            dungeon: dungeon,
            floorIndex: runState.currentFloorIndex,
            seed: runState.cardVariationSeed,
            tuning: tuning,
            ownedRelics: ownedRelics,
            rewardCount: rewardCount,
            movementStyle: runState.movementStyle,
            nextFloor: nextFloor
        )
        let offersWithHandExpansion = offersAddingRogueHandExpansionIfNeeded(
            to: adjustedOffers,
            dungeon: dungeon,
            runState: runState,
            rewardCount: rewardCount
        )
        return Array(offersWithHandExpansion.prefix(rewardCount))
    }

    private func offersAddingRogueHandExpansionIfNeeded(
        to offers: [DungeonRewardOffer],
        dungeon: DungeonDefinition,
        runState: DungeonRunState,
        rewardCount: Int
    ) -> [DungeonRewardOffer] {
        guard dungeon.difficulty == .roguelike,
              let seed = runState.rogueTowerSeed,
              runState.rogueHandExpansionSpawnSurface(floorIndex: runState.currentFloorIndex, seed: seed) == .clearReward,
              !offers.contains(.handExpansion),
              rewardCount > 0
        else { return offers }

        var result = Array(offers.prefix(rewardCount))
        if result.count >= rewardCount {
            if let replaceIndex = result.lastIndex(where: { $0.relic == nil }) {
                result.remove(at: replaceIndex)
            } else {
                result.removeLast()
            }
        }
        result.append(.handExpansion)
        return result
    }

    private func offersAddingWarpedHourglassSupportIfNeeded(
        to offers: [DungeonRewardOffer],
        dungeon: DungeonDefinition,
        floorIndex: Int,
        seed: UInt64?,
        tuning: DungeonRewardDrawTuning,
        ownedRelics: Set<DungeonRelicID>,
        rewardCount: Int,
        movementStyle: DungeonMovementStyle,
        nextFloor: DungeonFloorDefinition?
    ) -> [DungeonRewardOffer] {
        guard effectEnabledDungeonCurseEntries.contains(where: { $0.curseID == .warpedHourglass }),
              !offers.contains(where: { $0.support != nil }),
              rewardCount > 0
        else { return offers }

        let weightedSupportCandidate = DungeonWeightedRewardPools.drawUniqueOffers(
            from: DungeonWeightedRewardPools.entries(
                floorIndex: floorIndex,
                context: .clearReward,
                movementStyle: movementStyle,
                countering: nextFloor
            ),
            context: .clearReward,
            count: rewardCount,
            seed: seed ?? UInt64(floorIndex + 1),
            floorIndex: floorIndex,
            salt: 0x48A5,
            tuning: tuning,
            excludingPlayables: Set(offers.compactMap(\.playable)),
            excludingRelics: ownedRelics.union(offers.compactMap(\.relic))
        )
        .first { $0.support != nil }
        let fallbackSupportCandidate = [
            DungeonRewardOffer.playable(.support(.refillEmptySlots)),
            .playable(.support(.singleAnnihilationSpell)),
            .playable(.support(.annihilationSpell)),
            .playable(.support(.barrierSpell))
        ].first { !offers.contains($0) }
        guard let supportCandidate = weightedSupportCandidate ?? fallbackSupportCandidate else {
            return offers
        }

        var result = Array(offers.prefix(rewardCount))
        if result.count >= rewardCount {
            if let replaceIndex = result.lastIndex(where: { $0.relic == nil }) {
                result.remove(at: replaceIndex)
            } else {
                result.removeLast()
            }
        }
        result.append(supportCandidate)
        return result
    }

    /// 現在フロアのクリア後に選べる報酬カードを、移動/補助を同じ3択枠として返す
    var availableDungeonRewardCards: [PlayableCard] {
        availableDungeonRewardOffers.compactMap(\.playable)
    }
    /// 満杯時でも既存カードの重ね取りは許可し、新規種類だけを止める
    func canAddDungeonRewardMoveCard(_ card: MoveCard) -> Bool {
        canAddDungeonRewardPlayable(.move(card))
    }
    /// 現在フロアのクリア後に選べる補助報酬カード
    var availableDungeonRewardSupportCards: [SupportCard] {
        availableDungeonRewardOffers.compactMap(\.support)
    }

    /// 満杯時でも既存補助カードの重ね取りは許可し、新規種類だけを止める
    func canAddDungeonRewardSupportCard(_ support: SupportCard) -> Bool {
        canAddDungeonRewardPlayable(.support(support))
    }
    /// 拾得カードはクリア時に自動で次フロアへ持ち越すため、通常 UI では選択候補を出さない
    var carryoverCandidateDungeonPickupEntries: [DungeonInventoryEntry] {
        []
    }
    /// 新しく手札へ追加したカードに付与する使用回数
    var dungeonRewardAddUses: Int {
        guard let metadata = mode.dungeonMetadataSnapshot,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID)
        else { return 2 }
        return DungeonRunState.adjustedMoveRewardBaseUses(
            dungeonGrowthStore.rewardAddUses(for: dungeon),
            relicEntries: effectEnabledDungeonRelicEntries,
            curseEntries: effectEnabledDungeonCurseEntries
        )
    }

    var isCurrentDungeonClearWithinHalfTurnLimit: Bool {
        core.effectiveDungeonTurnLimit.map { $0 > 0 && core.moveCount <= $0 / 2 } ?? false
    }

    var dungeonRewardMoveUsesByCard: [MoveCard: Int] {
        Dictionary(uniqueKeysWithValues: availableDungeonRewardMoveCards.map { card in
            (
                card,
                DungeonRunState.adjustedRewardAddUses(
                    dungeonRewardAddUses,
                    for: card,
                    relicEntries: effectEnabledDungeonRelicEntries,
                    curseEntries: effectEnabledDungeonCurseEntries,
                    isExistingRewardCard: core.dungeonInventoryEntries.contains {
                        $0.moveCard == card && $0.hasUsesRemaining
                    }
                )
            )
        })
    }

    var baseDungeonSupportRewardAddUses: Int {
        DungeonRunState.adjustedSupportRewardUses(
            DungeonRunState.rewardUses(for: .refillEmptySlots),
            relicEntries: effectEnabledDungeonRelicEntries,
            curseEntries: effectEnabledDungeonCurseEntries
        )
    }

    var dungeonSupportRewardAddUses: Int {
        baseDungeonSupportRewardAddUses
    }
    /// クリア後に整理できる手札の報酬カード
    var adjustableDungeonRewardEntries: [DungeonInventoryEntry] {
        guard !isResultFailed,
              let metadata = mode.dungeonMetadataSnapshot,
              let runState = metadata.runState,
              let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID),
              dungeon.canAdvanceWithinRun(afterFloorIndex: runState.currentFloorIndex)
        else { return [] }
        return dungeonInventoryEntries.filter(\.hasUsesRemaining)
    }
    private func canAddDungeonRewardPlayable(_ playable: PlayableCard) -> Bool {
        let liveEntries = dungeonInventoryEntries.filter(\.hasUsesRemaining)
        if liveEntries.contains(where: { $0.playable == playable }) {
            return true
        }
        return liveEntries.count < core.dungeonInventoryKindLimit
    }
    /// 次のダンジョンフロア名
    var nextDungeonFloorTitle: String? {
        makeNextDungeonFloorMode()?.displayName
    }
    /// 現在のゲーム進行状態
    /// - Note: GameView 側でオーバーレイ表示を切り替える際に利用する
    var progress: GameProgress { core.progress }
    /// リザルト表示中の失敗状態
    var isResultFailed: Bool { core.progress == .failed }
    /// 失敗理由の短い表示文
    var failureReasonText: String? {
        guard core.progress == .failed else { return nil }
        if mode.usesDungeonExit {
            if core.dungeonHP <= 0 {
                if let turnLimit = core.effectiveDungeonTurnLimit, core.moveCount > turnLimit {
                    return "疲労でHPが0になりました"
                }
                return "HPが0になりました"
            }
        }
        return "攻略に失敗しました"
    }
    /// ペナルティバナー表示中かどうか
    /// - Note: SwiftUI 側の表示切り替えで利用するシンプルなフラグ
    var isShowingPenaltyBanner: Bool { activePenaltyBanner != nil }
    /// 捨て札選択待機中かどうか
    /// - Note: ボタンのスタイル切り替えに必要な状態をカプセル化する
    var isAwaitingManualDiscardSelection: Bool { core.isAwaitingManualDiscardSelection }
    var pendingDungeonPickupChoice: PendingDungeonPickupChoice? { core.pendingDungeonPickupChoice }
    var presentsBasicMoveCard: Bool {
        mode.usesDungeonExit && core.allowsCurrentBasicMove
    }
    var isBasicMoveCardSelected: Bool {
        isBasicMoveCardSelectionVisible
    }
    /// 現在の駒位置
    /// - Note: カード移動演出でフォールバック座標として参照する
    var currentPosition: GridPoint? { core.current }
    /// 将来の試練塔でスコア送信対象にするかどうか
    var isLeaderboardEligible: Bool { mode.isLeaderboardEligible }
    /// レイアウト診断用のスナップショット
    @Published var lastLoggedLayoutSnapshot: BoardLayoutSnapshot?
    /// 経過秒数を 1 秒刻みで更新するためのタイマーパブリッシャ
    let elapsedTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    /// ハプティクスの有効/無効設定
    var hapticsEnabled = true
    /// ガイドモードの有効/無効設定
    var guideModeEnabled = true
    /// Game Center 認証済みかどうかを UI と共有するフラグ
    @Published var isGameCenterAuthenticated: Bool
    /// 盤面タップ時にカード選択が必要なケースを利用者へ知らせるための警告状態
    /// - Important: `Identifiable` なペイロードを保持し、SwiftUI 側で `.alert(item:)` を使って監視できるようにする
    @Published var boardTapSelectionWarning: GameBoardTapSelectionWarning?
    /// 長押しで表示するカード/マスの一時説明
    @Published var activeInlineInspection: GameInlineInspection?
    /// 施錠階段の案内を同じ階で繰り返さないために記録する表示済みキー
    var displayedLockedExitReachNoticeKeys: Set<String> = []
    /// プレイヤーが確認できるラン履歴シートを表示しているかどうか
    @Published var isDungeonRunLogPresented = false
    /// GameCore から受け取ったラン履歴の表示用スナップショット
    @Published var dungeonRunLogEntries: [DungeonRunLogEntry] = []
    /// 被弾時の全画面フラッシュを SwiftUI 側へ伝えるための世代番号
    @Published var damageFeedbackGeneration = 0
    /// HP 低下演出の誤発火を避けるため、直近に観測したダンジョン HP を保持する
    var lastObservedDungeonHPForDamageEffect: Int?
    /// 敵ターン演出へ委譲した HP 低下イベントを重複再生しないために保持する
    var deferredEnemyDamageEventID: UUID?

    /// Combine の購読を保持するセット
    var cancellables = Set<AnyCancellable>()
    /// ひび割れ床落下後、次フロアへ移るまでの短い待機タスク
    var dungeonFallAdvanceTask: Task<Void, Never>?
    /// 現在時刻を取得するためのクロージャ。テストでは任意の値へ差し替える
    let currentDateProvider: () -> Date
    /// 手札選択と強制ハイライト制御を担当する内部状態
    var sessionState = GameSessionState()
    /// ペナルティバナー表示の責務を分離したヘルパー
    let penaltyBannerController: GamePenaltyBannerController
    /// タイマー停止理由を一元管理するヘルパー
    let pauseController: GamePauseController
    /// リザルト遷移とキャンペーン進捗更新を担当するヘルパー
    let flowCoordinator: GameFlowCoordinator
    /// 手札タップと盤面タップの入力フローを担当するヘルパー
    let inputFlowCoordinator: GameInputFlowCoordinator
    /// GameCore 購読と progress 起点の副作用を担当するヘルパー
    let coreBindingCoordinator: GameCoreBindingCoordinator
    /// タイトル復帰と新規プレイ開始時の後始末を担当するヘルパー
    let sessionResetCoordinator: GameSessionResetCoordinator
    /// 初期表示準備と設定同期を担当するヘルパー
    let appearanceSettingsCoordinator: GameAppearanceSettingsCoordinator
    /// Game Center / Ads の橋渡しを担当するヘルパー
    let sessionServicesCoordinator: GameSessionServicesCoordinator
    /// リザルト表示の内部状態
    var resultPresentationState = ResultPresentationState()
    /// セッション中の補助 UI 状態
    var sessionUIState = SessionUIState()
    /// チュートリアルイベント検出用の前回移動回数
    var lastTutorialMoveCount: Int = 0
    /// チュートリアルイベント検出用の前回進行状態
    var lastTutorialProgress: GameProgress = .playing

    /// ViewModel の初期化
    /// - Parameters:
    ///   - mode: 選択されたゲームモード
    ///   - gameInterfaces: GameCore を生成するためのファクトリ
    ///   - gameCenterService: スコア送信に利用するサービス
    ///   - adsService: 広告表示制御を担うサービス
    ///   - onRequestReturnToTitle: タイトルへ戻る際に呼び出すクロージャ
    init(
        mode: GameMode,
        gameInterfaces: GameModuleInterfaces,
        gameCenterService: GameCenterServiceProtocol,
        adsService: AdsServiceProtocol,
        dungeonGrowthStore: @MainActor @autoclosure () -> DungeonGrowthStore = DungeonGrowthStore(),
        dungeonRunResumeStore: @MainActor @autoclosure () -> DungeonRunResumeStore = DungeonRunResumeStore(),
        rogueTowerRecordStore: @MainActor @autoclosure () -> RogueTowerRecordStore = RogueTowerRecordStore(),
        tutorialTowerProgressStore: @MainActor @autoclosure () -> TutorialTowerProgressStore = TutorialTowerProgressStore(),
        encyclopediaDiscoveryStore: @MainActor @autoclosure () -> EncyclopediaDiscoveryStore = EncyclopediaDiscoveryStore(),
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)? = nil,
        onRequestReturnToTitle: (() -> Void)?,
        onRequestStartDungeonFloor: ((GameMode) -> Void)? = nil,
        penaltyBannerScheduler: PenaltyBannerScheduling = PenaltyBannerScheduler(),
        initialHandOrderingRawValue: String? = nil,
        initialGameCenterAuthenticationState: Bool = false,
        currentDateProvider: @escaping () -> Date = Date.init
    ) {
        self.mode = mode
        self.gameInterfaces = gameInterfaces
        self.gameCenterService = gameCenterService
        self.adsService = adsService
        self.dungeonGrowthStore = dungeonGrowthStore()
        self.dungeonRunResumeStore = dungeonRunResumeStore()
        self.rogueTowerRecordStore = rogueTowerRecordStore()
        self.tutorialTowerProgressStore = tutorialTowerProgressStore()
        self.encyclopediaDiscoveryStore = encyclopediaDiscoveryStore()
        self.onRequestGameCenterSignIn = onRequestGameCenterSignIn
        self.onRequestReturnToTitle = onRequestReturnToTitle
        self.onRequestStartDungeonFloor = onRequestStartDungeonFloor
        self.penaltyBannerController = GamePenaltyBannerController(scheduler: penaltyBannerScheduler)
        self.pauseController = GamePauseController()
        self.flowCoordinator = GameFlowCoordinator()
        self.inputFlowCoordinator = GameInputFlowCoordinator()
        self.coreBindingCoordinator = GameCoreBindingCoordinator()
        self.sessionResetCoordinator = GameSessionResetCoordinator()
        self.appearanceSettingsCoordinator = GameAppearanceSettingsCoordinator()
        self.sessionServicesCoordinator = GameSessionServicesCoordinator()
        self.isGameCenterAuthenticated = initialGameCenterAuthenticationState
        self.currentDateProvider = currentDateProvider

        // GameCore を生成し、ViewModel 経由で観測できるようにする
        let generatedCore = gameInterfaces.makeGameCore(mode)
        self.floorStartDungeonResumeSnapshot = mode.usesDungeonExit
            ? generatedCore.makeDungeonResumeSnapshot()
            : nil
        if let snapshot = self.dungeonRunResumeStore.snapshot,
           snapshot.dungeonID == mode.dungeonMetadataSnapshot?.dungeonID {
            let restored = generatedCore.restoreDungeonResumeSnapshot(snapshot)
            if !restored {
                self.dungeonRunResumeStore.clear()
            }
        }
        self.core = generatedCore
        self.dungeonRunLogEntries = generatedCore.dungeonRunLogEntries
        let initialDisplayedHandStacks = Self.visibleHandStacks(from: generatedCore.handStacks, mode: mode)
        self.displayedHandStacks = initialDisplayedHandStacks
        self.previousDisplayedHandStacksForAdditionEffect = initialDisplayedHandStacks
        self.boardBridge = GameBoardBridgeViewModel(core: generatedCore, mode: mode)
        self.boardBridge.onMovementPresentationStarted = { [weak self] resolution in
            self?.beginMovementPresentation(using: resolution)
        }
        self.boardBridge.onMovementPresentationStep = { [weak self] step in
            self?.applyMovementPresentationStep(step)
        }
        self.boardBridge.shouldPauseMovementPresentationAfterStep = { [weak self] _ in
            self?.movementPresentationOverlayPause != nil
        }
        self.boardBridge.onMovementPresentationFinished = { [weak self] in
            self?.finishMovementPresentation()
        }
        self.boardBridge.onEnemyTurnDamageResolved = { [weak self] event in
            self?.applyEnemyTurnDamagePresentation(event)
        }
        self.boardBridge.onEnemyTurnAnimationFinished = { [weak self] event in
            self?.finishEnemyTurnPresentation(event)
        }
        self.lastTutorialMoveCount = generatedCore.moveCount
        self.lastTutorialProgress = generatedCore.progress

        // GameCore の変更を ViewModel 経由で SwiftUI へ伝える
        generatedCore.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        // BoardBridge の描画更新も ViewModel 経由で伝播し、GameView 側が単一の監視対象で済むようにする
        boardBridge.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                self.objectWillChange.send()
            }
            .store(in: &cancellables)

        // GameCore が公開する各種状態を監視し、SwiftUI 側の責務を軽量化する
        bindGameCore()
        recordInitialEncyclopediaDiscoveries()
        generatedCore.resolvePendingDungeonFallLandingIfNeeded()

        // ユーザー設定から手札並び順を復元する
        if let rawValue = initialHandOrderingRawValue {
            restoreHandOrderingStrategy(from: rawValue)
        }
    }

    // MARK: - 手動操作ボタンのサポート

    /// 捨て札ボタンを操作可能かどうか判定する
    /// - Returns: 進行中かつ手札が 1 種類以上存在する場合に true
    var isManualDiscardButtonEnabled: Bool {
        sessionUIState.isManualDiscardButtonEnabled(
            progress: core.progress,
            handStacks: core.handStacks
        )
    }

    /// 捨て札ボタンに設定するアクセシビリティ説明文
    /// - Returns: 選択モード中かどうか、およびペナルティの有無に応じた説明テキスト
    var manualDiscardAccessibilityHint: String {
        sessionUIState.manualDiscardAccessibilityHint(
            penaltyCost: core.mode.manualDiscardPenaltyCost,
            isAwaitingManualDiscardSelection: core.isAwaitingManualDiscardSelection
        )
    }

    /// 捨て札モードの開始/終了をトグルする
    /// - Note: ボタンが無効な状態では開始せず、選択中であれば常に終了させる
    func toggleManualDiscardSelection() {
        clearSelectedCardSelection()
        if core.isAwaitingManualDiscardSelection {
            core.cancelManualDiscardSelection()
            return
        }

        guard isManualDiscardButtonEnabled else { return }
        core.beginManualDiscardSelection()
    }

    /// 手動ペナルティボタンを操作可能かどうか判定する
    /// - Returns: プレイ中であれば true
    var isManualPenaltyButtonEnabled: Bool {
        sessionUIState.isManualPenaltyButtonEnabled(progress: core.progress)
    }

    /// 手動ペナルティボタンのアクセシビリティ説明文
    /// - Returns: 手数消費量とスタック仕様を含めた説明テキスト
    var manualPenaltyAccessibilityHint: String {
        return sessionUIState.manualPenaltyAccessibilityHint(
            penaltyCost: core.mode.manualRedrawPenaltyCost,
            handSize: core.mode.handSize,
            stackingRuleDetailText: core.mode.stackingRuleDetailText
        )
    }

}

#if DEBUG || canImport(XCTest)
extension GameViewModel {
    /// テスト専用ラッパー: プライベートな進行状態ハンドラを直接呼び出し、リザルト挙動を検証する
    func handleProgressChangeForTesting(_ progress: GameProgress) {
        handleProgressChange(progress)
    }

    /// テスト専用にポーズメニュー表示状態を直接切り替えるユーティリティ
    /// - Parameter isPresented: 新しい表示状態
    func setPauseMenuPresentedForTesting(_ isPresented: Bool) {
        isPauseMenuPresented = isPresented
    }
}

#endif

enum DebugLogShareSupport {
    static var appVersionDescription: String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (version, build) {
        case let (version?, build?):
            return "\(version) (\(build))"
        case let (version?, nil):
            return version
        case let (nil, build?):
            return "build \(build)"
        case (nil, nil):
            return "unknown"
        }
    }

    static var deviceDescription: String {
        let device = UIDevice.current
        return "\(device.model) / iOS \(device.systemVersion)"
    }

    static func pointDescription(_ point: GridPoint?) -> String {
        guard let point else { return "nil" }
        return "(\(point.x),\(point.y))"
    }

    static func inventoryDescription(_ entries: [DungeonInventoryEntry]) -> String {
        let liveEntries = entries.filter(\.hasUsesRemaining)
        guard !liveEntries.isEmpty else { return "なし" }
        return liveEntries.map { "\($0.playable.displayName):\($0.totalUses)" }.joined(separator: ", ")
    }

    static func relicDescription(_ entries: [DungeonRelicEntry]) -> String {
        guard !entries.isEmpty else { return "なし" }
        return entries.map { "\($0.displayName):\($0.remainingUses)" }.joined(separator: ", ")
    }

    static func curseDescription(_ entries: [DungeonCurseEntry]) -> String {
        guard !entries.isEmpty else { return "なし" }
        return entries.map { "\($0.displayName):\($0.remainingUses)" }.joined(separator: ", ")
    }

    static func runLogDescription(_ entries: [DungeonRunLogEntry], limit: Int = 20) -> [String] {
        let recentEntries = entries.suffix(max(limit, 0))
        guard !recentEntries.isEmpty else { return ["ラン履歴はありません"] }
        return recentEntries.map { entry in
            "\(entry.headerText) [\(entry.kind.rawValue)] \(entry.message)"
        }
    }
}

struct TesterReproductionPayload: Codable, Equatable {
    static let version = 1
    static let prefix = "MONOKNIGHT_REPRO_SNAPSHOT_V1:"

    let version: Int
    let snapshot: DungeonRunResumeSnapshot

    init(version: Int = Self.version, snapshot: DungeonRunResumeSnapshot) {
        self.version = version
        self.snapshot = snapshot
    }

    var encodedString: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return Self.prefix + data.base64EncodedString()
    }

    static func decode(_ text: String) -> TesterReproductionPayload? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let encoded: String
        if trimmed.hasPrefix(prefix) {
            encoded = String(trimmed.dropFirst(prefix.count))
        } else if let prefixedLine = trimmed
            .components(separatedBy: .newlines)
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.hasPrefix(prefix) }) {
            encoded = String(prefixedLine.dropFirst(prefix.count))
        } else {
            return nil
        }

        guard let data = Data(base64Encoded: encoded),
              let payload = try? JSONDecoder().decode(Self.self, from: data),
              payload.version == version,
              payload.snapshot.version == DungeonRunResumeSnapshot.currentVersion,
              payload.snapshot.runState.dungeonID == payload.snapshot.dungeonID,
              payload.snapshot.runState.currentFloorIndex == payload.snapshot.floorIndex
        else { return nil }
        return payload
    }
}
