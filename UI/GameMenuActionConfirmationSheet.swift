import SwiftUI

/// iPad などレギュラー幅で確認文をゆったり表示するためのシートビュー
/// - Note: `GameMenuAction` を扱う UI コンポーネントを独立させ、`GameView` の責務を削減する。
struct GameMenuActionConfirmationSheet: View {
    /// 共通配色を参照して背景色などを統一する
    private var theme = AppTheme()
    /// 現在確認中のアクション
    let action: GameMenuAction
    /// 確定時に GameView 側で処理を実行するクロージャ
    let onConfirm: (GameMenuAction) -> Void
    /// キャンセル時に状態をリセットするクロージャ
    let onCancel: () -> Void

    /// 明示的なイニシャライザを用意し、外部からも扱いやすいようにする
    /// - Parameters:
    ///   - action: 確認対象のメニューアクション
    ///   - onConfirm: 決定時に呼び出すクロージャ
    ///   - onCancel: キャンセル時に呼び出すクロージャ
    init(
        action: GameMenuAction,
        onConfirm: @escaping (GameMenuAction) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.action = action
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            // MARK: - 見出しと詳細説明
            VStack(alignment: .leading, spacing: 16) {
                Text("操作の確認")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(action.confirmationMessage)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    // iPad で視線移動が極端にならないように最大幅を確保しつつ左寄せで表示する
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(theme.textPrimary)
            }

            Spacer(minLength: 0)

            // MARK: - アクションボタン群
            HStack(spacing: 16) {
                Button("キャンセル", role: .cancel) {
                    // ユーザーが操作を取り消した場合はシートを閉じる
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button(action.confirmationButtonTitle, role: action.buttonRole) {
                    // GameView 側で用意した実処理を実行する
                    onConfirm(action)
                }
                .buttonStyle(.borderedProminent)
            }
            // ボタン行を右寄せにして重要ボタンへ視線を誘導する
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        // iPad では余白を広めに確保し、モーダル全体が中央にまとまるようにする
        .padding(32)
        .frame(maxWidth: 520, alignment: .leading)
        .background(theme.backgroundElevated)
    }
}
