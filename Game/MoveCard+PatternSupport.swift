import Foundation

public extension MoveCard {
    /// カードが持つ移動パターンを抽象化した構造体
    /// - Important: これまでは単純なベクトル配列のみで管理していたが、将来的な連続移動や絶対座標指定カードにも対応できるよう、
    ///              パターン種別と経路を合わせて扱えるメタデータへ整理する。
    struct MovePattern {
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
            /// 既踏マスかどうかを判定するクロージャ
            /// - Note: 絶対座標ジャンプ系カードで未踏マス優先の挙動を実装するため追加
            private let visitedHandler: (GridPoint) -> Bool
            /// 目的地制で参照する現在目的地。目的地制でない場合は nil。
            public let targetPoint: GridPoint?
            /// 盤面上の特殊効果マスを参照するクロージャ
            private let effectHandler: (GridPoint) -> TileEffect?

            /// イニシャライザ
            /// - Parameters:
            ///   - boardSize: 対象となる盤面サイズ
            ///   - contains: 盤内判定を行うクロージャ
            ///   - isTraversable: 障害物などで進入不可かどうかを判定するクロージャ
            public init(
                boardSize: Int,
                contains: @escaping (GridPoint) -> Bool,
                isTraversable: @escaping (GridPoint) -> Bool,
                isVisited: @escaping (GridPoint) -> Bool = { _ in false },
                targetPoint: GridPoint? = nil,
                effectAt: @escaping (GridPoint) -> TileEffect? = { _ in nil }
            ) {
                self.boardSize = boardSize
                self.containsHandler = contains
                self.traversableHandler = isTraversable
                self.visitedHandler = isVisited
                self.targetPoint = targetPoint
                self.effectHandler = effectAt
            }

            /// 指定座標が盤内かどうかを返す
            public func contains(_ point: GridPoint) -> Bool {
                containsHandler(point)
            }

            /// 指定座標へ進入可能かを返す
            public func isTraversable(_ point: GridPoint) -> Bool {
                traversableHandler(point)
            }

            /// 指定座標が既に踏破済みかを返す
            public func isVisited(_ point: GridPoint) -> Bool {
                visitedHandler(point)
            }

            /// 指定座標の特殊効果を返す
            public func effect(at point: GridPoint) -> TileEffect? {
                effectHandler(point)
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
        private init(baseVectors: [MoveVector], identity: Identity, resolver: @escaping (GridPoint, ResolutionContext) -> [Path]) {
            self.baseVectors = baseVectors
            self.identity = identity
            self.resolver = resolver
        }

        /// 相対単歩／複数候補カード向けのパターンを生成する
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
        public static func directionalRayFinalStep(direction: MoveVector, limit: Int?) -> MovePattern {
            let identity = Identity.directionalRay(direction: direction, limit: limit)
            return MovePattern(baseVectors: [direction], identity: identity) { origin, context in
                var current = origin
                var traversed: [GridPoint] = []

                while true {
                    let nextStepIndex = traversed.count + 1
                    if let limit, nextStepIndex > limit { break }

                    let nextPoint = current.offset(dx: direction.dx, dy: direction.dy)
                    guard context.contains(nextPoint), context.isTraversable(nextPoint) else { break }

                    traversed.append(nextPoint)
                    current = nextPoint
                }

                guard let destination = traversed.last else { return [] }

                let steps = traversed.count
                let vector = MoveVector(dx: direction.dx * steps, dy: direction.dy * steps)
                return [Path(vector: vector, destination: destination, traversedPoints: traversed)]
            }
        }

        /// 絶対座標指定カード向けのパターンを生成する
        public static func absoluteTargets(
            _ targets: [GridPoint],
            identity: Identity? = nil,
            fallbackVectorsOverride: [MoveVector]? = nil
        ) -> MovePattern {
            let resolvedIdentity = identity ?? Identity.absoluteTargets(targets)
            let fallbackVectors: [MoveVector]
            if let overrideVectors = fallbackVectorsOverride {
                fallbackVectors = overrideVectors
            } else {
                fallbackVectors = targets.map { target in
                    MoveVector(dx: target.x, dy: target.y)
                }
            }
            return MovePattern(baseVectors: fallbackVectors, identity: resolvedIdentity) { origin, context in
                targets.compactMap { target in
                    guard context.contains(target), context.isTraversable(target) else { return nil }
                    let vector = MoveVector(dx: target.x - origin.x, dy: target.y - origin.y)
                    return Path(vector: vector, destination: target, traversedPoints: [target])
                }
            }
        }

        /// 盤面全域を走査して目的地候補を動的に生成するカード向けのパターンを構築する
        public static func dynamicAbsoluteTargets(
            identity: Identity,
            fallbackBoardSize: Int = BoardGeometry.standardSize,
            allowsVisitedTargets: Bool = true,
            additionalFilter: ((GridPoint, GridPoint, ResolutionContext) -> Bool)? = nil
        ) -> MovePattern {
            let fallbackVectors = makeFallbackVectors(forBoardSize: fallbackBoardSize)

            return MovePattern(baseVectors: fallbackVectors, identity: identity) { origin, context in
                let allPoints = BoardGeometry.allPoints(for: context.boardSize)
                var paths: [Path] = []
                paths.reserveCapacity(allPoints.count)

                for target in allPoints {
                    if target == origin { continue }
                    guard context.contains(target), context.isTraversable(target) else { continue }
                    if !allowsVisitedTargets && context.isVisited(target) { continue }
                    if let additionalFilter, !additionalFilter(target, origin, context) { continue }

                    let vector = MoveVector(dx: target.x - origin.x, dy: target.y - origin.y)
                    paths.append(Path(vector: vector, destination: target, traversedPoints: [target]))
                }

                paths.sort { lhs, rhs in
                    if lhs.destination.y != rhs.destination.y {
                        return lhs.destination.y < rhs.destination.y
                    }
                    return lhs.destination.x < rhs.destination.x
                }

                return paths
            }
        }

        /// movementVectors のフォールバックとして利用する代表ベクトルを生成する
        private static func makeFallbackVectors(forBoardSize boardSize: Int) -> [MoveVector] {
            guard boardSize > 0 else { return [] }
            let center = BoardGeometry.defaultSpawnPoint(for: boardSize)
            let allPoints = BoardGeometry.allPoints(for: boardSize)
            let vectors = allPoints.compactMap { point -> MoveVector? in
                guard point != center else { return nil }
                return MoveVector(dx: point.x - center.x, dy: point.y - center.y)
            }
            return vectors.sorted { lhs, rhs in
                if lhs.dy != rhs.dy {
                    return lhs.dy < rhs.dy
                }
                return lhs.dx < rhs.dx
            }
        }

        /// movementVectors 互換の代表ベクトル配列を返す
        public func fallbackVectors() -> [MoveVector] { baseVectors }

        /// 指定した原点から到達可能な経路を列挙する
        public func resolvePaths(from origin: GridPoint, context: ResolutionContext) -> [Path] {
            resolver(origin, context)
        }
    }
}
