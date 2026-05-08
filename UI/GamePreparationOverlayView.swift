import Game
import SwiftUI

struct GamePreparationOverlayPresentation: Equatable {
    let titleText: String
    let subtitleText: String?

    init(mode: GameMode) {
        if let metadata = mode.dungeonMetadataSnapshot,
           let runState = metadata.runState,
           let dungeon = DungeonLibrary.shared.dungeon(with: metadata.dungeonID) {
            titleText = "\(dungeon.title) \(runState.floorNumber)F"
            subtitleText = "Floor \(runState.floorNumber)"
        } else {
            titleText = mode.displayName
            subtitleText = nil
        }
    }
}

extension RootView {
    struct GamePreparationOverlayView: View {
        let mode: GameMode
        let isReady: Bool
        let onStart: () -> Void

        private var presentation: GamePreparationOverlayPresentation {
            GamePreparationOverlayPresentation(mode: mode)
        }

        var body: some View {
            ZStack {
                Color.black.opacity(0.72).ignoresSafeArea()

                VStack(spacing: 10) {
                    Text(presentation.titleText)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)

                    if let subtitleText = presentation.subtitleText {
                        Text(subtitleText)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(.white.opacity(0.68))
                            .textCase(.uppercase)
                    }
                }
                .padding(.horizontal, 28)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("game_preparation_overlay")
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isReady {
                    onStart()
                }
            }
            .transition(.opacity)
        }
    }
}
