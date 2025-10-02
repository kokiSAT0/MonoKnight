import SwiftUI

/// デイリーチャレンジ機能が未提供であることを案内するシンプルな仮画面
struct DailyChallengePlaceholderView: View {
    /// タイトル画面へ戻る処理を親から受け取る
    let onDismiss: () -> Void

    /// アクセシビリティ向けの配色や余白調整で利用するテーマ
    private let theme = AppTheme()

    var body: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 0)

            // 情報アイコンと案内テキストで現在準備中であることを明確に伝える
            VStack(spacing: 16) {
                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(theme.accentPrimary)
                    .accessibilityHidden(true)

                Text("デイリーチャレンジは現在準備中です")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(theme.textPrimary)

                Text("近日中に日替わりの特別ルールを公開できるよう調整しています。最新情報はアップデートノートでお知らせします。")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 0)

            // ホームへ戻る導線を明示し、VoiceOver でも意味が伝わるよう日本語でラベルを付与する
            Button {
                onDismiss()
            } label: {
                Text("ホームに戻る")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(theme.accentPrimary)
                    )
                    .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("ホームに戻るボタン。タップするとタイトルへ戻ります")
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundPrimary.ignoresSafeArea())
        .navigationTitle("デイリーチャレンジ")
        .navigationBarTitleDisplayMode(.inline)
        // VoiceOver で画面の目的が一言で伝わるようにトップレベルのラベルを設定
        .accessibilityElement(children: .contain)
        .accessibilityLabel("デイリーチャレンジは準備中です。近日公開予定です。ホームに戻るボタンがあります。")
    }
}

#Preview {
    DailyChallengePlaceholderView(onDismiss: {})
}
