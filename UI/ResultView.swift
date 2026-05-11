import Game  // GameMode.Identifier を扱うために追加
import SwiftUI
import UIKit  // ハプティクス用フレームワーク

/// ゲーム終了時の結果を表示するビュー
/// ポイントと内訳、ベスト記録、各種ボタンをまとめて配置する
@MainActor
struct ResultView: View {
    /// 今回のプレイで実際に移動した回数
    let moveCount: Int

    /// ペナルティで加算された手数
    let penaltyCount: Int
    /// 出口到達型ダンジョンのリザルトかどうか
    let usesDungeonExit: Bool
    /// 失敗リザルトかどうか
    let isFailed: Bool
    /// 失敗理由
    let failureReason: String?
    /// ダンジョン残 HP
    let dungeonHP: Int?
    /// ダンジョン残り手数
    let remainingDungeonTurns: Int?
    /// ダンジョンランの階層表示
    let dungeonRunFloorText: String?
    /// 試練塔のローカル最高到達表示
    let rogueTowerRecordText: String?
    /// ダンジョンランの累計移動手数
    let dungeonRunTotalMoveCount: Int?
    /// 次のダンジョンフロア名
    let nextDungeonFloorTitle: String?
    /// 再挑戦ボタンの表示名
    let retryButtonTitle: String
    /// 次階へ進む前に選べる報酬。移動/補助/遺物を合わせた表示上の候補。
    let dungeonRewardOffers: [DungeonRewardOffer]
    /// 次階へ進む前に選べる報酬カード。旧呼び出し互換用。
    let dungeonRewardCards: [PlayableCard]
    /// 次階へ進む前に選べる報酬カード
    let dungeonRewardMoveCards: [MoveCard]
    /// 次階へ進む前に選べる補助報酬カード
    let dungeonRewardSupportCards: [SupportCard]
    /// リザルト時点で残っている塔所持カード
    let dungeonInventoryEntries: [DungeonInventoryEntry]
    /// 拾得カード持ち越し候補。通常 UI では自動持ち越しのため空配列を渡す。
    let dungeonPickupCarryoverEntries: [DungeonInventoryEntry]
    /// 新しく手札へ追加したカードの使用回数
    let dungeonRewardAddUses: Int
    /// 報酬移動カードごとの実際の使用回数
    let dungeonRewardMoveUsesByCard: [MoveCard: Int]
    /// 新しく手札へ追加した補助カードの使用回数
    let dungeonSupportRewardAddUses: Int
    /// 塔クリアで得た永続成長ポイント
    let dungeonGrowthAward: DungeonGrowthAward?

    /// クリアまでに要した秒数
    let elapsedSeconds: Int

    /// 将来の試練塔スコア境界で利用するゲームモード識別子
    let modeIdentifier: GameMode.Identifier
    /// 表示用のモード名称
    let modeDisplayName: String
    /// 将来の試練塔スコア導線を表示するかどうか
    let showsLeaderboardButton: Bool
    /// Game Center 認証済みかどうか
    let isGameCenterAuthenticated: Bool
    /// ルートビューへ Game Center 再サインインを依頼するためのクロージャ
    let onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)?

    /// 次のダンジョンフロアへ直接移動するためのクロージャ
    let onSelectNextDungeonFloor: (() -> Void)?
    /// ダンジョン報酬カードを選んで次階へ進むためのクロージャ
    let onSelectDungeonRewardMoveCard: ((MoveCard) -> Void)?
    /// 手札満杯などで追加できないダンジョン報酬カード
    let disabledDungeonRewardMoveCards: Set<MoveCard>
    /// 手札満杯などで追加できないダンジョン補助報酬カード
    let disabledDungeonRewardSupportCards: Set<SupportCard>
    /// ダンジョン報酬を追加/強化などから選んで次階へ進むためのクロージャ
    let onSelectDungeonReward: ((DungeonRewardSelection) -> Void)?
    /// 手札のカードを報酬消費なしで整理するためのクロージャ
    let onRemoveDungeonRewardCard: ((MoveCard) -> Void)?
    /// 手札の補助カードを報酬消費なしで整理するためのクロージャ
    let onRemoveDungeonRewardSupportCard: ((SupportCard) -> Void)?
    /// 失敗時にリザルトを一時的に閉じて盤面を確認するためのクロージャ
    let onInspectFailedBoard: (() -> Void)?
    /// 再戦処理を外部から受け取るクロージャ
    let onRetry: () -> Void
    /// ホームへ戻る操作を外部へ依頼するクロージャ（未指定の場合はボタンを表示しない）
    let onReturnToTitle: (() -> Void)?

    /// Game Center 連携を扱うサービス（プロトコル型で受け取る）
    /// `init` 時にのみ代入し、以後は再代入しないがテスト用に差し替えられるよう `var` で定義
    private var gameCenterService: GameCenterServiceProtocol
    /// 広告表示を扱うサービス（プロトコル型で受け取る）
    /// 上記と同じく `init` で注入し、必要に応じてモックに差し替え可能にする
    private var adsService: AdsServiceProtocol

    /// サイズクラスを参照し、iPad でのフォームシート表示時に余白を調整する
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// 共通設定ストア
    @EnvironmentObject private var gameSettingsStore: GameSettingsStore

    /// リザルト表示に関する一時状態
    @State private var viewState = ResultViewState()

    /// デフォルト実装のサービスを安全に取得するためのコンビニエンスイニシャライザ
    /// - NOTE: Swift 6 で厳格化されたコンカレンシーモデルに対応するため、`@MainActor` 上でシングルトンへアクセスする
    init(
        moveCount: Int,
        penaltyCount: Int,
        usesDungeonExit: Bool = false,
        isFailed: Bool = false,
        failureReason: String? = nil,
        dungeonHP: Int? = nil,
        remainingDungeonTurns: Int? = nil,
        dungeonRunFloorText: String? = nil,
        rogueTowerRecordText: String? = nil,
        dungeonRunTotalMoveCount: Int? = nil,
        nextDungeonFloorTitle: String? = nil,
        retryButtonTitle: String = "リトライ",
        dungeonRewardOffers: [DungeonRewardOffer] = [],
        dungeonRewardCards: [PlayableCard] = [],
        dungeonRewardMoveCards: [MoveCard] = [],
        dungeonRewardSupportCards: [SupportCard] = [],
        dungeonInventoryEntries: [DungeonInventoryEntry] = [],
        dungeonPickupCarryoverEntries: [DungeonInventoryEntry] = [],
        dungeonRewardAddUses: Int = 2,
        dungeonRewardMoveUsesByCard: [MoveCard: Int] = [:],
        dungeonSupportRewardAddUses: Int = 1,
        dungeonGrowthAward: DungeonGrowthAward? = nil,
        elapsedSeconds: Int,
        modeIdentifier: GameMode.Identifier,
        modeDisplayName: String,
        showsLeaderboardButton: Bool = true,
        isGameCenterAuthenticated: Bool? = nil,
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)? = nil,
        onSelectNextDungeonFloor: (() -> Void)? = nil,
        onSelectDungeonRewardMoveCard: ((MoveCard) -> Void)? = nil,
        disabledDungeonRewardMoveCards: Set<MoveCard> = [],
        disabledDungeonRewardSupportCards: Set<SupportCard> = [],
        onSelectDungeonReward: ((DungeonRewardSelection) -> Void)? = nil,
        onRemoveDungeonRewardCard: ((MoveCard) -> Void)? = nil,
        onRemoveDungeonRewardSupportCard: ((SupportCard) -> Void)? = nil,
        onInspectFailedBoard: (() -> Void)? = nil,
        onRetry: @escaping () -> Void,
        onReturnToTitle: (() -> Void)? = nil
    ) {
        // 既定値はメインアクター上で解決し、Game Center サービスの状態を同期させる
        let resolvedIsAuthenticated = isGameCenterAuthenticated ?? GameCenterService.shared.isAuthenticated
        self.init(
            moveCount: moveCount,
            penaltyCount: penaltyCount,
            usesDungeonExit: usesDungeonExit,
            isFailed: isFailed,
            failureReason: failureReason,
            dungeonHP: dungeonHP,
            remainingDungeonTurns: remainingDungeonTurns,
            dungeonRunFloorText: dungeonRunFloorText,
            rogueTowerRecordText: rogueTowerRecordText,
            dungeonRunTotalMoveCount: dungeonRunTotalMoveCount,
            nextDungeonFloorTitle: nextDungeonFloorTitle,
            retryButtonTitle: retryButtonTitle,
            dungeonRewardOffers: dungeonRewardOffers,
            dungeonRewardCards: dungeonRewardCards,
            dungeonRewardMoveCards: dungeonRewardMoveCards,
            dungeonRewardSupportCards: dungeonRewardSupportCards,
            dungeonInventoryEntries: dungeonInventoryEntries,
            dungeonPickupCarryoverEntries: dungeonPickupCarryoverEntries,
            dungeonRewardAddUses: dungeonRewardAddUses,
            dungeonRewardMoveUsesByCard: dungeonRewardMoveUsesByCard,
            dungeonSupportRewardAddUses: dungeonSupportRewardAddUses,
            dungeonGrowthAward: dungeonGrowthAward,
            elapsedSeconds: elapsedSeconds,
            modeIdentifier: modeIdentifier,
            modeDisplayName: modeDisplayName,
            showsLeaderboardButton: showsLeaderboardButton,
            isGameCenterAuthenticated: resolvedIsAuthenticated,
            onRequestGameCenterSignIn: onRequestGameCenterSignIn,
            onSelectNextDungeonFloor: onSelectNextDungeonFloor,
            onSelectDungeonRewardMoveCard: onSelectDungeonRewardMoveCard,
            disabledDungeonRewardMoveCards: disabledDungeonRewardMoveCards,
            disabledDungeonRewardSupportCards: disabledDungeonRewardSupportCards,
            onSelectDungeonReward: onSelectDungeonReward,
            onRemoveDungeonRewardCard: onRemoveDungeonRewardCard,
            onRemoveDungeonRewardSupportCard: onRemoveDungeonRewardSupportCard,
            onInspectFailedBoard: onInspectFailedBoard,
            onRetry: onRetry,
            onReturnToTitle: onReturnToTitle,
            gameCenterService: GameCenterService.shared,
            adsService: AdsService.shared
        )
    }

    init(
        moveCount: Int,
        penaltyCount: Int,
        usesDungeonExit: Bool = false,
        isFailed: Bool = false,
        failureReason: String? = nil,
        dungeonHP: Int? = nil,
        remainingDungeonTurns: Int? = nil,
        dungeonRunFloorText: String? = nil,
        rogueTowerRecordText: String? = nil,
        dungeonRunTotalMoveCount: Int? = nil,
        nextDungeonFloorTitle: String? = nil,
        retryButtonTitle: String = "リトライ",
        dungeonRewardOffers: [DungeonRewardOffer] = [],
        dungeonRewardCards: [PlayableCard] = [],
        dungeonRewardMoveCards: [MoveCard] = [],
        dungeonRewardSupportCards: [SupportCard] = [],
        dungeonInventoryEntries: [DungeonInventoryEntry] = [],
        dungeonPickupCarryoverEntries: [DungeonInventoryEntry] = [],
        dungeonRewardAddUses: Int = 2,
        dungeonRewardMoveUsesByCard: [MoveCard: Int] = [:],
        dungeonSupportRewardAddUses: Int = 1,
        dungeonGrowthAward: DungeonGrowthAward? = nil,
        elapsedSeconds: Int,
        modeIdentifier: GameMode.Identifier,
        modeDisplayName: String,
        showsLeaderboardButton: Bool = true,
        isGameCenterAuthenticated: Bool? = nil,
        onRequestGameCenterSignIn: ((GameCenterSignInPromptReason) -> Void)? = nil,
        onSelectNextDungeonFloor: (() -> Void)? = nil,
        onSelectDungeonRewardMoveCard: ((MoveCard) -> Void)? = nil,
        disabledDungeonRewardMoveCards: Set<MoveCard> = [],
        disabledDungeonRewardSupportCards: Set<SupportCard> = [],
        onSelectDungeonReward: ((DungeonRewardSelection) -> Void)? = nil,
        onRemoveDungeonRewardCard: ((MoveCard) -> Void)? = nil,
        onRemoveDungeonRewardSupportCard: ((SupportCard) -> Void)? = nil,
        onInspectFailedBoard: (() -> Void)? = nil,
        onRetry: @escaping () -> Void,
        onReturnToTitle: (() -> Void)? = nil,

        gameCenterService: GameCenterServiceProtocol,
        adsService: AdsServiceProtocol

    ) {
        // `@MainActor` に隔離されたシングルトンへ安全にアクセスするため、
        // Swift 6 の規約に合わせてここで依存解決を行う。
        // テスト注入時にも同じコード経路を通せるよう、まずローカル定数に束縛してからプロパティへ代入する。
        let resolvedGameCenterService = gameCenterService
        let resolvedAdsService = adsService
        // 認証状態を一度ローカル定数にまとめ、ビュー内部で利用する値を統一する
        let resolvedIsAuthenticated = isGameCenterAuthenticated ?? resolvedGameCenterService.isAuthenticated

        self.moveCount = moveCount
        self.penaltyCount = penaltyCount
        self.usesDungeonExit = usesDungeonExit
        self.isFailed = isFailed
        self.failureReason = failureReason
        self.dungeonHP = dungeonHP
        self.remainingDungeonTurns = remainingDungeonTurns
        self.dungeonRunFloorText = dungeonRunFloorText
        self.rogueTowerRecordText = rogueTowerRecordText
        self.dungeonRunTotalMoveCount = dungeonRunTotalMoveCount
        self.nextDungeonFloorTitle = nextDungeonFloorTitle
        self.retryButtonTitle = retryButtonTitle
        self.dungeonRewardOffers = Self.resolvedDungeonRewardOffers(
            dungeonRewardOffers,
            cards: dungeonRewardCards,
            moveCards: dungeonRewardMoveCards,
            supportCards: dungeonRewardSupportCards
        )
        self.dungeonRewardCards = Self.resolvedDungeonRewardCards(
            dungeonRewardCards,
            moveCards: dungeonRewardMoveCards,
            supportCards: dungeonRewardSupportCards
        )
        self.dungeonRewardMoveCards = dungeonRewardMoveCards
        self.dungeonRewardSupportCards = dungeonRewardSupportCards
        self.dungeonInventoryEntries = dungeonInventoryEntries
        self.dungeonPickupCarryoverEntries = dungeonPickupCarryoverEntries
        self.dungeonRewardAddUses = max(dungeonRewardAddUses, 1)
        self.dungeonRewardMoveUsesByCard = dungeonRewardMoveUsesByCard
        self.dungeonSupportRewardAddUses = max(dungeonSupportRewardAddUses, 1)
        self.dungeonGrowthAward = dungeonGrowthAward
        self.elapsedSeconds = elapsedSeconds
        self.modeIdentifier = modeIdentifier
        self.modeDisplayName = modeDisplayName
        self.showsLeaderboardButton = showsLeaderboardButton
        self.isGameCenterAuthenticated = resolvedIsAuthenticated
        self.onRequestGameCenterSignIn = onRequestGameCenterSignIn
        self.onSelectNextDungeonFloor = onSelectNextDungeonFloor
        self.onSelectDungeonRewardMoveCard = onSelectDungeonRewardMoveCard
        self.disabledDungeonRewardMoveCards = disabledDungeonRewardMoveCards
        self.disabledDungeonRewardSupportCards = disabledDungeonRewardSupportCards
        self.onSelectDungeonReward = onSelectDungeonReward
        self.onRemoveDungeonRewardCard = onRemoveDungeonRewardCard
        self.onRemoveDungeonRewardSupportCard = onRemoveDungeonRewardSupportCard
        self.onInspectFailedBoard = onInspectFailedBoard
        self.onRetry = onRetry
        self.onReturnToTitle = onReturnToTitle
        self.gameCenterService = resolvedGameCenterService
        self.adsService = resolvedAdsService
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ResultSummarySection(presentation: summaryPresentation)

                if let dungeonGrowthAward {
                    DungeonGrowthAwardSection(award: dungeonGrowthAward)
                }

                ResultActionSection(
                    presentation: summaryPresentation,
                    modeIdentifier: modeIdentifier,
                    modeDisplayName: modeDisplayName,
                    nextDungeonFloorTitle: nextDungeonFloorTitle,
                    retryButtonTitle: retryButtonTitle,
                    dungeonRewardOffers: dungeonRewardOffers,
                    dungeonRewardCards: dungeonRewardCards,
                    dungeonRewardMoveCards: dungeonRewardMoveCards,
                    dungeonRewardSupportCards: dungeonRewardSupportCards,
                    dungeonRewardInventoryEntries: dungeonInventoryEntries,
                    dungeonPickupCarryoverEntries: dungeonPickupCarryoverEntries,
                    dungeonRewardAddUses: dungeonRewardAddUses,
                    dungeonRewardMoveUsesByCard: dungeonRewardMoveUsesByCard,
                    dungeonSupportRewardAddUses: dungeonSupportRewardAddUses,
                    disabledDungeonRewardMoveCards: disabledDungeonRewardMoveCards,
                    disabledDungeonRewardSupportCards: disabledDungeonRewardSupportCards,
                    showsLeaderboardButton: showsLeaderboardButton,
                    isGameCenterAuthenticated: isGameCenterAuthenticated,
                    onRequestGameCenterSignIn: onRequestGameCenterSignIn,
                    onSelectNextDungeonFloor: onSelectNextDungeonFloor,
                    onSelectDungeonRewardMoveCard: onSelectDungeonRewardMoveCard,
                    onSelectDungeonReward: onSelectDungeonReward,
                    onRemoveDungeonRewardCard: onRemoveDungeonRewardCard,
                    onRemoveDungeonRewardSupportCard: onRemoveDungeonRewardSupportCard,
                    onInspectFailedBoard: onInspectFailedBoard,
                    onRetry: onRetry,
                    onReturnToTitle: onReturnToTitle,
                    gameCenterService: gameCenterService,
                    hapticsEnabled: gameSettingsStore.hapticsEnabled
                )
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 32)
            .frame(maxWidth: contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
        }
        .onAppear {
            adsService.showInterstitialAfterGameClearIfNeeded()
            if showsLeaderboardButton {
                updateBest()
            }
        }
    }

    /// iPad 表示時の最大コンテンツ幅を制御し、中央寄せの見た目を整える
    private var contentMaxWidth: CGFloat? {
        horizontalSizeClass == .regular ? 520 : nil
    }

    /// 横方向のパディングをサイズクラスごとに最適化する
    private var horizontalPadding: CGFloat {
        horizontalSizeClass == .regular ? 32 : 20
    }

    private static func resolvedDungeonRewardCards(
        _ cards: [PlayableCard],
        moveCards: [MoveCard],
        supportCards: [SupportCard]
    ) -> [PlayableCard] {
        guard cards.isEmpty else { return cards }
        return Array((moveCards.map(PlayableCard.move) + supportCards.map(PlayableCard.support)).prefix(3))
    }

    private static func resolvedDungeonRewardOffers(
        _ offers: [DungeonRewardOffer],
        cards: [PlayableCard],
        moveCards: [MoveCard],
        supportCards: [SupportCard]
    ) -> [DungeonRewardOffer] {
        guard offers.isEmpty else { return offers }
        return resolvedDungeonRewardCards(cards, moveCards: moveCards, supportCards: supportCards)
            .map(DungeonRewardOffer.playable)
    }

    private var summaryPresentation: ResultSummaryPresentation {
        ResultSummaryPresentation(
            moveCount: moveCount,
            penaltyCount: penaltyCount,
            usesDungeonExit: usesDungeonExit,
            isFailed: isFailed,
            failureReason: failureReason,
            dungeonHP: dungeonHP,
            remainingDungeonTurns: remainingDungeonTurns,
            dungeonRunFloorText: dungeonRunFloorText,
            rogueTowerRecordText: rogueTowerRecordText,
            dungeonRunTotalMoveCount: dungeonRunTotalMoveCount,
            dungeonRewardMoveCards: dungeonRewardMoveCards,
            dungeonInventoryEntries: dungeonInventoryEntries,
            dungeonGrowthAward: dungeonGrowthAward,
            hasNextDungeonFloor: nextDungeonFloorTitle != nil,
            elapsedSeconds: elapsedSeconds
        )
    }

    /// ベスト記録を更新する
    private func updateBest() {
        viewState.isNewBest = false
    }
}

struct ResultView_Previews: PreviewProvider {
    static var previews: some View {
        ResultView(
            moveCount: 24,
            penaltyCount: 6,
            elapsedSeconds: 132,
            modeIdentifier: .dungeonFloor,
            modeDisplayName: "塔ダンジョン",
            onRetry: {},
            gameCenterService: GameCenterService.shared,
            adsService: AdsService.shared
        )
    }
}


#Preview {
    ResultView(
        moveCount: 24,
        penaltyCount: 6,
        elapsedSeconds: 132,
        modeIdentifier: .dungeonFloor,
        modeDisplayName: "塔ダンジョン",
        onRetry: {}
    )
}
