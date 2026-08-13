import SwiftUI

enum AppThemeVisualStyle: String, CaseIterable, Identifiable {
    case classic
    case starChartSurveyTower

    var id: String { rawValue }
}

/// アプリ全体で共通利用する配色をまとめたテーマコンポーネント
/// DynamicProperty を採用することで、ダークモード切り替え時にも自動的に再評価される
struct AppTheme: DynamicProperty {
    /// SwiftUI 環境から取得するカラースキーム（ライト/ダーク）
    @Environment(\.colorScheme) private var environmentColorScheme

    /// SpriteKit など SwiftUI 環境外で利用する際に上書きするカラースキーム
    let overrideColorScheme: ColorScheme?
    /// 実験中の見た目を切り替えるためのビジュアルスタイル
    let visualStyle: AppThemeVisualStyle

    /// 標準イニシャライザでは SwiftUI の環境値を利用する
    init(visualStyle: AppThemeVisualStyle = .classic) {
        overrideColorScheme = nil
        self.visualStyle = visualStyle
    }

    /// SpriteKit 側から明示的にカラースキームを指定して利用するためのイニシャライザ
    /// - Parameter colorScheme: ライト/ダークのいずれか
    init(colorScheme: ColorScheme, visualStyle: AppThemeVisualStyle = .classic) {
        overrideColorScheme = colorScheme
        self.visualStyle = visualStyle
    }

    /// 実際に参照するカラースキーム。SpriteKit から利用する場合は override を優先する
    var resolvedColorScheme: ColorScheme {
        overrideColorScheme ?? environmentColorScheme
    }

    // MARK: - ベースカラー（Assets.xcassets から取得）

    /// 画面全体の背景色。ライトでは淡いグレー、ダークでは限りなく黒に近いトーンを採用
    var backgroundPrimary: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(
                light: Color(red: 0.91, green: 0.97, blue: 0.99),
                dark: Color(red: 0.025, green: 0.08, blue: 0.16)
            )
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.78, green: 0.82, blue: 0.92),
                dark: Color(red: 0.006, green: 0.010, blue: 0.030)
            )
        }
    }

    /// カードやモーダルなど一段高いレイヤー用の背景色
    var backgroundElevated: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(
                light: Color.white.opacity(0.92),
                dark: Color(red: 0.06, green: 0.18, blue: 0.29).opacity(0.96)
            )
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.86, green: 0.89, blue: 0.98),
                dark: Color(red: 0.030, green: 0.042, blue: 0.085)
            )
        }
    }

    /// 標準の文字色。本文や主要なラベルで利用する
    var textPrimary: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(
                light: Color(red: 0.04, green: 0.16, blue: 0.25),
                dark: Color(red: 0.91, green: 0.98, blue: 1.0)
            )
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.05, green: 0.07, blue: 0.14),
                dark: Color(red: 0.92, green: 0.96, blue: 1.0)
            )
        }
    }

    /// サブ情報用の文字色。キャプションや補足テキスト向け
    var textSecondary: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(
                light: Color(red: 0.24, green: 0.38, blue: 0.48),
                dark: Color(red: 0.66, green: 0.82, blue: 0.88)
            )
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.20, green: 0.28, blue: 0.48).opacity(0.84),
                dark: Color(red: 0.70, green: 0.78, blue: 0.94).opacity(0.88)
            )
        }
    }

    /// ボタンなど強調表示する要素の背景色
    var accentPrimary: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(
                light: Color(red: 0.03, green: 0.49, blue: 0.58),
                dark: Color(red: 0.32, green: 0.88, blue: 0.86)
            )
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.18, green: 0.48, blue: 0.78),
                dark: Color(red: 0.42, green: 0.90, blue: 1.0)
            )
        }
    }

    /// アクセント背景上で使用する文字色
    var accentOnPrimary: Color {
        switch visualStyle {
        case .classic:
            return schemeColor(
                light: Color.white,
                dark: Color(red: 0.02, green: 0.10, blue: 0.15)
            )
        case .starChartSurveyTower:
            return schemeColor(
                light: Color(red: 0.98, green: 0.94, blue: 0.82),
                dark: Color(red: 0.07, green: 0.045, blue: 0.020)
            )
        }
    }
}

extension AppTheme {
    /// ライト/ダークで切り替える色を簡潔に定義するヘルパー
    func schemeColor(light: Color, dark: Color) -> Color {
        switch resolvedColorScheme {
        case .dark:
            return dark
        default:
            return light
        }
    }
}
