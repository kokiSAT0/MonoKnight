import Foundation
#if canImport(UIKit)
import UIKit
import SwiftUI
#endif

#if canImport(UIKit)
typealias HapticType = UINotificationFeedbackGenerator.FeedbackType
#else
/// UIKit が利用できない環境向けのダミー列挙
enum HapticType {
    case success, warning, error
}
#endif

/// ハプティクスの発生を一元管理するサービス
/// - NOTE: 設定のオン/オフを `@AppStorage` で保持する
final class HapticService {
    /// シングルトンインスタンス
    static let shared = HapticService()

    #if canImport(UIKit)
    /// ハプティクスのオン/オフ設定（UserDefaults と連携）
    @AppStorage("enable_haptics") private var enableHaptics: Bool = true
    #else
    /// 非 iOS 環境では単純なプロパティで代替
    private var enableHaptics: Bool = true
    #endif

    /// 外部からのインスタンス生成を禁止
    private init() {}

    /// 指定したタイプのハプティクスを再生
    /// - Parameter type: 成功/警告/エラーなどのハプティクスタイプ
    func notify(_ type: HapticType) {
        #if canImport(UIKit)
        // ユーザー設定がオンのときのみ実行
        guard enableHaptics else { return }
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(type)
        #else
        // 非 iOS 環境では何もしない
        #endif
    }
}

