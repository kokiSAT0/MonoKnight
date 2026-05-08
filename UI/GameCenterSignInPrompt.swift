import Foundation

/// Game Center へのサインインをユーザーへ促す際の理由を整理した列挙体
/// - Important: 画面間でメッセージ内容を共有するために `Identifiable` を分離した構造体と組み合わせて利用する
enum GameCenterSignInPromptReason {
    /// アプリ起動時の自動認証が失敗した場合に表示する
    case initialAuthenticationFailed
    /// 将来のスコア表示を要求したが未認証のため開けない場合に使用する
    case leaderboardRequestedWhileUnauthenticated
    /// スコア送信を試みたが未認証でスキップした際に利用する
    case scoreSubmissionSkipped
    /// 再試行でも認証に失敗したときに案内する
    case retryFailed

    /// ユーザーへ提示する本文メッセージ
    var message: String {
        switch self {
        case .initialAuthenticationFailed:
            return "Game Center へのサインインに失敗しました。通信環境を確認のうえ、再試行するか設定画面からサインインしてください。"
        case .leaderboardRequestedWhileUnauthenticated:
            return "スコア機能を表示するには Game Center 認証が必要です。設定画面から認証してから再度お試しください。"
        case .scoreSubmissionSkipped:
            return "Game Center 未認証のため、今回のスコア送信はスキップされました。設定画面から認証すると次回以降に利用できます。"
        case .retryFailed:
            return "Game Center へのサインインに再度失敗しました。しばらく時間を置くか、設定画面から改めてサインインをお試しください。"
        }
    }
}

/// サインイン促しダイアログの再表示を容易にするためのラッパー
/// - Note: 同じ理由であっても毎回固有の ID を発行し、SwiftUI の `.alert(item:)` で連続表示できるようにする
struct GameCenterSignInPrompt: Identifiable {
    /// アラート識別用の一意 ID
    let id = UUID()
    /// ユーザーへ提示する理由種別
    let reason: GameCenterSignInPromptReason
}
