import SpriteKit

/// 盤面や駒を描画する `SKScene`
/// - 備考: 現時点ではレイアウトのみ。今後の拡張で盤面描画やタップ処理を実装予定
final class GameScene: SKScene {
    /// ゲームロジックへの参照
    private let core: GameCore

    /// 初期化時にゲームロジックを受け取り、シーンサイズを設定する
    init(size: CGSize, core: GameCore) {
        self.core = core
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = .black
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
