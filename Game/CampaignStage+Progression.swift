import Foundation

public extension CampaignStage {
    /// ゲームプレイ用の `GameMode` を生成
    /// - Returns: ステージに対応するモード
    func makeGameMode() -> GameMode {
        GameMode(
            identifier: .campaignStage,
            displayName: "\(displayCode) \(title)",
            regulation: regulation,
            leaderboardEligible: false,
            campaignMetadata: .init(stageID: id)
        )
    }
}
