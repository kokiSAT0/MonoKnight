# MonoKnight

SwiftUI と SpriteKit を組み合わせたカード移動パズル。\
主要機能（Game Center ランキング・広告除去 IAP・インタースティシャル広告制御・同意フロー）は実装済みで、正式リリース向けの仕上げ段階に入っている。

## テストの実行方法

本リポジトリでは **Swift Package Manager** を利用して単体テストを管理しています。

```bash
# 依存関係の解決とテストの実行
swift test
```

上記コマンドをプロジェクトルートで実行すると、`Game` モジュールに対するテストが実行されます。\
リリース準備中は PR ごとにテスト結果を共有し、品質のすり合わせを密に行うことを推奨する。

## 開発ドキュメント


- [`docs/development-basics.md`](docs/development-basics.md)：SPM を用いたビルド・テスト手順
- [`docs/files.md`](docs/files.md)：リポジトリ構成とシミュレーター実行までの手順
- [`docs/recommended-task-list.md`](docs/recommended-task-list.md)：リリースに向けて優先度別に整理した残タスク

## リポジトリ構成

```text
MonoKnight/
├─ MonoKnight.xcodeproj      # アプリ本体の Xcode プロジェクト
├─ Package.swift             # SwiftPM 設定
├─ Game/                     # ゲームロジック
├─ UI/                       # 画面関連
├─ Services/                 # プラットフォーム機能
├─ Tests/                    # テストコード
├─ Config/                   # xcconfig など
└─ docs/                     # ドキュメント
```


## VSCode の設定共有

開発者ごとの VSCode 設定は `.vscode/` ディレクトリに保存しますが、リポジトリでは追跡しません。
共有したい設定を `.vscode.sample` にサンプルとして用意しているので、必要に応じて以下のコマンドでコピーしてください。

```bash
cp -r .vscode.sample .vscode
```

コピー後、環境に合わせて設定内容を調整してから利用してください。
