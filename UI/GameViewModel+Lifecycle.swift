import Foundation
import Game
import SwiftUI

@MainActor
extension GameViewModel {
    func handlePauseMenuVisibilityChange(isPresented: Bool) {
        pauseController.handlePauseMenuVisibilityChange(
            isPresented: isPresented,
            supportsTimerPausing: supportsTimerPausing,
            progress: core.progress,
            pauseTimer: { [self] in
                core.pauseTimer(referenceDate: currentDateProvider())
            },
            resumeTimer: { [self] in
                core.resumeTimer(referenceDate: currentDateProvider())
            }
        )
    }

    func restoreHandOrderingStrategy(from rawValue: String) {
        appearanceSettingsCoordinator.restoreHandOrderingStrategy(from: rawValue, core: core)
    }

    func applyHandOrderingStrategy(rawValue: String) {
        appearanceSettingsCoordinator.applyHandOrderingStrategy(rawValue: rawValue, core: core)
    }

    func updateGameCenterAuthenticationStatus(_ newValue: Bool) {
        sessionServicesCoordinator.updateGameCenterAuthenticationStatus(
            currentValue: isGameCenterAuthenticated,
            newValue: newValue
        ) { [weak self] updatedValue in
            self?.isGameCenterAuthenticated = updatedValue
        }
    }

    func updateGuideMode(enabled: Bool) {
        appearanceSettingsCoordinator.updateGuideMode(
            enabled: enabled,
            boardBridge: boardBridge
        ) { [weak self] updatedValue in
            self?.guideModeEnabled = updatedValue
        }
    }

    func updateHapticsSetting(isEnabled: Bool) {
        appearanceSettingsCoordinator.updateHapticsSetting(
            isEnabled: isEnabled,
            boardBridge: boardBridge
        ) { [weak self] updatedValue in
            self?.hapticsEnabled = updatedValue
        }
    }

    func applyScenePalette(for scheme: ColorScheme) {
        boardBridge.applyScenePalette(for: scheme)
    }

    func refreshGuideHighlights(
        handOverride: [HandStack]? = nil,
        currentOverride: GridPoint? = nil,
        progressOverride: GameProgress? = nil
    ) {
        boardBridge.refreshGuideHighlights(
            handOverride: handOverride,
            currentOverride: currentOverride,
            progressOverride: progressOverride
        )
    }

    func updateDisplayedElapsedTime() {
        appearanceSettingsCoordinator.updateDisplayedElapsedTime(
            liveElapsedSeconds: core.liveElapsedSeconds
        ) { [weak self] seconds in
            self?.applySessionUIMutation { state in
                state.updateDisplayedElapsedTime(seconds)
            }
        }
    }

    func handleScenePhaseChange(_ newPhase: ScenePhase) {
        if newPhase == .inactive || newPhase == .background {
            saveCurrentDungeonResumeIfPossible()
        }
        pauseController.handleScenePhaseChange(
            newPhase,
            supportsTimerPausing: supportsTimerPausing,
            progress: core.progress,
            pauseTimer: { [self] in
                core.pauseTimer(referenceDate: currentDateProvider())
            },
            presentPauseMenu: { [self] in
                presentPauseMenu()
            }
        )
    }

    func handlePreparationOverlayChange(isVisible: Bool) {
        pauseController.handlePreparationOverlayChange(
            isVisible: isVisible,
            supportsTimerPausing: supportsTimerPausing,
            progress: core.progress,
            pauseTimer: { [self] in
                core.pauseTimer(referenceDate: currentDateProvider())
            },
            resumeTimer: { [self] in
                core.resumeTimer(referenceDate: currentDateProvider())
            },
            presentPauseMenu: { [self] in
                presentPauseMenu()
            }
        )
    }

    func prepareForAppear(
        colorScheme: ColorScheme,
        guideModeEnabled: Bool,
        hapticsEnabled: Bool,
        handOrderingStrategy: HandOrderingStrategy,
        isPreparationOverlayVisible: Bool
    ) {
        appearanceSettingsCoordinator.prepareForAppear(
            colorScheme: colorScheme,
            guideModeEnabled: guideModeEnabled,
            hapticsEnabled: hapticsEnabled,
            handOrderingStrategy: handOrderingStrategy,
            isPreparationOverlayVisible: isPreparationOverlayVisible,
            boardBridge: boardBridge,
            core: core,
            updateGuideMode: { [weak self] enabled in
                self?.updateGuideMode(enabled: enabled)
            },
            updateHapticsSetting: { [weak self] isEnabled in
                self?.updateHapticsSetting(isEnabled: isEnabled)
            },
            updateDisplayedElapsedTime: { [weak self] in
                self?.updateDisplayedElapsedTime()
            },
            handlePreparationOverlayChange: { [weak self] isVisible in
                self?.handlePreparationOverlayChange(isVisible: isVisible)
            }
        )
    }

    func updateBoardAnchor(_ anchor: Anchor<CGRect>?) {
        boardBridge.updateBoardAnchor(anchor)
    }

    func recordInitialEncyclopediaDiscoveries() {
        var ids: Set<EncyclopediaDiscoveryID> = [
            tileDiscoveryID("normal"),
            tileDiscoveryID("spawn"),
            tileDiscoveryID("dungeonExit")
        ]

        for stack in core.handStacks {
            if let playable = stack.topCard?.playable {
                ids.insert(playable.encyclopediaDiscoveryID)
            }
        }

        guard mode.usesDungeonExit else {
            encyclopediaDiscoveryStore.discover(ids)
            return
        }

        if !mode.impassableTilePoints.isEmpty {
            ids.insert(tileDiscoveryID("impassable"))
        }

        if !mode.warpTilePairs.isEmpty {
            ids.insert(tileDiscoveryID("warp"))
        }

        for effect in mode.tileEffectOverrides.values {
            ids.insert(tileDiscoveryID(for: effect))
        }

        if let rules = mode.dungeonRules {
            if rules.exitLock != nil {
                ids.insert(tileDiscoveryID("lockedDungeonExit"))
                ids.insert(tileDiscoveryID("dungeonKey"))
            }
            for enemy in rules.enemies {
                ids.insert(enemy.behavior.presentationKind.encyclopediaDiscoveryID)
                if enemy.behavior.presentationKind == .marker {
                    ids.insert(tileDiscoveryID("enemyWarning"))
                }
                ids.insert(tileDiscoveryID("enemyDanger"))
            }
            for hazard in rules.hazards {
                ids.formUnion(discoveryIDs(for: hazard))
            }
            for pickup in rules.cardPickups {
                ids.insert(tileDiscoveryID("cardPickup"))
                ids.insert(pickup.playable.encyclopediaDiscoveryID)
            }
            for pickup in rules.relicPickups {
                ids.insert(tileDiscoveryID("dungeonRelicPickup"))
                ids.insert(pickup.kind.encyclopediaEventKind.encyclopediaDiscoveryID)
            }
        }

        recordRelicAndCurseDiscoveries(into: &ids)
        encyclopediaDiscoveryStore.discover(ids)
    }

    func recordDisplayedHandDiscoveries(_ handStacks: [HandStack]) {
        encyclopediaDiscoveryStore.discover(
            handStacks.compactMap { $0.topCard?.playable.encyclopediaDiscoveryID }
        )
    }

    func recordRewardOfferDiscoveries() {
        var ids: Set<EncyclopediaDiscoveryID> = []
        for offer in availableDungeonRewardOffers {
            switch offer {
            case .playable(let playable):
                ids.insert(playable.encyclopediaDiscoveryID)
            case .relic(let relic):
                ids.insert(DungeonEventEncyclopediaKind.relicReward.encyclopediaDiscoveryID)
                ids.insert(relic.encyclopediaDiscoveryID)
            }
        }
        encyclopediaDiscoveryStore.discover(ids)
    }

    func recordRelicDiscoveries(_ entries: [DungeonRelicEntry]) {
        encyclopediaDiscoveryStore.discover(entries.map { $0.relicID.encyclopediaDiscoveryID })
    }

    func recordCurseDiscoveries(_ entries: [DungeonCurseEntry]) {
        var ids = entries.map { $0.curseID.encyclopediaDiscoveryID }
        if !entries.isEmpty {
            ids.append(DungeonEventEncyclopediaKind.curseOutcome.encyclopediaDiscoveryID)
        }
        encyclopediaDiscoveryStore.discover(ids)
    }

    private func recordRelicAndCurseDiscoveries(into ids: inout Set<EncyclopediaDiscoveryID>) {
        ids.formUnion(core.dungeonRelicEntries.map { $0.relicID.encyclopediaDiscoveryID })
        if !core.dungeonCurseEntries.isEmpty {
            ids.insert(DungeonEventEncyclopediaKind.curseOutcome.encyclopediaDiscoveryID)
        }
        ids.formUnion(core.dungeonCurseEntries.map { $0.curseID.encyclopediaDiscoveryID })
    }

    private func discoveryIDs(for hazard: HazardDefinition) -> Set<EncyclopediaDiscoveryID> {
        switch hazard {
        case .brittleFloor(let points, let initialState):
            let tileID = initialState == .hiddenWeak ? "hiddenWeakFloor" : "brittleFloor"
            return points.isEmpty ? [] : [
                tileDiscoveryID(tileID),
                DungeonEventEncyclopediaKind.floorFall.encyclopediaDiscoveryID
            ]
        case .damageTrap(let points, _):
            return points.isEmpty ? [] : [tileDiscoveryID("damageTrap")]
        case .lavaTile(let points, _):
            return points.isEmpty ? [] : [tileDiscoveryID("lavaTile")]
        case .healingTile(let points, _):
            return points.isEmpty ? [] : [tileDiscoveryID("healingTile")]
        }
    }

    private func tileDiscoveryID(for effect: TileEffect) -> EncyclopediaDiscoveryID {
        switch effect {
        case .warp:
            return tileDiscoveryID("warp")
        case .returnWarp:
            return tileDiscoveryID("returnWarp")
        case .shuffleHand:
            return tileDiscoveryID("shuffleHand")
        case .blast:
            return tileDiscoveryID("blast")
        case .slow:
            return tileDiscoveryID("paralysisTrap")
        case .shackleTrap:
            return tileDiscoveryID("shackleTrap")
        case .poisonTrap:
            return tileDiscoveryID("poisonTrap")
        case .illusionTrap:
            return tileDiscoveryID("illusionTrap")
        case .swamp:
            return tileDiscoveryID("swamp")
        case .preserveCard:
            return tileDiscoveryID("preserveCard")
        case .discardRandomHand:
            return tileDiscoveryID("discardRandomHandTrap")
        case .discardAllMoveCards:
            return tileDiscoveryID("discardAllMoveCardsTrap")
        case .discardAllSupportCards:
            return tileDiscoveryID("discardAllSupportCardsTrap")
        case .discardAllHands:
            return tileDiscoveryID("discardAllHandsTrap")
        }
    }

    private func tileDiscoveryID(_ id: String) -> EncyclopediaDiscoveryID {
        EncyclopediaDiscoveryID(category: .tile, itemID: id)
    }
}

private extension PlayableCard {
    var encyclopediaDiscoveryID: EncyclopediaDiscoveryID {
        switch self {
        case .move(let move):
            return move.encyclopediaDiscoveryID
        case .support(let support):
            return support.encyclopediaDiscoveryID
        }
    }
}
