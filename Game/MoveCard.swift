import Foundation

/// 駒を移動させるカードの種類を定義する列挙型
/// - Note: 周囲 1 マスのキング型 8 種、ナイト型 8 種、距離 2 の直線/斜め 8 種の計 24 種に加え、キャンペーン専用の複数方向カードをサポート
/// - Note: SwiftUI モジュールからも扱うため `public` とし、全ケース配列も公開する
public enum MoveCard: CaseIterable {
    // MARK: - MovePattern 定義
    /// カードが持つ移動パターンを抽象化した構造体
    /// - Important: これまでは単純なベクトル配列のみで管理していたが、将来的な連続移動や絶対座標指定カードにも対応できるよう、
    ///              パターン種別と経路を合わせて扱えるメタデータへ整理する。
    public struct MovePattern {
        /// 識別用の内部ストレージ。
        /// - Note: 盤面生成時にユニークな移動パターンを数えたり、スタック管理で同一カードを検出する用途で利用する。
        private enum IdentityStorage: Hashable {
            case relativeSteps([MoveVector])
            case directionalRay(direction: MoveVector, limit: Int?)
            case absoluteTargets([GridPoint])
            case custom(String)
        }

        /// 外部公開用のアイデンティティ構造体
        /// - Note: `Hashable` へ準拠させることで Set や辞書のキーとして扱えるようにする。
        public struct Identity: Hashable {
            /// 内部表現
            private let storage: IdentityStorage

            /// プライベートイニシャライザでストレージを隠蔽し、用途に応じた生成メソッドのみ公開する
            /// - Parameter storage: 内部保持するストレージ値
            private init(storage: IdentityStorage) {
                self.storage = storage
            }

            /// 相対移動ベクトル列をもとにしたアイデンティティを生成する
            /// - Parameter vectors: 候補となる相対ベクトル配列
            /// - Returns: 同一ベクトル構成のカードを識別するための Identity
            public static func relativeSteps(_ vectors: [MoveVector]) -> Identity {
                Identity(storage: .relativeSteps(vectors))
            }

            /// 直線方向の連続移動を表すアイデンティティを生成する
            /// - Parameters:
            ///   - direction: 1 ステップ分の基準方向
            ///   - limit: 最大歩数（nil の場合は盤端まで）
            /// - Returns: 同一方向・同一上限を共有するカードを識別する Identity
            public static func directionalRay(direction: MoveVector, limit: Int?) -> Identity {
                Identity(storage: .directionalRay(direction: direction, limit: limit))
            }

            /// 絶対座標へジャンプするカード用のアイデンティティを生成する
            /// - Parameter targets: 目的地候補の座標配列
            /// - Returns: 同一座標集合へ移動するカードを識別する Identity
            public static func absoluteTargets(_ targets: [GridPoint]) -> Identity {
                Identity(storage: .absoluteTargets(targets))
            }

            /// 将来的にカスタム判定を導入したい場合に備えた生成メソッド
            /// - Parameter rawValue: 一意な文字列
            /// - Returns: 文字列ベースの Identity
            public static func custom(_ rawValue: String) -> Identity {
                Identity(storage: .custom(rawValue))
            }
        }

        /// 盤面判定に利用するコンテキスト
        /// - Note: `Board` 型へ直接依存しないようクロージャで判定を受け取り、テストや将来の盤面拡張へ対応する。
        public struct ResolutionContext {
            /// 盤面サイズ（デバッグ用にも参照しやすいよう保持）
            public let boardSize: Int
            /// 座標が盤内に含まれるかを判定するクロージャ
            private let containsHandler: (GridPoint) -> Bool
            /// 座標へ進入できるかを判定するクロージャ
            private let traversableHandler: (GridPoint) -> Bool

            /// イニシャライザ
            /// - Parameters:
            ///   - boardSize: 対象となる盤面サイズ
            ///   - contains: 盤内判定を行うクロージャ
            ///   - isTraversable: 障害物などで進入不可かどうかを判定するクロージャ
            public init(boardSize: Int, contains: @escaping (GridPoint) -> Bool, isTraversable: @escaping (GridPoint) -> Bool) {
                self.boardSize = boardSize
                self.containsHandler = contains
                self.traversableHandler = isTraversable
            }

            /// 指定座標が盤内かどうかを返す
            /// - Parameter point: 判定したい座標
            /// - Returns: 盤面に含まれていれば true
            public func contains(_ point: GridPoint) -> Bool {
                containsHandler(point)
            }

            /// 指定座標へ進入可能かを返す
            /// - Parameter point: 判定したい座標
            /// - Returns: 進入できる場合は true
            public func isTraversable(_ point: GridPoint) -> Bool {
                traversableHandler(point)
            }
        }

        /// 経路を表現する構造体
        /// - Important: 目的地だけでなく通過マスの列も保持し、連続移動カード追加時に衝突判定へ再利用できるようにする。
        public struct Path: Hashable {
            /// 合計移動量を表すベクトル
            public let vector: MoveVector
            /// 最終的な到達先
            public let destination: GridPoint
            /// 途中経路を含む通過マス（目的地を含む）
            public let traversedPoints: [GridPoint]

            /// イニシャライザ
            /// - Parameters:
            ///   - vector: 合計移動量
            ///   - destination: 最終到達地点
            ///   - traversedPoints: 通過マス配列（順番通りに格納する）
            public init(vector: MoveVector, destination: GridPoint, traversedPoints: [GridPoint]) {
                self.vector = vector
                self.destination = destination
                self.traversedPoints = traversedPoints
            }
        }

        /// 従来 API 互換用の基本ベクトル配列
        private let baseVectors: [MoveVector]
        /// 実際の経路を生成するクロージャ
        private let resolver: (GridPoint, ResolutionContext) -> [Path]
        /// このパターンのアイデンティティ
        public let identity: Identity

        /// プライベートイニシャライザ
        /// - Parameters:
        ///   - baseVectors: 既存 API 向けに返す代表ベクトル集合
        ///   - identity: 同一性判定用 ID
        ///   - resolver: 経路生成クロージャ
        private init(baseVectors: [MoveVector], identity: Identity, resolver: @escaping (GridPoint, ResolutionContext) -> [Path]) {
            self.baseVectors = baseVectors
            self.identity = identity
            self.resolver = resolver
        }

        /// 相対単歩／複数候補カード向けのパターンを生成する
        /// - Parameter vectors: 盤面に依存しない相対ベクトル配列
        /// - Returns: 与えられたベクトル列をそのまま候補とするパターン
        public static func relativeSteps(_ vectors: [MoveVector]) -> MovePattern {
            let identity = Identity.relativeSteps(vectors)
            return MovePattern(baseVectors: vectors, identity: identity) { origin, context in
                vectors.compactMap { vector in
                    let destination = origin.offset(dx: vector.dx, dy: vector.dy)
                    guard context.contains(destination), context.isTraversable(destination) else { return nil }
                    return Path(vector: vector, destination: destination, traversedPoints: [destination])
                }
            }
        }

        /// 指定方向へ連続直進するカード向けのパターンを生成する
        /// - Parameters:
        ///   - direction: 1 ステップ分の方向
        ///   - limit: 上限ステップ数（nil の場合は盤端まで継続）
        /// - Returns: 方向ベースで終点候補を列挙するパターン
        public static func directionalRay(direction: MoveVector, limit: Int?) -> MovePattern {
            let identity = Identity.directionalRay(direction: direction, limit: limit)
            return MovePattern(baseVectors: [direction], identity: identity) { origin, context in
                var results: [Path] = []
                results.reserveCapacity(4)
                var current = origin
                var traversed: [GridPoint] = []
                var step = 0

                while true {
                    step += 1
                    if let limit, step > limit { break }

                    current = current.offset(dx: direction.dx, dy: direction.dy)
                    guard context.contains(current), context.isTraversable(current) else { break }
                    traversed.append(current)

                    let accumulatedVector = MoveVector(dx: direction.dx * step, dy: direction.dy * step)
                    results.append(Path(vector: accumulatedVector, destination: current, traversedPoints: traversed))
                }

                return results
            }
        }

        /// 最終到達マスのみを候補として返す直進カード向けのパターン
        /// - Parameters:
        ///   - direction: 1 ステップ分の方向ベクトル
        ///   - limit: 上限ステップ数（nil の場合は盤端まで継続）
        /// - Returns: 終端のみを `Path` として返す移動パターン
        public static func directionalRayFinalStep(direction: MoveVector, limit: Int?) -> MovePattern {
            let identity = Identity.directionalRay(direction: direction, limit: limit)
            return MovePattern(baseVectors: [direction], identity: identity) { origin, context in
                // --- 経路解決の初期設定（現在地と通過マスログを保持）---
                var current = origin
                var traversed: [GridPoint] = []

                // --- 進行可能な限り同方向へ伸ばし、障害物や盤端で停止する ---
                while true {
                    let nextStepIndex = traversed.count + 1
                    if let limit, nextStepIndex > limit { break }

                    let nextPoint = current.offset(dx: direction.dx, dy: direction.dy)
                    guard context.contains(nextPoint), context.isTraversable(nextPoint) else { break }

                    traversed.append(nextPoint)
                    current = nextPoint
                }

                // --- 1 マスも進めない場合は候補なしとする ---
                guard let destination = traversed.last else { return [] }

                // --- 累積ベクトルを算出し、通過マス全体を含む Path を 1 件だけ返す ---
                let steps = traversed.count
                let vector = MoveVector(dx: direction.dx * steps, dy: direction.dy * steps)
                return [Path(vector: vector, destination: destination, traversedPoints: traversed)]
            }
        }

        /// 絶対座標指定カード向けのパターンを生成する
        /// - Parameter targets: 目的地候補の座標配列
        /// - Returns: 指定座標へ直接ジャンプするパターン
        public static func absoluteTargets(_ targets: [GridPoint]) -> MovePattern {
            let identity = Identity.absoluteTargets(targets)
            let fallbackVectors = targets.map { target in
                MoveVector(dx: target.x, dy: target.y)
            }
            return MovePattern(baseVectors: fallbackVectors, identity: identity) { origin, context in
                targets.compactMap { target in
                    guard context.contains(target), context.isTraversable(target) else { return nil }
                    let vector = MoveVector(dx: target.x - origin.x, dy: target.y - origin.y)
                    return Path(vector: vector, destination: target, traversedPoints: [target])
                }
            }
        }

        /// movementVectors 互換の代表ベクトル配列を返す
        /// - Returns: 既存 API で利用していたベクトル配列
        public func fallbackVectors() -> [MoveVector] { baseVectors }

        /// 指定した原点から到達可能な経路を列挙する
        /// - Parameters:
        ///   - origin: 現在位置
        ///   - context: 盤面判定に必要なコンテキスト
        /// - Returns: 盤内かつ進入可能な経路一覧
        public func resolvePaths(from origin: GridPoint, context: ResolutionContext) -> [Path] {
            resolver(origin, context)
        }
    }

    /// 既定のパターン集合
    private static let patternRegistry: [MoveCard: MovePattern] = {
        // MARK: - パターン定義マップ
        var mapping: [MoveCard: MovePattern] = [:]

        // --- キング型 ---
        mapping[.kingUp] = .relativeSteps([MoveVector(dx: 0, dy: 1)])
        mapping[.kingUpRight] = .relativeSteps([MoveVector(dx: 1, dy: 1)])
        mapping[.kingRight] = .relativeSteps([MoveVector(dx: 1, dy: 0)])
        mapping[.kingDownRight] = .relativeSteps([MoveVector(dx: 1, dy: -1)])
        mapping[.kingDown] = .relativeSteps([MoveVector(dx: 0, dy: -1)])
        mapping[.kingDownLeft] = .relativeSteps([MoveVector(dx: -1, dy: -1)])
        mapping[.kingLeft] = .relativeSteps([MoveVector(dx: -1, dy: 0)])
        mapping[.kingUpLeft] = .relativeSteps([MoveVector(dx: -1, dy: 1)])
        mapping[.kingUpOrDown] = .relativeSteps([
            MoveVector(dx: 0, dy: 1),
            MoveVector(dx: 0, dy: -1)
        ])
        mapping[.kingLeftOrRight] = .relativeSteps([
            MoveVector(dx: 1, dy: 0),
            MoveVector(dx: -1, dy: 0)
        ])
        mapping[.kingUpwardDiagonalChoice] = .relativeSteps([
            MoveVector(dx: 1, dy: 1),
            MoveVector(dx: -1, dy: 1)
        ])
        mapping[.kingRightDiagonalChoice] = .relativeSteps([
            MoveVector(dx: 1, dy: 1),
            MoveVector(dx: 1, dy: -1)
        ])
        mapping[.kingDownwardDiagonalChoice] = .relativeSteps([
            MoveVector(dx: 1, dy: -1),
            MoveVector(dx: -1, dy: -1)
        ])
        mapping[.kingLeftDiagonalChoice] = .relativeSteps([
            MoveVector(dx: -1, dy: 1),
            MoveVector(dx: -1, dy: -1)
        ])

        // --- ナイト型 ---
        mapping[.knightUp2Right1] = .relativeSteps([MoveVector(dx: 1, dy: 2)])
        mapping[.knightUp2Left1] = .relativeSteps([MoveVector(dx: -1, dy: 2)])
        mapping[.knightUp1Right2] = .relativeSteps([MoveVector(dx: 2, dy: 1)])
        mapping[.knightUp1Left2] = .relativeSteps([MoveVector(dx: -2, dy: 1)])
        mapping[.knightDown2Right1] = .relativeSteps([MoveVector(dx: 1, dy: -2)])
        mapping[.knightDown2Left1] = .relativeSteps([MoveVector(dx: -1, dy: -2)])
        mapping[.knightDown1Right2] = .relativeSteps([MoveVector(dx: 2, dy: -1)])
        mapping[.knightDown1Left2] = .relativeSteps([MoveVector(dx: -2, dy: -1)])
        mapping[.knightUpwardChoice] = .relativeSteps([
            MoveVector(dx: 1, dy: 2),
            MoveVector(dx: -1, dy: 2)
        ])
        mapping[.knightRightwardChoice] = .relativeSteps([
            MoveVector(dx: 2, dy: 1),
            MoveVector(dx: 2, dy: -1)
        ])
        mapping[.knightDownwardChoice] = .relativeSteps([
            MoveVector(dx: 1, dy: -2),
            MoveVector(dx: -1, dy: -2)
        ])
        mapping[.knightLeftwardChoice] = .relativeSteps([
            MoveVector(dx: -2, dy: 1),
            MoveVector(dx: -2, dy: -1)
        ])

        // --- 長距離カード ---
        mapping[.straightUp2] = .relativeSteps([MoveVector(dx: 0, dy: 2)])
        mapping[.straightDown2] = .relativeSteps([MoveVector(dx: 0, dy: -2)])
        mapping[.straightRight2] = .relativeSteps([MoveVector(dx: 2, dy: 0)])
        mapping[.straightLeft2] = .relativeSteps([MoveVector(dx: -2, dy: 0)])
        mapping[.diagonalUpRight2] = .relativeSteps([MoveVector(dx: 2, dy: 2)])
        mapping[.diagonalDownRight2] = .relativeSteps([MoveVector(dx: 2, dy: -2)])
        mapping[.diagonalDownLeft2] = .relativeSteps([MoveVector(dx: -2, dy: -2)])
        mapping[.diagonalUpLeft2] = .relativeSteps([MoveVector(dx: -2, dy: 2)])

        // --- 無制限レイ型（障害物か盤端まで進む連続カード）---
        let directionalRayDefinitions: [(MoveCard, MoveVector)] = [
            (.rayUp, MoveVector(dx: 0, dy: 1)),
            (.rayUpRight, MoveVector(dx: 1, dy: 1)),
            (.rayRight, MoveVector(dx: 1, dy: 0)),
            (.rayDownRight, MoveVector(dx: 1, dy: -1)),
            (.rayDown, MoveVector(dx: 0, dy: -1)),
            (.rayDownLeft, MoveVector(dx: -1, dy: -1)),
            (.rayLeft, MoveVector(dx: -1, dy: 0)),
            (.rayUpLeft, MoveVector(dx: -1, dy: 1))
        ]
        directionalRayDefinitions.forEach { card, vector in
            mapping[card] = .directionalRayFinalStep(direction: vector, limit: nil)
        }

        return mapping
    }()

    /// MovePattern が存在しない場合のフォールバック
    private static let emptyPattern = MovePattern.relativeSteps([])

    /// カードが持つ移動パターン
    public var movePattern: MovePattern {
        guard let pattern = MoveCard.patternRegistry[self] else {
            assertionFailure("MoveCard に対する MovePattern が登録されていません: \(self)")
            return MoveCard.emptyPattern
        }
        return pattern
    }
    // MARK: - 定義済みセット
    /// 盤端まで伸びるレイ型カード 8 種の集合
    /// - Important: デッキ構築や重み設定でも頻繁に参照するため、定数として公開する
    public static let directionalRayCards: [MoveCard] = [
        .rayUp,
        .rayUpRight,
        .rayRight,
        .rayDownRight,
        .rayDown,
        .rayDownLeft,
        .rayLeft,
        .rayUpLeft
    ]

    /// 標準デッキで採用している 32 種類のカード集合
    /// - Important: 選択式カードは含めず、単方向カードと連続レイ型カードのみで構成する
    public static let standardSet: [MoveCard] = [
        .kingUp,
        .kingUpRight,
        .kingRight,
        .kingDownRight,
        .kingDown,
        .kingDownLeft,
        .kingLeft,
        .kingUpLeft,
        .knightUp2Right1,
        .knightUp2Left1,
        .knightUp1Right2,
        .knightUp1Left2,
        .knightDown2Right1,
        .knightDown2Left1,
        .knightDown1Right2,
        .knightDown1Left2,
        .straightUp2,
        .straightDown2,
        .straightRight2,
        .straightLeft2,
        .diagonalUpRight2,
        .diagonalDownRight2,
        .diagonalDownLeft2,
        .diagonalUpLeft2
    ] + directionalRayCards

    // MARK: - 全ケース一覧
    /// `CaseIterable` の自動生成は internal となるため、外部モジュールからも全種類を参照できるよう明示的に公開配列を定義する
    /// - Note: スタンダードセットに複数方向カードを加えた順序で公開する
    public static let allCases: [MoveCard] = standardSet + [
        .kingUpOrDown,
        .kingLeftOrRight,
        .kingUpwardDiagonalChoice,
        .kingRightDiagonalChoice,
        .kingDownwardDiagonalChoice,
        .kingLeftDiagonalChoice,
        .knightUpwardChoice,
        .knightRightwardChoice,
        .knightDownwardChoice,
        .knightLeftwardChoice
    ]

    // MARK: - ケース定義
    /// キング型: 上に 1
    case kingUp
    /// キング型: 右上に 1
    case kingUpRight
    /// キング型: 右に 1
    case kingRight
    /// キング型: 右下に 1
    case kingDownRight
    /// キング型: 下に 1
    case kingDown
    /// キング型: 左下に 1
    case kingDownLeft
    /// キング型: 左に 1
    case kingLeft
    /// キング型: 左上に 1
    case kingUpLeft
    /// キング型: 上下いずれか 1 マスの選択移動
    case kingUpOrDown
    /// キング型: 左右いずれか 1 マスの選択移動
    case kingLeftOrRight
    /// キング型: 上方向の斜め 2 方向（右上・左上）から選択するカード
    case kingUpwardDiagonalChoice
    /// キング型: 右方向の斜め 2 方向（右上・右下）から選択するカード
    case kingRightDiagonalChoice
    /// キング型: 下方向の斜め 2 方向（右下・左下）から選択するカード
    case kingDownwardDiagonalChoice
    /// キング型: 左方向の斜め 2 方向（左上・左下）から選択するカード
    case kingLeftDiagonalChoice

    /// ナイト型: 上に 2、右に 1
    case knightUp2Right1
    /// ナイト型: 上に 2、左に 1
    case knightUp2Left1
    /// ナイト型: 上に 1、右に 2
    case knightUp1Right2
    /// ナイト型: 上に 1、左に 2
    case knightUp1Left2
    /// ナイト型: 下に 2、右に 1
    case knightDown2Right1
    /// ナイト型: 下に 2、左に 1
    case knightDown2Left1
    /// ナイト型: 下に 1、右に 2
    case knightDown1Right2
    /// ナイト型: 下に 1、左に 2
    case knightDown1Left2
    /// ナイト型: 上方向 2 種（上2右1/上2左1）から選択するカード
    case knightUpwardChoice
    /// ナイト型: 右方向 2 種（上1右2/下1右2）から選択するカード
    case knightRightwardChoice
    /// ナイト型: 下方向 2 種（下2右1/下2左1）から選択するカード
    case knightDownwardChoice
    /// ナイト型: 左方向 2 種（上1左2/下1左2）から選択するカード
    case knightLeftwardChoice

    /// 直線: 上に 2
    case straightUp2
    /// 直線: 下に 2
    case straightDown2
    /// 直線: 右に 2
    case straightRight2
    /// 直線: 左に 2
    case straightLeft2

    /// 斜め: 右上に 2
    case diagonalUpRight2
    /// 斜め: 右下に 2
    case diagonalDownRight2
    /// 斜め: 左下に 2
    case diagonalDownLeft2
    /// 斜め: 左上に 2
    case diagonalUpLeft2

    /// レイ型: 上方向へ障害物まで連続移動
    case rayUp
    /// レイ型: 右上方向へ障害物まで連続移動
    case rayUpRight
    /// レイ型: 右方向へ障害物まで連続移動
    case rayRight
    /// レイ型: 右下方向へ障害物まで連続移動
    case rayDownRight
    /// レイ型: 下方向へ障害物まで連続移動
    case rayDown
    /// レイ型: 左下方向へ障害物まで連続移動
    case rayDownLeft
    /// レイ型: 左方向へ障害物まで連続移動
    case rayLeft
    /// レイ型: 左上方向へ障害物まで連続移動
    case rayUpLeft

    // MARK: - 移動ベクトル
    /// カードが持つ移動候補一覧を返す
    /// - Important: 現行カードは 1 要素のみだが、今後複数候補を持つカード追加時に拡張しやすいよう配列で保持する
    /// テスト向けに movementVectors を差し替えるためのオーバーライド辞書
    /// - Note: テスト完了後は必ず nil を指定してクリーンアップし、副作用を残さないようにする
    static var testMovementVectorOverrides: [MoveCard: [MoveVector]] = [:]

    /// movementVectors を一時的に差し替えるヘルパー
    /// - Parameters:
    ///   - vectors: 差し替え後の移動ベクトル配列。nil を渡すと元の定義に戻す。
    ///   - card: 対象となるカード種別
    static func setTestMovementVectors(_ vectors: [MoveVector]?, for card: MoveCard) {
        if let vectors {
            testMovementVectorOverrides[card] = vectors
        } else {
            testMovementVectorOverrides.removeValue(forKey: card)
        }
    }

    public var movementVectors: [MoveVector] {
        if let override = MoveCard.testMovementVectorOverrides[self] {
            return override
        }
        return movePattern.fallbackVectors()
    }

    /// 盤面状況を考慮した移動経路を解決する
    /// - Parameters:
    ///   - origin: 現在位置
    ///   - context: 盤面サイズ・進入可否を評価するためのコンテキスト
    /// - Returns: 実際に移動可能な経路一覧
    public func resolvePaths(from origin: GridPoint, context: MovePattern.ResolutionContext) -> [MovePattern.Path] {
        if let override = MoveCard.testMovementVectorOverrides[self] {
            // テスト用オーバーライドが指定されている場合は、相対単歩としてシンプルに展開する
            return override.compactMap { vector in
                let destination = origin.offset(dx: vector.dx, dy: vector.dy)
                guard context.contains(destination), context.isTraversable(destination) else { return nil }
                return MovePattern.Path(vector: vector, destination: destination, traversedPoints: [destination])
            }
        }
        return movePattern.resolvePaths(from: origin, context: context)
    }

    /// 既存コードとの互換性を維持するための代表ベクトル
    /// - Note: 候補が複数化した際は UI 側での選択ロジックを追加しやすいよう、先頭要素を共通の入口として公開する
    public var primaryVector: MoveVector {
        guard let vector = movementVectors.first else {
            assertionFailure("MoveCard.movementVectors は最低 1 要素を想定している")
            return MoveVector(dx: 0, dy: 0)
        }
        return vector
    }

    // MARK: - UI 表示名
    /// UI に表示する日本語の名前
    public var displayName: String {
        switch self {
        case .kingUp:
            // キング型: 上方向へ 1 マス移動
            return "上1"
        case .kingUpRight:
            // キング型: 右上方向へ 1 マス移動
            return "右上1"
        case .kingRight:
            // キング型: 右方向へ 1 マス移動
            return "右1"
        case .kingDownRight:
            // キング型: 右下方向へ 1 マス移動
            return "右下1"
        case .kingDown:
            // キング型: 下方向へ 1 マス移動
            return "下1"
        case .kingDownLeft:
            // キング型: 左下方向へ 1 マス移動
            return "左下1"
        case .kingLeft:
            // キング型: 左方向へ 1 マス移動
            return "左1"
        case .kingUpLeft:
            // キング型: 左上方向へ 1 マス移動
            return "左上1"
        case .kingUpOrDown:
            // キング型: 上下のどちらか 1 マスを選択する特別カード
            return "上下1 (選択)"
        case .kingLeftOrRight:
            // キング型: 左右のどちらか 1 マスを選択する特別カード
            return "左右1 (選択)"
        case .kingUpwardDiagonalChoice:
            // キング型: 左右の上斜めから好みの方向を選ぶ特別カード
            return "上斜め1 (選択)"
        case .kingRightDiagonalChoice:
            // キング型: 上下の右斜めから好みの方向を選ぶ特別カード
            return "右斜め1 (選択)"
        case .kingDownwardDiagonalChoice:
            // キング型: 左右の下斜めから好みの方向を選ぶ特別カード
            return "下斜め1 (選択)"
        case .kingLeftDiagonalChoice:
            // キング型: 上下の左斜めから好みの方向を選ぶ特別カード
            return "左斜め1 (選択)"
        case .knightUp2Right1: return "上2右1"
        case .knightUp2Left1: return "上2左1"
        case .knightUp1Right2: return "上1右2"
        case .knightUp1Left2: return "上1左2"
        case .knightDown2Right1: return "下2右1"
        case .knightDown2Left1: return "下2左1"
        case .knightDown1Right2: return "下1右2"
        case .knightDown1Left2: return "下1左2"
        case .knightUpwardChoice:
            // 桂馬型: 上方向 2 種から好みを選べる特別カード
            return "上桂 (選択)"
        case .knightRightwardChoice:
            // 桂馬型: 右方向 2 種から好みを選べる特別カード
            return "右桂 (選択)"
        case .knightDownwardChoice:
            // 桂馬型: 下方向 2 種から好みを選べる特別カード
            return "下桂 (選択)"
        case .knightLeftwardChoice:
            // 桂馬型: 左方向 2 種から好みを選べる特別カード
            return "左桂 (選択)"
        case .straightUp2: return "上2"
        case .straightDown2: return "下2"
        case .straightRight2: return "右2"
        case .straightLeft2: return "左2"
        case .diagonalUpRight2: return "右上2"
        case .diagonalDownRight2: return "右下2"
        case .diagonalDownLeft2: return "左下2"
        case .diagonalUpLeft2: return "左上2"
        case .rayUp:
            // レイ型: 上方向へ連続移動するカード
            return "上連続"
        case .rayUpRight:
            // レイ型: 右上方向へ連続移動するカード
            return "右上連続"
        case .rayRight:
            // レイ型: 右方向へ連続移動するカード
            return "右連続"
        case .rayDownRight:
            // レイ型: 右下方向へ連続移動するカード
            return "右下連続"
        case .rayDown:
            // レイ型: 下方向へ連続移動するカード
            return "下連続"
        case .rayDownLeft:
            // レイ型: 左下方向へ連続移動するカード
            return "左下連続"
        case .rayLeft:
            // レイ型: 左方向へ連続移動するカード
            return "左連続"
        case .rayUpLeft:
            // レイ型: 左上方向へ連続移動するカード
            return "左上連続"
        }
    }

    // MARK: - 属性判定
    /// 王将型（キング型）に該当するかを判定するフラグ
    /// - Note: デッキ構築時の配分調整に利用する
    public var isKingType: Bool {
        switch self {
        case .kingUp,
             .kingUpRight,
             .kingRight,
             .kingDownRight,
             .kingDown,
             .kingDownLeft,
             .kingLeft,
             .kingUpLeft,
             .kingUpOrDown,
             .kingLeftOrRight,
             .kingUpwardDiagonalChoice,
             .kingRightDiagonalChoice,
             .kingDownwardDiagonalChoice,
             .kingLeftDiagonalChoice:
            return true
        default:
            return false
        }
    }

    /// ナイト型カードかどうかを判定するフラグ
    /// - Note: 山札内で桂馬カードの重み付けを計算するために利用する
    public var isKnightType: Bool {
        switch self {
        case .knightUp2Right1,
             .knightUp2Left1,
             .knightUp1Right2,
             .knightUp1Left2,
             .knightDown2Right1,
             .knightDown2Left1,
             .knightDown1Right2,
             .knightDown1Left2,
             .knightUpwardChoice,
             .knightRightwardChoice,
             .knightDownwardChoice,
             .knightLeftwardChoice:
            return true
        default:
            return false
        }
    }

    /// 斜め 2 マス（マンハッタン距離 4）の長距離斜めカードかどうかを判定する
    /// - Note: 山札の重み調整（桂馬カードの半分の排出確率）に利用する
    public var isDiagonalDistanceFour: Bool {
        switch self {
        case .diagonalUpRight2,
             .diagonalDownRight2,
             .diagonalDownLeft2,
             .diagonalUpLeft2:
            return true
        default:
            return false
        }
    }

    /// 盤端や障害物まで連続で進むレイ型カードかどうかを判定する
    /// - Note: 山札の重み調整や UI 表示順の制御で利用する
    public var isDirectionalRay: Bool {
        switch self {
        case .rayUp,
             .rayUpRight,
             .rayRight,
             .rayDownRight,
             .rayDown,
             .rayDownLeft,
             .rayLeft,
             .rayUpLeft:
            return true
        default:
            return false
        }
    }

    // MARK: - 利用判定
    /// 指定した座標からこのカードが使用可能か判定する
    /// - Parameters:
    ///   - from: 現在位置
    ///   - boardSize: 判定対象となる盤面サイズ
    /// - Returns: 盤内に移動できる場合は true
    public func canUse(from: GridPoint, boardSize: Int) -> Bool {
        // 盤面情報がサイズのみの場合は、進入可否も「盤内かどうか」で判定する
        let context = MovePattern.ResolutionContext(
            boardSize: boardSize,
            contains: { point in point.isInside(boardSize: boardSize) },
            isTraversable: { point in point.isInside(boardSize: boardSize) }
        )
        // resolvePaths を用いることで将来的に連続移動へ拡張した際も同一判定ロジックを流用できる
        return !resolvePaths(from: from, context: context).isEmpty
    }
}

// MARK: - デバッグ用表示名
extension MoveCard: CustomStringConvertible {
    /// デバッグログでカード名をわかりやすくするため displayName を返す
    public var description: String { displayName }
}

// MARK: - Identifiable への適合
extension MoveCard: Identifiable {
    /// `Identifiable` 準拠のための一意な識別子
    /// ここでは単純に UUID を生成して返す
    /// - Note: 山札で同種カードが複数枚存在するため
    ///         各カードインスタンスを区別する目的で利用する
    public var id: UUID { UUID() }
}
