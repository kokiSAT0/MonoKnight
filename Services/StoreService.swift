import Foundation
import StoreKit
import SwiftUI

/// StoreKit2 を用いた課金処理をまとめたサービス
/// `remove_ads` 商品の購入・復元・状態保持を担当する
@MainActor
final class StoreService: ObservableObject {
    /// シングルトンインスタンス
    static let shared = StoreService()

    /// 取得済みのプロダクト一覧（現在は広告除去のみ）
    @Published var products: [Product] = []

    /// 広告除去購入済みフラグ
    /// - `true` の場合は AdsService が広告を読み込まない
    @AppStorage("remove_ads") private var removeAds: Bool = false

    private init() {
        // 初期化と同時に商品情報の取得とトランザクション監視を開始
        Task {
            await fetchProducts()
            await updatePurchasedStatus()
            await observeTransactions()
        }
    }

    // MARK: - Product

    /// `remove_ads` 商品の情報を取得する
    func fetchProducts() async {
        do {
            // App Store Connect で登録した Product ID を指定
            products = try await Product.products(for: ["remove_ads"])
        } catch {
            // 失敗時はユーザーへは通知せず、デバッグログのみ詳細を出力
            debugError(error, message: "商品情報の取得に失敗")
        }
    }

    // MARK: - Purchase

    /// 広告除去を購入する
    func purchaseRemoveAds() async {
        // 事前に取得したプロダクトを検索
        guard let product = products.first(where: { $0.id == "remove_ads" }) else { return }

        do {
            // 購入フローを開始
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                // トランザクションの検証
                if let transaction = checkVerified(verification), transaction.productID == "remove_ads" {
                    // フラグ反映と広告停止
                    applyRemoveAds()
                    // 消費型ではないので明示的に finish
                    await transaction.finish()
                }
            default:
                // キャンセルや待機中の場合は特に何もしない
                break
            }
        } catch {
            // 購入フローで発生したエラーの詳細を出力
            debugError(error, message: "購入処理でエラー")
        }
    }

    /// 外部から呼び出して購入済み情報を更新する
    private func applyRemoveAds() {
        removeAds = true
        // 広告サービスに通知して表示を停止させる
        AdsService.shared.disableAds()
    }

    // MARK: - Transaction

    /// 購入済みトランザクションを確認しフラグを反映する
    private func updatePurchasedStatus() async {
        // 現在有効なトランザクションをすべてチェック
        for await result in Transaction.currentEntitlements {
            if let transaction = checkVerified(result), transaction.productID == "remove_ads" {
                applyRemoveAds()
            }
        }
    }

    /// トランザクション更新の監視を開始する
    private func observeTransactions() async {
        // 非同期シーケンスとして更新を受け取る
        for await result in Transaction.updates {
            if let transaction = checkVerified(result), transaction.productID == "remove_ads" {
                applyRemoveAds()
                await transaction.finish()
            }
        }
    }

    /// StoreKit2 の検証結果を確認する汎用メソッド
    private func checkVerified<T>(_ result: VerificationResult<T>) -> T? {
        switch result {
        case .unverified:
            // 署名が正しくない場合は無視
            return nil
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Restore

    /// 「購入を復元」ボタンなどから呼び出される処理
    /// App Store と同期して過去の購入を再評価する
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            // `AppStore.sync()` 実行後は `Transaction.updates` が再度流れるため
            // `updatePurchasedStatus()` を明示的に呼ぶ必要はない
        } catch {
            // 復元処理が失敗した場合も詳細なログを残す
            debugError(error, message: "購入の復元に失敗")
        }
    }
}
