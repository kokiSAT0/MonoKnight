#if !canImport(Combine)
import Foundation

/// Combine が利用できない Linux などの環境向けに最低限の型を定義する補助ファイル
/// - Note: SPM のテストを Linux で実行するケースを考慮し、`GameCore` などが `ObservableObject`
///   と `@Published` を安全に参照できるようシンプルな代替を提供する。
public protocol ObservableObject {}

/// Combine の `@Published` を簡易的に模倣するためのジェネリックラッパー
/// - Important: 実際の Combine のような購読機能は持たず、値の保持と初期化のみに対応する。
@propertyWrapper
public struct Published<Value> {
    /// ラップしている実際の値
    public var wrappedValue: Value

    /// 保持したい値で初期化する
    /// - Parameter wrappedValue: `Published` が管理する初期値
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
}
#endif
