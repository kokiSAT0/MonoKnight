import Game
import SwiftUI
import UIKit

/// 同意画面を含むアプリ全体で設定とライフサイクルを音へ反映する。
struct AppAudioModifier: ViewModifier {
    @ObservedObject var settings: GameSettingsStore
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear {
                configure()
                GameAudioService.shared.setSuspended(.scene, UIApplication.shared.applicationState != .active)
            }
            .onChange(of: scenePhase) { _, phase in
                GameAudioService.shared.setSuspended(.scene, phase != .active)
            }
            .onChange(of: settings.musicEnabled) { _, _ in configure() }
            .onChange(of: settings.soundEnabled) { _, _ in configure() }
            .onChange(of: settings.musicVolume) { _, _ in configure() }
            .onChange(of: settings.soundVolume) { _, _ in configure() }
    }

    private func configure() {
        GameAudioService.shared.configure(
            musicEnabled: settings.musicEnabled, soundEnabled: settings.soundEnabled,
            musicVolume: settings.musicVolume, soundVolume: settings.soundVolume
        )
    }
}

/// 表示に反映された変化を観測し、移動演出より先にダメージや結果音を鳴らさない。
struct GameAudioModifier: ViewModifier {
    @ObservedObject var viewModel: GameViewModel

    private var music: GameMusic {
        switch viewModel.mode.dungeonMetadataSnapshot?.dungeonID {
        case "tutorial-tower": .tutorial
        case "rogue-tower": .trial
        default: .growth
        }
    }

    func body(content: Content) -> some View {
        content
            .onAppear { updateMusic() }
            .onChange(of: viewModel.isPauseMenuPresented) { _, isPresented in
                GameAudioService.shared.setSuspended(.pauseMenu, isPresented)
            }
            .onChange(of: viewModel.showingResult) { _, showingResult in
                updateMusic()
                guard showingResult else { return }
                let sound: GameSound = viewModel.progress == .cleared
                    ? (viewModel.nextDungeonFloorTitle == nil ? .victory : .clear) : .defeat
                GameAudioService.shared.play(sound)
            }
            .onChange(of: viewModel.moveCount) { oldValue, newValue in
                guard newValue > oldValue else { return }
                GameAudioService.shared.resumeAfterUserAction()
                GameAudioService.shared.play(.move)
            }
            .onChange(of: viewModel.selectedHandStackID) { _, id in
                guard id != nil else { return }
                GameAudioService.shared.resumeAfterUserAction()
                GameAudioService.shared.play(.select)
            }
            .onChange(of: viewModel.damageFeedbackGeneration) { _, _ in
                GameAudioService.shared.play(.damage)
            }
            .onChange(of: viewModel.dungeonHP) { oldHP, newHP in
                if newHP > oldHP { GameAudioService.shared.play(.heal) }
            }
            .onChange(of: viewModel.recentlyAddedHandStackIDs) { _, ids in
                if !ids.isEmpty { GameAudioService.shared.play(.pickup) }
            }
            .onChange(of: viewModel.activeDungeonRelicAcquisitionPresentation?.id) { _, id in
                if id != nil { GameAudioService.shared.play(.relic) }
            }
            .onChange(of: viewModel.boardTapSelectionWarning) { _, warning in
                if warning != nil { GameAudioService.shared.play(.warning) }
            }
    }

    private func updateMusic() {
        GameAudioService.shared.setSuspended(.pauseMenu, viewModel.isPauseMenuPresented)
        GameAudioService.shared.playMusic(viewModel.showingResult ? nil : music)
    }
}
