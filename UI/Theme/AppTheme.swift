import SwiftUI

/// アプリ全体で共通利用する配色をまとめたテーマコンポーネント
/// DynamicProperty を採用することで、ダークモード切り替え時にも自動的に再評価される
struct AppTheme: DynamicProperty {
    /// SwiftUI 環境から取得するカラースキーム（ライト/ダーク）
    @Environment(\.colorScheme) private var environmentColorScheme

    /// SpriteKit など SwiftUI 環境外で利用する際に上書きするカラースキーム
    let overrideColorScheme: ColorScheme?

    /// 標準イニシャライザでは SwiftUI の環境値を利用する
    init() {
        overrideColorScheme = nil
    }

    /// SpriteKit 側から明示的にカラースキームを指定して利用するためのイニシャライザ
    /// - Parameter colorScheme: ライト/ダークのいずれか
    init(colorScheme: ColorScheme) {
        overrideColorScheme = colorScheme
    }

    /// 実際に参照するカラースキーム。SpriteKit から利用する場合は override を優先する
    var resolvedColorScheme: ColorScheme {
        overrideColorScheme ?? environmentColorScheme
    }

    // MARK: - ベースカラー（Assets.xcassets から取得）

    /// 画面全体の背景色。ライトでは淡いグレー、ダークでは限りなく黒に近いトーンを採用
    var backgroundPrimary: Color { Color("backgroundPrimary") }

    /// カードやモーダルなど一段高いレイヤー用の背景色
    var backgroundElevated: Color { Color("backgroundElevated") }

    /// 標準の文字色。本文や主要なラベルで利用する
    var textPrimary: Color { Color("textPrimary") }

    /// サブ情報用の文字色。キャプションや補足テキスト向け
    var textSecondary: Color { Color("textSecondary") }

    /// ボタンなど強調表示する要素の背景色
    var accentPrimary: Color { Color("accentPrimary") }

    /// アクセント背景上で使用する文字色
    var accentOnPrimary: Color { Color("accentOnPrimary") }
}
