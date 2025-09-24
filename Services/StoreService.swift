import Combine
import Foundation
import StoreKit
import SwiftUI
// Game モジュールに定義されたデータ型（GameMode.Identifier など）を利用するために読み込む
import Game
import SharedSupport // debugLog / debugError を利用するため追加

/// StoreKit2 を用いた課金処理をまとめたサービス
/// `remove_ads_mk` 商品の購入・復元・状態保持を担当する
@MainActor
final class StoreService: ObservableObject, StoreServiceProtocol {
    /// シングルトンインスタンス
    static let shared = StoreService()

    /// StoreKit で参照する Product ID を一元管理する内部定数
    private enum ProductID {
        static let removeAds = "remove_ads_mk"
    }

    /// 取得済みのプロダクト一覧（現在は広告除去のみ）
    /// - NOTE: 現状 1 種類のみだが、将来別商品の追加にも備えて配列として保持する。
    @Published private(set) var products: [Product] = []

    /// 広告除去購入済みフラグを UI へ公開するためのプロパティ
    /// - NOTE: `@AppStorage` だけだと SwiftUI の描画更新が走らないため、`@Published` と併用して View 側で購読しやすくする
    @Published private(set) var isRemoveAdsPurchased: Bool

    /// 価格表示用のテキスト。商品情報が未取得の間は `nil` のままにし、UI でローディング表示へ切り替える。
    @Published private(set) var removeAdsPriceText: String?

    /// 広告除去購入済みフラグ
    /// - `true` の場合は AdsService が広告を読み込まない
    @AppStorage(ProductID.removeAds) private var removeAdsMK: Bool = false

    /// 設定画面などから参照する広告除去商品のキャッシュ
    private var removeAdsProduct: Product? { products.first(where: { $0.id == ProductID.removeAds }) }

    private init() {
        // 起動時点で保存済みの値を読み出し、UI の初期状態に反映する
        self.isRemoveAdsPurchased = UserDefaults.standard.bool(forKey: ProductID.removeAds)
        self.removeAdsPriceText = nil

        if removeAdsMK {
            // すでに広告除去が有効な場合は AdsService にも通知しておき、広告ロードを完全に止める
            AdsService.shared.disableAds()
        }

        // 初期化と同時に商品情報の取得とトランザクション監視を開始
        Task {
            await refreshProducts()
            await updatePurchasedStatus()
            await observeTransactions()
        }
    }

    // MARK: - Product

    /// `remove_ads_mk` 商品の情報を取得する
    func refreshProducts() async {
        do {
            // App Store Connect で登録した Product ID を指定
            products = try await Product.products(for: [ProductID.removeAds])
            // 取得に成功した場合は表示用の価格テキストも更新する
            removeAdsPriceText = removeAdsProduct?.displayPrice
        } catch {
            // 失敗時はユーザーへは通知せず、デバッグログのみ詳細を出力
            debugError(error, message: "商品情報の取得に失敗")
            // エラー発生時は価格をリセットして、UI でローディングを継続表示させる
            removeAdsPriceText = nil
        }
    }

    // MARK: - Purchase

    /// 広告除去を購入する
    func purchaseRemoveAds() async {
        // 事前に取得したプロダクトを検索
        guard let product = removeAdsProduct else { return }

        do {
            // 購入フローを開始
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                // トランザクションの検証
                if let transaction = checkVerified(verification), transaction.productID == ProductID.removeAds {
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
        removeAdsMK = true
        isRemoveAdsPurchased = true
        // 広告サービスに通知して表示を停止させる
        AdsService.shared.disableAds()
    }

    // MARK: - Transaction

    /// 購入済みトランザクションを確認しフラグを反映する
    private func updatePurchasedStatus() async {
        // 現在有効なトランザクションをすべてチェック
        for await result in Transaction.currentEntitlements {
            if let transaction = checkVerified(result), transaction.productID == ProductID.removeAds {
                applyRemoveAds()
            }
        }
    }

    /// トランザクション更新の監視を開始する
    private func observeTransactions() async {
        // 非同期シーケンスとして更新を受け取る
        for await result in Transaction.updates {
            if let transaction = checkVerified(result), transaction.productID == ProductID.removeAds {
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
    func restorePurchases() async -> Bool {
        do {
            try await AppStore.sync()
            // `AppStore.sync()` 実行後は `Transaction.updates` が再度流れるため
            // `updatePurchasedStatus()` を明示的に呼ぶ必要はない
            return true
        } catch {
            // 復元処理が失敗した場合も詳細なログを残す
            debugError(error, message: "購入の復元に失敗")
            return false
        }
    }
}

// MARK: - タイプイレースされた Store サービス
@MainActor
final class AnyStoreService: ObservableObject, StoreServiceProtocol {
    /// 実際の Store サービス実装を保持する。
    private let base: any StoreServiceProtocol
    /// Combine 購読を保持し、ラップ対象の objectWillChange を監視するためのセット。
    private var cancellables: Set<AnyCancellable> = []

    /// 広告除去購入済みフラグを公開する。内部的にはラップ対象の値をそのまま反映する。
    @Published private(set) var isRemoveAdsPurchased: Bool
    /// 価格表示用のテキスト。ラップ対象の値が更新され次第このプロパティも追従する。
    @Published private(set) var removeAdsPriceText: String?

    /// - Parameter base: 実際の StoreService 実装（本番・モックのいずれにも対応）。
    init(base: any StoreServiceProtocol) {
        self.base = base
        self.isRemoveAdsPurchased = base.isRemoveAdsPurchased
        self.removeAdsPriceText = base.removeAdsPriceText

        // ラップ対象の objectWillChange を監視し、Published プロパティを同期する。
        base.objectWillChange
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.synchronizeFromBase()
                }
            }
            .store(in: &cancellables)
    }

    /// 商品情報の更新を実行し、完了後に Published プロパティへ反映する。
    func refreshProducts() async {
        await base.refreshProducts()
        await synchronizeAfterAsyncOperation()
    }

    /// 購入フローを実行し、結果を反映する。
    func purchaseRemoveAds() async {
        await base.purchaseRemoveAds()
        await synchronizeAfterAsyncOperation()
    }

    /// 復元処理を実行し、結果を反映する。
    func restorePurchases() async -> Bool {
        let result = await base.restorePurchases()
        await synchronizeAfterAsyncOperation()
        return result
    }

    /// objectWillChange 経由の通知で呼び出される同期処理。
    private func synchronizeFromBase() {
        isRemoveAdsPurchased = base.isRemoveAdsPurchased
        removeAdsPriceText = base.removeAdsPriceText
    }

    /// 非同期処理完了後にメインスレッドで同期を行うヘルパー。
    private func synchronizeAfterAsyncOperation() async {
        await MainActor.run { [weak self] in
            self?.synchronizeFromBase()
        }
    }
}
