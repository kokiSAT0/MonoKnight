//
//  MonoKnightAppTests.swift
//  MonoKnightAppTests
//
//  Created by koki sato on 2025/09/10.
//

import SwiftUI
import Testing
import Game
@testable import MonoKnightApp

// MARK: - テスト用スタブ定義
/// GameCenterServiceProtocol を差し替えるためのスタブ
/// - Note: 認証状態を任意に切り替えられるようにし、RootView 初期化時の状態注入を検証する
private final class StubGameCenterService: GameCenterServiceProtocol {
    /// テストで参照する認証フラグ
    var isAuthenticated: Bool
    /// 認証メソッドの呼び出し回数を記録しておき、必要に応じて挙動確認できるようにする
    private(set) var authenticateCallCount: Int = 0
    /// スコア送信ログを保持し、後続のユニットテスト追加にも流用できるようにする
    private(set) var submittedScores: [(score: Int, mode: GameMode.Identifier)] = []
    /// ランキング表示要求の履歴を取っておき、UI との連携テストに備える
    private(set) var requestedLeaderboards: [GameMode.Identifier] = []

    init(isAuthenticated: Bool) {
        self.isAuthenticated = isAuthenticated
    }

    func authenticateLocalPlayer(completion: ((Bool) -> Void)?) {
        authenticateCallCount += 1
        completion?(isAuthenticated)
    }

    func submitScore(_ score: Int, for modeIdentifier: GameMode.Identifier) {
        submittedScores.append((score, modeIdentifier))
    }

    func showLeaderboard(for modeIdentifier: GameMode.Identifier) {
        requestedLeaderboards.append(modeIdentifier)
    }
}

/// 広告サービスの挙動を固定化するためのスタブ
/// - Important: AdsServiceProtocol は @MainActor 指定のため、スタブ側も同様にアノテーションを付与する
@MainActor
private final class StubAdsService: AdsServiceProtocol {
    /// インタースティシャル表示要求の回数
    private(set) var showInterstitialCallCount: Int = 0
    /// プレイ開始フラグのリセットが何度呼ばれたか
    private(set) var resetPlayFlagCallCount: Int = 0
    /// 広告無効化メソッドの呼び出し回数
    private(set) var disableAdsCallCount: Int = 0
    /// トラッキング許可ダイアログ要求の回数
    private(set) var trackingAuthorizationRequestCount: Int = 0
    /// 同意フォーム表示のための判定更新回数
    private(set) var consentRequestCount: Int = 0
    /// プライバシーオプション更新の回数
    private(set) var consentRefreshCount: Int = 0

    func showInterstitial() {
        showInterstitialCallCount += 1
    }

    func resetPlayFlag() {
        resetPlayFlagCallCount += 1
    }

    func disableAds() {
        disableAdsCallCount += 1
    }

    func requestTrackingAuthorization() async {
        trackingAuthorizationRequestCount += 1
    }

    func requestConsentIfNeeded() async {
        consentRequestCount += 1
    }

    func refreshConsentStatus() async {
        consentRefreshCount += 1
    }
}

struct MonoKnightAppTests {

    /// RootView の初期状態が期待通りかつ依存サービスが適切に注入されるかのテスト
    /// - Note: UI の初期表示はゲームタイトルが前面に出ている想定のため、`isShowingTitleScreen` が true であることを検証する
    @MainActor
    @Test func rootView_initialState_reflectsInjectedServices() throws {
        // MARK: 前提準備
        // Game Center 側は認証済みシナリオを想定し、true を渡したスタブを生成
        let gameCenterStub = StubGameCenterService(isAuthenticated: true)
        // 広告サービスは特に状態を持たないが、依存注入が差し替えられることを確認するために専用スタブを用意
        let adsServiceStub = StubAdsService()

        // MARK: テスト対象の生成
        let view = RootView(gameCenterService: gameCenterStub, adsService: adsServiceStub)
        let mirror = Mirror(reflecting: view)

        // MARK: 依存サービスの保持を検証
        let mirroredGameCenter = mirror.children.first { $0.label == "gameCenterService" }?.value as? StubGameCenterService
        #expect(mirroredGameCenter === gameCenterStub)

        let mirroredAdsService = mirror.children.first { $0.label == "adsService" }?.value as? StubAdsService
        #expect(mirroredAdsService === adsServiceStub)

        // MARK: @State 初期値の検証（タイトル表示フラグ）
        let titleState = mirror.children.first { $0.label == "_isShowingTitleScreen" }?.value as? State<Bool>
        #expect(titleState != nil)
        if let titleState {
            #expect(titleState.wrappedValue == true)
        }

        // MARK: @State 初期値の検証（ローディング中フラグ）
        let preparingState = mirror.children.first { $0.label == "_isPreparingGame" }?.value as? State<Bool>
        #expect(preparingState != nil)
        if let preparingState {
            #expect(preparingState.wrappedValue == false)
        }

        // MARK: @State 初期値の検証（認証状態）
        let authState = mirror.children.first { $0.label == "_isAuthenticated" }?.value as? State<Bool>
        #expect(authState != nil)
        if let authState {
            #expect(authState.wrappedValue == true)
        }
    }

    /// 日替わりモード用リーダーボード ID のマッピングが期待通りかを検証する
    /// - Note: GameCenterService 側で xcconfig 差し替えを行う前提のため、仮 ID を固定で確認しておく
    @MainActor
    @Test func leaderboardIdentifier_dailyModes_haveExpectedTestIDs() throws {
        let service = GameCenterService.shared
        // 日替わり固定シード用リーダーボードの ID を確認
        #expect(service.leaderboardIdentifier(for: .dailyFixedChallenge) == "test_daily_fixed_v1")
        // 日替わりランダムシード用リーダーボードの ID を確認
        #expect(service.leaderboardIdentifier(for: .dailyRandomChallenge) == "test_daily_random_v1")
    }
}
