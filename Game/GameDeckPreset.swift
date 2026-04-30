import Foundation

/// ゲームルール一式をまとめたモード設定
/// - Note: 盤サイズや山札構成、ペナルティ量などをまとめて扱うことで、新モード追加時の分岐を最小限に抑える。
/// 山札プリセットを識別し、UI からも扱いやすいように公開する列挙体
/// - Note: それぞれのケースは `Deck.Configuration` へ変換可能で、表示名や概要テキストも併せて提供する
public enum GameDeckPreset: String, CaseIterable, Codable, Identifiable {
    /// スタンダードモードと同じ山札構成
    /// - Note: 盤面 5×5 の基礎練習やランキング対象モードで共通採用するベースライン。
    case standard
    /// 長距離カードの出現頻度を抑えた標準構成
    /// - Note: 直線・斜め 2 マスを軽量化して初心者が局所移動へ慣れやすくする。
    case standardLight
    /// クラシカルチャレンジと同じ桂馬のみの構成
    /// - Note: ナイト系ジャンプだけで盤面踏破するため、騎士巡りの感覚を磨ける。
    case classicalChallenge
    /// 王将型カードのみの構成（序盤向け超短距離デッキ）
    /// - Note: 近接移動だけを扱い、移動候補の読み替え負荷を最小化する。
    case kingOnly
    /// キングと桂馬の基本 16 種を収録した構成
    /// - Note: 標準セットの短距離カードに限定し、中級者への橋渡しに使う。
    case kingAndKnightBasic
    /// キングと桂馬基礎デッキへ上下左右の選択キングカードを加えた構成
    /// - Note: 長距離カードを避けたまま縦横の判断力だけを拡張する初級者向け派生。
    case kingAndKnightWithOrthogonalChoices
    /// キングと桂馬基礎デッキへ斜め選択キングカードを加えた構成
    /// - Note: 角方向の処理を短距離カードのみで鍛えるための派生構成。
    case kingAndKnightWithDiagonalChoices
    /// キングと桂馬基礎デッキへ桂馬の選択カードを加えた構成
    /// - Note: 跳躍系の自由度を高めつつ長距離カードを含めない応用派生。
    case kingAndKnightWithKnightChoices
    /// キングと桂馬基礎デッキへ全選択カードを網羅した構成
    /// - Note: 短距離カードのみで構成したまま総合演習に挑める集大成デッキ。
    case kingAndKnightWithAllChoices
    /// キング 4 種と桂馬 4 種のみで構成した訓練向けデッキ
    /// - Note: 3×3 盤での導入に最適化し、操作量をさらに絞り込む。
    case kingPlusKnightOnly
    /// キング型カードに上下左右の選択肢を加えた構成
    /// - Note: 選択カードの初期学習として縦横 2 択の判断練習に活用する。
    case directionChoice
    /// レイ型カードを主体とした連続移動構成
    /// - Note: レイ型と補助キングを組み合わせ、長距離掃討を重点的に学ぶ。
    case directionalRayFocus
    /// 標準デッキに上下左右の選択キングを加えた構成
    /// - Note: 縦横選択を重み 2 で引きやすくし、標準カードとの切り替えを練習する。
    case standardWithOrthogonalChoices
    /// 標準デッキに斜め選択キングを加えた構成
    /// - Note: 角方向の補正を習得する中盤トレーニングとして利用する。
    case standardWithDiagonalChoices
    /// 標準デッキに桂馬の選択カードを加えた構成
    /// - Note: ナイト跳躍の柔軟性を高めるため、4 方向選択を重み 2 で供給する。
    case standardWithKnightChoices
    /// 標準デッキにすべての選択カードを加えた構成
    /// - Note: 選択カード 10 種を網羅し、複合判断の最終確認に位置付ける。
    case standardWithAllChoices
    /// 固定ワープカードを主役に据えた基礎練習デッキ
    /// - Note: 固定ワープを高頻度で引き込みつつ、近接移動でリカバリーできるようサポートカードも少量混在させる。
    case fixedWarpSpecialized
    /// 標準デッキに全域ワープを高重みで導入した構成
    /// - Note: 瞬間移動ルート構築を重点的に練習する上級者向けデッキ。
    case superWarpHighFrequency
    /// 標準デッキにワープカードを加えた構成
    /// - Note: 固定ワープと全域ワープをバランス良く混在させ、応用期の訓練に用いる。
    case standardWithWarpCards
    /// 目的地制カードの調整用に主要カード系統を混在させた実験構成
    /// - Note: 標準・選択・レイ・ワープカードをまとめて扱う。
    case targetLabAllIn
    /// 補助専用カードの挙動確認に使う実験構成
    /// - Note: NEXT更新・入替・導きを、基本移動カードと混ぜて確認する。
    case supportToolkit
    /// 複数マス移動カードを重視した拡張構成
    /// - Note: レイ型＋補助キングで盤面全域の掃討速度を高める目的。
    case extendedWithMultiStepMoves
    /// 上下左右の選択キングカードのみで構成した訓練デッキ
    /// - Note: 選択式の基本挙動を短時間で体験できる限定構成。
    case kingOrthogonalChoiceOnly
    /// 斜め方向の選択キングカードのみで構成した訓練デッキ
    /// - Note: 角移動の判断を集中的に磨く限定構成。
    case kingDiagonalChoiceOnly
    /// 桂馬の選択カードのみで構成した訓練デッキ
    /// - Note: 桂馬系の到達パターンを把握するための専用メニュー。
    case knightChoiceOnly
    /// すべての選択カードを混合した総合デッキ
    /// - Note: 選択カード全系統を均等重みで扱い、自由練習に向く構成。
    case allChoiceMixed

    /// `Identifiable` 準拠用の ID
    public var id: String { rawValue }

    /// UI で表示する名称
    public var displayName: String {
        switch self {
        case .standard:
            return "スタンダード構成"
        case .standardLight:
            return "スタンダード軽量構成"
        case .classicalChallenge:
            return "クラシカル構成"
        case .kingOnly:
            return "王将構成"
        case .kingAndKnightBasic:
            return "キング＋ナイト基礎構成"
        case .kingAndKnightWithOrthogonalChoices:
            return "キング＋ナイト＋縦横選択構成"
        case .kingAndKnightWithDiagonalChoices:
            return "キング＋ナイト＋斜め選択構成"
        case .kingAndKnightWithKnightChoices:
            return "キング＋ナイト＋桂馬選択構成"
        case .kingAndKnightWithAllChoices:
            return "キング＋ナイト＋全選択構成"
        case .kingPlusKnightOnly:
            return "キング＋ナイト限定構成"
        case .directionChoice:
            return "選択式キング構成"
        case .directionalRayFocus:
            return "連続移動カード構成"
        case .standardWithOrthogonalChoices:
            return "標準＋縦横選択キング構成"
        case .standardWithDiagonalChoices:
            return "標準＋斜め選択キング構成"
        case .standardWithKnightChoices:
            return "標準＋桂馬選択構成"
        case .standardWithAllChoices:
            return "標準＋全選択カード構成"
        case .fixedWarpSpecialized:
            return "固定ワープ基礎構成"
        case .superWarpHighFrequency:
            return "全域ワープ高頻度構成"
        case .standardWithWarpCards:
            return "標準＋ワープカード構成"
        case .targetLabAllIn:
            return "カード・特殊マス実験場構成"
        case .supportToolkit:
            return "補助カード実験構成"
        case .extendedWithMultiStepMoves:
            return "複数マス移動拡張構成"
        case .kingOrthogonalChoiceOnly:
            return "上下左右選択キング構成"
        case .kingDiagonalChoiceOnly:
            return "斜め選択キング構成"
        case .knightChoiceOnly:
            return "桂馬選択構成"
        case .allChoiceMixed:
            return "選択カード総合構成"
        }
    }

    /// 山札構成の概要テキスト
    public var summaryText: String {
        configuration.deckSummaryText
    }

    /// 実際に利用する `Deck.Configuration`
    var configuration: Deck.Configuration {
        switch self {
        case .standard:
            return .standard
        case .standardLight:
            return .standardLight
        case .classicalChallenge:
            return .classicalChallenge
        case .kingOnly:
            return .kingOnly
        case .kingAndKnightBasic:
            return .kingAndKnightBasic
        case .kingAndKnightWithOrthogonalChoices:
            return .kingAndKnightWithOrthogonalChoices
        case .kingAndKnightWithDiagonalChoices:
            return .kingAndKnightWithDiagonalChoices
        case .kingAndKnightWithKnightChoices:
            return .kingAndKnightWithKnightChoices
        case .kingAndKnightWithAllChoices:
            return .kingAndKnightWithAllChoices
        case .kingPlusKnightOnly:
            return .kingPlusKnightOnly
        case .directionChoice:
            return .directionChoice
        case .directionalRayFocus:
            return .directionalRayFocus
        case .standardWithOrthogonalChoices:
            return .standardWithOrthogonalChoices
        case .standardWithDiagonalChoices:
            return .standardWithDiagonalChoices
        case .standardWithKnightChoices:
            return .standardWithKnightChoices
        case .standardWithAllChoices:
            return .standardWithAllChoices
        case .fixedWarpSpecialized:
            return .fixedWarpSpecialized
        case .superWarpHighFrequency:
            return .superWarpHighFrequency
        case .standardWithWarpCards:
            return .standardWithWarpCards
        case .targetLabAllIn:
            return .targetLabAllIn
        case .supportToolkit:
            return .supportToolkit
        case .extendedWithMultiStepMoves:
            return .extendedWithMultiStepMoves
        case .kingOrthogonalChoiceOnly:
            return .kingOrthogonalChoiceOnly
        case .kingDiagonalChoiceOnly:
            return .kingDiagonalChoiceOnly
        case .knightChoiceOnly:
            return .knightChoiceOnly
        case .allChoiceMixed:
            return .allChoiceMixed
        }
    }

    /// 固定ワープカードを含めた構成を取得するヘルパー
    /// - Parameters:
    ///   - weight: 固定ワープカードへ割り当てたい重み（既定値は 1）
    ///   - summarySuffix: 山札概要テキストへ追記するサフィックス（nil の場合は変更しない）
    /// - Returns: 固定ワープカードを含む `Deck.Configuration`
    func configurationIncludingFixedWarpCard(weight: Int = 1, summarySuffix: String? = "＋固定ワープ") -> Deck.Configuration {
        configuration.addingFixedWarpCard(weight: weight, summarySuffix: summarySuffix)
    }
}
