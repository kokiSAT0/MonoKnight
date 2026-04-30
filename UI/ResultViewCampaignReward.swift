import Game
import SwiftUI
import UIKit

struct CampaignRewardNavigationPresentation: Equatable {
    let title: String
    let message: String
    let buttonTitle: String?
    let stage: CampaignStage?

    init(nextCampaignStage: CampaignStage?) {
        if let nextCampaignStage {
            title = "次のステージ"
            message = "このまま順番に進んで、新しい要素に触れていきましょう。"
            buttonTitle = "次へ: \(nextCampaignStage.displayCode)"
            stage = nextCampaignStage
        } else {
            title = "キャンペーン完走"
            message = "全ステージをクリアしました。星3や記録更新に挑戦できます。"
            buttonTitle = nil
            stage = nil
        }
    }
}

struct CampaignRewardSummarySection: View {
    let record: CampaignStageClearRecord
    let nextCampaignStage: CampaignStage?
    let onSelectCampaignStage: ((CampaignStage) -> Void)?
    let hapticsEnabled: Bool

    private let presentation: CampaignRewardPresentation

    init(
        record: CampaignStageClearRecord,
        nextCampaignStage: CampaignStage?,
        onSelectCampaignStage: ((CampaignStage) -> Void)?,
        hapticsEnabled: Bool
    ) {
        self.record = record
        self.nextCampaignStage = nextCampaignStage
        self.onSelectCampaignStage = onSelectCampaignStage
        self.hapticsEnabled = hapticsEnabled
        self.presentation = CampaignRewardPresentation(record: record)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("キャンペーンリワード")
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("ステージ \(record.stage.displayCode) \(record.stage.title)")
                    .font(.headline)

                CampaignStarProgressView(record: record)

                Text("今回の獲得: \(record.evaluation.earnedStars) / 3")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if presentation.starGain > 0 {
                    Text("累計スターが\(presentation.starGain)個増えました！")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.yellow)
                        .accessibilityLabel("累計スターが\(presentation.starGain)個増えました")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(presentation.conditions, id: \.title) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.isAchieved ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(item.isAchieved ? .green : .secondary)
                            .font(.system(size: 20, weight: .semibold))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                            Text(item.description)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            navigationSection
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    @ViewBuilder
    private var navigationSection: some View {
        let navigation = CampaignRewardNavigationPresentation(nextCampaignStage: nextCampaignStage)
        VStack(alignment: .leading, spacing: 8) {
            Text(navigation.title)
                .font(.headline)

            Text(navigation.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let stage = navigation.stage, let buttonTitle = navigation.buttonTitle {
                let canNavigate = onSelectCampaignStage != nil
                Button {
                    if hapticsEnabled {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                    onSelectCampaignStage?(stage)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(buttonTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(stage.title)
                                .font(.footnote)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canNavigate)
            }
        }
    }
}

struct CampaignStarProgressView: View {
    let record: CampaignStageClearRecord

    @State private var animatedEarnedStars: Int
    @State private var bounceStates: [Bool] = Array(repeating: false, count: 3)
    @State private var animationTask: Task<Void, Never>?

    init(record: CampaignStageClearRecord) {
        self.record = record
        _animatedEarnedStars = State(initialValue: min(record.previousProgress.earnedStars, 3))
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Image(systemName: index < animatedEarnedStars ? "star.fill" : "star")
                    .foregroundColor(index < animatedEarnedStars ? .yellow : .secondary)
                    .scaleEffect(bounceStates[index] ? 1.24 : 1.0)
                    .shadow(color: index < animatedEarnedStars ? Color.yellow.opacity(0.4) : .clear,
                            radius: bounceStates[index] ? 6 : 0)
                    .animation(.easeOut(duration: 0.18), value: bounceStates[index])
                    .animation(.spring(response: 0.42, dampingFraction: 0.82), value: animatedEarnedStars)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("累計スター: \(record.progress.earnedStars) / 3")
        .onAppear { startAnimation() }
        .onChange(of: record.progress.earnedStars) { _, _ in
            startAnimation()
        }
        .onDisappear {
            animationTask?.cancel()
            animationTask = nil
        }
    }

    private func startAnimation() {
        animationTask?.cancel()
        animationTask = Task {
            await animateStarGain()
        }
    }

    private func animateStarGain() async {
        let baseline = baselineCount
        let target = targetCount

        await MainActor.run {
            animatedEarnedStars = baseline
            bounceStates = Array(repeating: false, count: 3)
        }

        guard target > baseline else {
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    animatedEarnedStars = target
                }
            }
            return
        }

        var current = baseline
        while current < target {
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 220_000_000)
            if Task.isCancelled { return }
            current += 1
            await MainActor.run {
                withAnimation(.spring(response: 0.44, dampingFraction: 0.74)) {
                    animatedEarnedStars = current
                    bounceStates[current - 1] = true
                }
            }
            if Task.isCancelled { return }
            try? await Task.sleep(nanoseconds: 180_000_000)
            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.18)) {
                    bounceStates[current - 1] = false
                }
            }
        }
    }

    private var baselineCount: Int {
        min(record.previousProgress.earnedStars, 3)
    }

    private var targetCount: Int {
        min(record.progress.earnedStars, 3)
    }
}
