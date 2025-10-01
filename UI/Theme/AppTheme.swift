import SwiftUI
#if canImport(SpriteKit)
import SpriteKit
#endif
#if canImport(UIKit)
import UIKit
#endif

/// アプリ全体で共通利用する配色をまとめたテーマコンポーネント
/// DynamicProperty を採用することで、ダークモード切り替え時にも自動的に再評価される
struct AppTheme: DynamicProperty {
    /// SwiftUI 環境から取得するカラースキーム（ライト/ダーク）
    @Environment(\.colorScheme) private var environmentColorScheme

    /// SpriteKit など SwiftUI 環境外で利用する際に上書きするカラースキーム
    private var overrideColorScheme: ColorScheme?

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
    private var resolvedColorScheme: ColorScheme {
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

    // MARK: - バッジ／統計表示向けカラー

    /// 統計バッジの背景色。盤面上でも視認性を損なわない半透明トーン
    var statisticBadgeBackground: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.black.opacity(0.8)
        default:
            return Color.white.opacity(0.9)
        }
    }

    /// 統計バッジの枠線色。ライトでは黒系、ダークでは白系で薄く縁取る
    var statisticBadgeBorder: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.25)
        default:
            return Color.black.opacity(0.1)
        }
    }

    /// 統計バッジの補助ラベルに使う文字色
    var statisticTitleText: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.65)
        default:
            return Color.black.opacity(0.6)
        }
    }

    /// 統計バッジのメイン数値に使う文字色
    var statisticValueText: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white
        default:
            return Color.black
        }
    }

    // MARK: - カード表示向けカラー

    /// 手札カードの背景色。淡いトーンで盤面との差を演出
    var cardBackgroundHand: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.08)
        default:
            return Color.black.opacity(0.05)
        }
    }

    /// 先読みカードの背景色。手札よりわずかに明るくして注目度を上げる
    var cardBackgroundNext: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color.black.opacity(0.08)
        }
    }

    /// 手札カードの枠線色
    var cardBorderHand: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white
        default:
            return Color.black.opacity(0.85)
        }
    }

    /// 先読みカードの枠線色
    var cardBorderNext: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.8)
        default:
            return Color.black.opacity(0.9)
        }
    }

    /// 盤面中央セルのハイライト色（手札用）
    var centerHighlightHand: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color.black.opacity(0.08)
        }
    }

    /// 盤面中央セルのハイライト色（先読み用）
    var centerHighlightNext: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.25)
        default:
            return Color.black.opacity(0.12)
        }
    }

    /// グリッド線の色（手札用）
    var gridLineHand: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.4)
        default:
            return Color.black.opacity(0.3)
        }
    }

    /// グリッド線の色（先読み用）
    var gridLineNext: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.55)
        default:
            return Color.black.opacity(0.4)
        }
    }

    /// 矢印やラベルなどカード上の主要要素の色
    var cardContentPrimary: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white
        default:
            return Color.black
        }
    }

    /// カード上で白黒を反転して利用する際の色
    var cardContentInverted: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.black
        default:
            return Color.white
        }
    }

    /// 現在位置マーカーの縁取り色
    var startMarkerStroke: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.black.opacity(0.8)
        default:
            return Color.white.opacity(0.8)
        }
    }

    /// 目的地マーカーの縁取り色
    var destinationMarkerStroke: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white
        default:
            return Color.black
        }
    }

    // MARK: - プレースホルダ／メニュー等の付随 UI

    /// 手札が空の時に表示する枠線色
    var placeholderStroke: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.25)
        default:
            return Color.black.opacity(0.2)
        }
    }

    /// 手札プレースホルダの背景色
    var placeholderBackground: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.05)
        default:
            return Color.black.opacity(0.03)
        }
    }

    /// 手札プレースホルダのアイコン色
    var placeholderIcon: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.4)
        default:
            return Color.black.opacity(0.35)
        }
    }

    /// 右上メニューアイコンの前景色
    var menuIconForeground: Color { cardContentPrimary }

    /// 右上メニューアイコンの背景色
    var menuIconBackground: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.12)
        default:
            return Color.black.opacity(0.08)
        }
    }

    /// 右上メニューアイコンの枠線色
    var menuIconBorder: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.25)
        default:
            return Color.black.opacity(0.12)
        }
    }

    /// ダミー広告の背景色。実広告導入まで視認性を保つプレースホルダ用
    var adPlaceholderBackground: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.1)
        default:
            return Color.black.opacity(0.05)
        }
    }

    // MARK: - スポーン選択オーバーレイ

    /// スポーン案内の背景色。ライトモードでは白ベース、ダークモードでは黒ベースで適度に透過させる
    var spawnOverlayBackground: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.black.opacity(0.82)
        default:
            return Color.white.opacity(0.92)
        }
    }

    /// スポーン案内の枠線色。背景とのコントラストが強すぎないよう控えめな値に調整
    var spawnOverlayBorder: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.25)
        default:
            return Color.black.opacity(0.15)
        }
    }

    /// スポーン案内ボックスのドロップシャドウ色
    var spawnOverlayShadow: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.black.opacity(0.7)
        default:
            return Color.black.opacity(0.25)
        }
    }

    // MARK: - ペナルティバナー／先読みオーバーレイ

    /// ペナルティバナーの背景色
    var penaltyBannerBackground: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.18)
        default:
            return Color.black.opacity(0.08)
        }
    }

    /// ペナルティバナーの枠線色
    var penaltyBannerBorder: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.35)
        default:
            return Color.black.opacity(0.15)
        }
    }

    /// ペナルティバナーの影色
    var penaltyBannerShadow: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.black.opacity(0.35)
        default:
            return Color.black.opacity(0.12)
        }
    }

    /// ペナルティバナーのメインテキスト色
    var penaltyTextPrimary: Color { cardContentPrimary }

    /// ペナルティバナーの補足テキスト色
    var penaltyTextSecondary: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.8)
        default:
            return Color.black.opacity(0.7)
        }
    }

    /// ペナルティバナーのアイコン（シンボル）の色
    var penaltyIconForeground: Color { cardContentInverted }

    /// ペナルティバナーのアイコン背景色
    var penaltyIconBackground: Color { cardContentPrimary }

    /// NEXT バッジの文字色
    var nextBadgeText: Color { cardContentPrimary }

    /// NEXT バッジの背景色
    var nextBadgeBackground: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.18)
        default:
            return Color.black.opacity(0.08)
        }
    }

    /// NEXT バッジの枠線色
    var nextBadgeBorder: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.7)
        default:
            return Color.black.opacity(0.35)
        }
    }

    // MARK: - SpriteKit 盤面用カラー

    /// SpriteKit で描画する盤面の背景色
    var boardBackground: Color { backgroundPrimary }

    /// グリッド線の色（ライト/ダークでコントラストを調整）
    var boardGridLine: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.75)
        default:
            return Color.black.opacity(0.65)
        }
    }

    /// 踏破済みマスの塗り色（マルチ踏破マス完了時とトーンを揃える）
    var boardTileVisited: Color {
        switch resolvedColorScheme {
        case .dark:
            // ダークテーマではマルチ踏破の完了色と統一し、踏破完了時の色変化を明確にする
            return Color.white.opacity(0.28)
        default:
            // ライトテーマでも同じ思想で 18% の黒を重ね、踏破済みマスの濃いグレーを共通化する
            return Color.black.opacity(0.18)
        }
    }

    /// 未踏破マスの塗り色（基本は透明だが、若干のトーンを付けて盤面に奥行きを与える）
    var boardTileUnvisited: Color {
        switch resolvedColorScheme {
        case .dark:
            // 暗所でもマスの輪郭を把握しやすいよう、うっすらと光が当たった程度の 8% まで持ち上げる
            return Color.white.opacity(0.08)
        default:
            // まったくの透明だと盤面の境界が迷子になるため、わずかに灰色を乗せた 5% を採用する
            return Color.black.opacity(0.05)
        }
    }

    /// 複数回踏破マスの基準色（未踏破マスと同じトーンから段階演出をスタートさせる）
    var boardTileMultiBase: Color {
        // NOTE: マルチ踏破の進捗段階はオーバーレイで表現するため、ベース色は未踏破マスと同一にする
        //       これにより、踏破完了時に踏破済みカラーへ切り替わるコントラストが最大化される
        return boardTileUnvisited
    }

    /// 複数回踏破マス専用の枠線色（高コントラストのグレートーンを採用）
    var boardTileMultiStroke: Color {
        switch resolvedColorScheme {
        case .dark:
            // 暗所でも輪郭がはっきり残るよう、やや明度を高めたグレーを使用
            return Color.white.opacity(0.82)
        default:
            // ライトテーマではチャコール寄りの濃いグレーを用い、モノクロ基調を崩さず強調する
            return Color.black.opacity(0.78)
        }
    }

    /// トグルマスの塗り色（踏破状態に左右されない強調色）
    var boardTileToggle: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white.opacity(0.5)
        default:
            return Color.black.opacity(0.32)
        }
    }

    /// 駒本体の塗り色（背景に応じて反転させコントラストを維持）
    var boardKnight: Color {
        switch resolvedColorScheme {
        case .dark:
            return Color.white
        default:
            return Color.black
        }
    }

    /// ガイドモードで候補マスを照らす際の基準色
    /// - Note: HIG のコントラスト要件を満たしつつ盤面のモノトーンを邪魔しないよう、彩度を抑えたオレンジをテーマ別に用意する
    var boardGuideHighlight: Color {
        switch resolvedColorScheme {
        case .dark:
            // ダークテーマでは暗所で浮きすぎないよう、明度を上げたオレンジをベースに透過率を高めて輪郭をくっきりさせる
            let guideStrokeBase = Color(red: 1.0, green: 0.74, blue: 0.38)
            return guideStrokeBase.opacity(0.9)
        default:
            // ライトテーマでは背景が明るいので、彩度を抑えた濃いめのオレンジを採用し、透過で軽やかさを残す
            // NOTE: RGB(240, 104, 20) 相当の色味を透過 0.85 で用いることで、盤面に馴染みつつ視認性を確保する
            let guideStrokeBase = Color(red: 0.94, green: 0.41, blue: 0.08)
            return guideStrokeBase.opacity(0.85)
        }
    }

    #if canImport(UIKit)
    /// 指定したライト/ダークそれぞれの Color から動的 UIColor を生成するユーティリティ
    private func dynamicUIColor(light: Color, dark: Color) -> UIColor {
        let lightColor = UIColor(light)
        let darkColor = UIColor(dark)
        return UIColor { traitCollection in
            let interfaceStyle: UIUserInterfaceStyle
            if let overrideColorScheme {
                interfaceStyle = overrideColorScheme == .dark ? .dark : .light
            } else {
                interfaceStyle = traitCollection.userInterfaceStyle
            }
            switch interfaceStyle {
            case .dark:
                return darkColor
            default:
                return lightColor
            }
        }
    }

    /// カラースキームごとに AppTheme を生成して Color を取り出すヘルパー
    private func color(for scheme: ColorScheme, keyPath: KeyPath<AppTheme, Color>) -> Color {
        AppTheme(colorScheme: scheme)[keyPath: keyPath]
    }

    /// SpriteKit 盤面背景の UIColor 版
    var uiBoardBackground: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardBackground),
            dark: color(for: .dark, keyPath: \.boardBackground)
        )
    }

    /// SpriteKit グリッド線の UIColor 版
    var uiBoardGridLine: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardGridLine),
            dark: color(for: .dark, keyPath: \.boardGridLine)
        )
    }

    /// SpriteKit 踏破済みマスの UIColor 版
    var uiBoardTileVisited: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileVisited),
            dark: color(for: .dark, keyPath: \.boardTileVisited)
        )
    }

    /// SpriteKit 未踏破マスの UIColor 版
    var uiBoardTileUnvisited: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileUnvisited),
            dark: color(for: .dark, keyPath: \.boardTileUnvisited)
        )
    }

    /// SpriteKit 複数回踏破マス基準色の UIColor 版
    var uiBoardTileMultiBase: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileMultiBase),
            dark: color(for: .dark, keyPath: \.boardTileMultiBase)
        )
    }

    /// SpriteKit 複数回踏破マス枠線色の UIColor 版
    var uiBoardTileMultiStroke: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileMultiStroke),
            dark: color(for: .dark, keyPath: \.boardTileMultiStroke)
        )
    }

    /// SpriteKit トグルマス色の UIColor 版
    var uiBoardTileToggle: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardTileToggle),
            dark: color(for: .dark, keyPath: \.boardTileToggle)
        )
    }

    /// SpriteKit 駒の UIColor 版
    var uiBoardKnight: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardKnight),
            dark: color(for: .dark, keyPath: \.boardKnight)
        )
    }

    /// SpriteKit ガイドハイライトの UIColor 版
    var uiBoardGuideHighlight: UIColor {
        dynamicUIColor(
            light: color(for: .light, keyPath: \.boardGuideHighlight),
            dark: color(for: .dark, keyPath: \.boardGuideHighlight)
        )
    }
    #endif

    #if canImport(SpriteKit) && canImport(UIKit)
    /// SpriteKit の SKColor へ変換した盤面背景色
    var skBoardBackground: SKColor { SKColor(cgColor: uiBoardBackground.cgColor) }

    /// SpriteKit の SKColor へ変換したグリッド線色
    var skBoardGridLine: SKColor { SKColor(cgColor: uiBoardGridLine.cgColor) }

    /// SpriteKit の SKColor へ変換した踏破済みマス色
    var skBoardTileVisited: SKColor { SKColor(cgColor: uiBoardTileVisited.cgColor) }

    /// SpriteKit の SKColor へ変換した未踏破マス色
    var skBoardTileUnvisited: SKColor { SKColor(cgColor: uiBoardTileUnvisited.cgColor) }

    /// SpriteKit の SKColor へ変換した複数回踏破マス基準色
    var skBoardTileMultiBase: SKColor { SKColor(cgColor: uiBoardTileMultiBase.cgColor) }

    /// SpriteKit の SKColor へ変換した複数回踏破マス枠線色
    var skBoardTileMultiStroke: SKColor { SKColor(cgColor: uiBoardTileMultiStroke.cgColor) }

    /// SpriteKit の SKColor へ変換したトグルマス色
    var skBoardTileToggle: SKColor { SKColor(cgColor: uiBoardTileToggle.cgColor) }

    /// SpriteKit の SKColor へ変換した駒の塗り色
    var skBoardKnight: SKColor { SKColor(cgColor: uiBoardKnight.cgColor) }

    /// SpriteKit の SKColor へ変換したガイドハイライト色
    var skBoardGuideHighlight: SKColor { SKColor(cgColor: uiBoardGuideHighlight.cgColor) }
    #endif
}
