import Foundation
#if canImport(UIKit)
import UIKit
#endif
import SharedSupport // ログユーティリティを利用するため追加

/// ペナルティトリガー別に案内文とデバッグ文言を提供するプライベート拡張
private extension PenaltyEvent.Trigger {
    /// デバッグログ向けの説明文
    var debugDescription: String {
        switch self {
        case .automaticDeadlock:
            return "自動検出"
        case .manualRedraw:
            return "ユーザー操作"
        case .automaticFreeRedraw:
            return "連続手詰まり対応"
        }
    }

    /// VoiceOver で読み上げる案内文
    /// - Parameter penaltyAmount: 今回案内するペナルティ手数（直前の加算量も含む）
    func voiceOverMessage(penaltyAmount: Int) -> String {
        switch self {
        case .automaticDeadlock:
            // 手詰まり発生時は加算手数をそのまま案内し、VoiceOver 利用者へ状況を明確化する
            return "手詰まりのため手札スロットを引き直しました。手数は+\(penaltyAmount)です。"
        case .manualRedraw:
            // 手動ペナルティ利用時も加算量を具体的な数値で読み上げる
            return "ペナルティを使用して手札スロットを引き直しました。手数は+\(penaltyAmount)です。"
        case .automaticFreeRedraw:
            // 無料扱いの表現ではなく、直前に加算された手数を再確認できる文言へ統一する
            return "手詰まりが続いたため手札スロットを再度引き直しました。直前のペナルティは+\(penaltyAmount)です。"
        }
    }
}

/// ペナルティ判定や捨て札ペナルティの処理、VoiceOver 通知など UI 連動が強い処理を切り出した拡張
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
extension GameCore {
    /// UI 側から手動でペナルティを支払い、手札スロットを引き直すための公開メソッド
    /// - Note: 既にゲームが終了している場合や、ペナルティ中は何もしない
    public func applyManualPenaltyRedraw() {
        // クリア済み・ペナルティ処理中は無視し、進行中のみ受け付ける
        guard progress == .playing || progress == .awaitingSpawn else { return }

        // デバッグログ: ユーザー操作による引き直しを記録
        debugLog("ユーザー操作でペナルティ引き直しを実行")

        // 捨て札選択モードが残っていればここで解除しておく
        cancelManualDiscardSelection()

        // 共通処理を用いて手札を入れ替える
        applyPenaltyRedraw(
            trigger: .manualRedraw,
            penaltyAmount: mode.manualRedrawPenaltyCost,
            shouldAddPenalty: true
        )

        // 引き直し後も盤外カードしか無いケースをケアするため、直前の加算手数を引き継いで再判定する
        checkDeadlockAndApplyPenaltyIfNeeded(lastPaidPenaltyAmount: mode.manualRedrawPenaltyCost)
    }

    /// 手札スロットがすべて盤外となる場合にペナルティを課し、手札スロットを引き直す
    /// - Parameter lastPaidPenaltyAmount: 直前に支払ったペナルティ手数（未支払いなら `nil`）
    func checkDeadlockAndApplyPenaltyIfNeeded(lastPaidPenaltyAmount: Int? = nil) {
        // スポーン待機中は判定不要
        guard progress != .awaitingSpawn, let current = current else { return }

        // availableMoves() 内で primaryVector が評価されるため、将来の複数候補カードでも共通ロジックを維持できる
        let usableMoves = availableMoves(handStacks: handStacks, current: current)
        guard usableMoves.isEmpty else { return }

        if let lastPenaltyAmount = lastPaidPenaltyAmount {
            // デバッグログ: 連続手詰まりを通知し、追加ペナルティ無しで再抽選する
            debugLog("手詰まりが継続したため追加ペナルティ無しで自動引き直しを実施")

            // 共通処理を呼び出して手札・先読みを更新（追加ペナルティ無し）
            applyPenaltyRedraw(trigger: .automaticFreeRedraw, penaltyAmount: lastPenaltyAmount, shouldAddPenalty: false)

            // 引き直し後も詰みの場合があるので再チェック（同じ金額を引き継ぐ）
            checkDeadlockAndApplyPenaltyIfNeeded(lastPaidPenaltyAmount: lastPenaltyAmount)
            return
        } else {
            // デバッグログ: 手札詰まりの発生を通知
            debugLog("手札スロットが全て使用不可のためペナルティを適用")

            // 共通処理を呼び出して手札・先読みを更新
            applyPenaltyRedraw(
                trigger: .automaticDeadlock,
                penaltyAmount: mode.deadlockPenaltyCost,
                shouldAddPenalty: true
            )
            // 引き直し後も詰みの場合があるので再チェック（以降は直前の加算手数を引き継ぐ）
            checkDeadlockAndApplyPenaltyIfNeeded(lastPaidPenaltyAmount: mode.deadlockPenaltyCost)
        }
    }

    /// ペナルティ適用に伴う手札再構成・通知処理を一箇所へ集約する
    /// - Parameters:
    ///   - trigger: 自動検出か手動操作かを識別するフラグ
    ///   - penaltyAmount: 今回加算するペナルティ手数
    ///   - shouldAddPenalty: 追加ペナルティを課す必要があるかどうか
    private func applyPenaltyRedraw(trigger: PenaltyEvent.Trigger, penaltyAmount: Int, shouldAddPenalty: Bool) {
        // ペナルティ処理中は .deadlock 状態として UI 側の入力を抑制する
        updateProgressForPenaltyFlow(.deadlock)

        // 捨て札選択モードと同時には成立しないため、ここで解除する
        setManualDiscardSelectionState(false)

        // 手札が一新されるため、盤面タップからの保留リクエストも破棄して整合性を保つ
        resetBoardTapPlayRequestForPenalty()

        // ペナルティ加算。追加ペナルティが不要な場合や加算量 0 の場合はカウント維持
        if shouldAddPenalty && penaltyAmount > 0 {
            addPenaltyCount(penaltyAmount)
            debugLog("ペナルティ加算: +\(penaltyAmount)")
        }

        // 現在の手札・先読みカードはそのまま破棄し、新しいカードを引き直す
        handManager.clearAll()
        rebuildHandAndNext()

        // UI へ手詰まりの発生を知らせ、演出やフィードバックを促す
        publishPenaltyEvent(PenaltyEvent(penaltyAmount: penaltyAmount, trigger: trigger))

#if canImport(UIKit)
        // VoiceOver 利用者向けにペナルティ内容をアナウンス
        UIAccessibility.post(notification: .announcement, argument: trigger.voiceOverMessage(penaltyAmount: penaltyAmount))
#endif

        // デバッグログ: 引き直し後の状態を詳細に記録
        debugLog("ペナルティ引き直しを実行（トリガー: \(trigger.debugDescription)）")
        let handDescription = handStacks.debugSummaryJoined(emptyPlaceholder: "なし")
        debugLog("引き直し後の手札: [\(handDescription)]")
        // デバッグ: 引き直し後の盤面を表示
#if DEBUG
        // デバッグ目的でのみ盤面を出力する
        board.debugDump(current: current)
#endif

        // 手札更新が完了したら適切な進行状態へ戻す
        if mode.requiresSpawnSelection && current == nil {
            updateProgressForPenaltyFlow(.awaitingSpawn)
        } else {
            updateProgressForPenaltyFlow(.playing)
        }
    }

    /// シャッフルマスを踏んだ際に、ペナルティを加算せず手札・NEXT をすべて引き直す共通処理
    func applyTileEffectHandRedraw() {
        // --- UI へ処理中であることを伝えるため、一時的に deadlock 状態へ遷移（入力抑止目的） ---
        updateProgressForPenaltyFlow(.deadlock)

        // --- 捨て札モードが残っていると不整合になるため、ここで必ず解除しておく ---
        cancelManualDiscardSelection()

        // --- 盤面タップ要求もリセットし、次の入力待ち状態と矛盾しないよう整理 ---
        resetBoardTapPlayRequestForPenalty()

        // --- 現在の手札・先読みを完全に破棄し、山札から新規に配り直す（ペナルティ加算は行わない） ---
        handManager.clearAll()
        rebuildHandAndNext()

        // --- VoiceOver 利用者へ効果適用を通知し、無料引き直しであることを案内 ---
#if canImport(UIKit)
        UIAccessibility.post(notification: .announcement, argument: "シャッフルマスの効果で手札を引き直しました。")
#endif

        // --- ログへ記録し、テストやデバッグ時に挙動を追いやすくする ---
        debugLog("シャッフルマス効果で手札とNEXTを全て再配布")

        // --- モードに応じた進行状態へ戻し、通常のプレイサイクルへ復帰 ---
        if mode.requiresSpawnSelection && current == nil {
            updateProgressForPenaltyFlow(.awaitingSpawn)
        } else {
            updateProgressForPenaltyFlow(.playing)
        }
    }

    /// 捨て札ペナルティの選択を開始する
    /// - Note: ゲーム進行中で手札が存在する場合のみ受付ける
    public func beginManualDiscardSelection() {
        // プレイ中以外は受け付けない
        guard progress == .playing else { return }
        // 手札が空の場合は選択しても意味がないため無視する
        guard !handStacks.isEmpty else { return }
        // 既に捨て札モードであれば再度有効化する必要はない
        guard !isAwaitingManualDiscardSelection else { return }

        setManualDiscardSelectionState(true)
        debugLog("捨て札ペナルティ選択モード開始")

#if canImport(UIKit)
        // VoiceOver へモード切替を知らせる
        let announcement: String
        if mode.manualDiscardPenaltyCost > 0 {
            announcement = "捨て札するカードを選んでください。手数が\(mode.manualDiscardPenaltyCost)増加します。"
        } else {
            announcement = "捨て札するカードを選んでください。手数は増加しません。"
        }
        UIAccessibility.post(notification: .announcement, argument: announcement)
#endif
    }

    /// 捨て札モードを明示的に終了する
    /// - Note: UI 側でキャンセル操作が行われた際などに利用する
    public func cancelManualDiscardSelection() {
        guard isAwaitingManualDiscardSelection else { return }
        setManualDiscardSelectionState(false)
        debugLog("捨て札ペナルティ選択モードをキャンセル")
    }

    /// 指定スタックを捨て札にし、ペナルティを加算して新しいカードを補充する
    /// - Parameter stackID: 捨て札対象のスタック識別子
    /// - Returns: 正常終了した場合は true
    @discardableResult
    public func discardHandStack(withID stackID: UUID) -> Bool {
        // プレイ中以外では捨て札を実行しない
        guard progress == .playing else { return false }
        // 捨て札モードでなければ誤操作とみなし拒否する
        guard isAwaitingManualDiscardSelection else { return false }
        // 指定 ID のスタックが存在するか確認
        guard let index = handStacks.firstIndex(where: { $0.id == stackID }) else { return false }

        let removedStack = handManager.removeStack(at: index)
        setManualDiscardSelectionState(false)
        resetBoardTapPlayRequestForPenalty()

        // ペナルティを加算し、統計値へ反映
        let penalty = mode.manualDiscardPenaltyCost
        if penalty > 0 {
            addPenaltyCount(penalty)
        }

        debugLog("捨て札ペナルティ適用: stackID=\(stackID), 枚数=\(removedStack.count), move=\(String(describing: removedStack.representativeMove)), ペナルティ=+\(penalty)")

#if canImport(UIKit)
        let message: String
        if penalty > 0 {
            message = "捨て札しました。手数が\(penalty)増加します。"
        } else {
            message = "捨て札しました。手数の増加はありません。"
        }
        UIAccessibility.post(notification: .announcement, argument: message)
#endif

        // NEXT キューを優先して補充し、不足分は山札から取得する（削除位置を維持する）
        rebuildHandAndNext(preferredInsertionIndices: [index])

        // 捨て札後の手札が再び詰む場合に備えてチェックする
        checkDeadlockAndApplyPenaltyIfNeeded()
        return true
    }

    /// 現在の残り踏破数を VoiceOver で通知する
    func announceRemainingTiles() {
#if canImport(UIKit)
        let remaining = board.remainingCount
        let message = "残り踏破数は\(remaining)です"
        UIAccessibility.post(notification: .announcement, argument: message)
#endif
    }
}
