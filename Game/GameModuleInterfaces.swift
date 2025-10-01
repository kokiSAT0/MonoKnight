import Foundation

/// Game モジュールが公開する代表的な依存関係を束ねる窓口
/// - Note: UI 側からはこの構造体を経由して `GameCore` を生成することで、将来的に別実装へ差し替えやすくする。
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public struct GameModuleInterfaces {
    /// `GameCore` を生成するためのファクトリクロージャ
    /// - Note: UI テストやプレビューでモックを差し込みたい場合に差し替えられるよう、外部から設定できるようにしている。
    public var makeGameCore: (_ mode: GameMode) -> GameCore

    /// デフォルト実装（本番利用を想定）
    /// - Parameter makeGameCore: `GameCore` を生成するクロージャ。省略時は `GameCore.init(mode:)` を利用する。
    @available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
    public init(makeGameCore: @escaping (_ mode: GameMode) -> GameCore = { GameCore(mode: $0) }) {
        self.makeGameCore = makeGameCore
    }

    /// ライブ環境向けのプリセット
    /// - Note: App 本体ではこの値を利用し、依存の置き換えを必要とする箇所は任意のインスタンスを注入する。
    public static let live = GameModuleInterfaces()
}
