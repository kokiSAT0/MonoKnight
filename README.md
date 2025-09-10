# MonoKnight

SwiftUI と SpriteKit を用いたカード移動パズルのプロトタイプ。

## テストの実行方法

本リポジトリでは **Swift Package Manager** を利用して単体テストを管理しています。

```bash
# 依存関係の解決とテストの実行
swift test
```

上記コマンドをプロジェクトルートで実行すると、`Game` モジュールに対するテストが実行されます。

## 開発の基本手順

 - 初めて環境構築を行う場合やデバッグビルドの作成方法については
   [`docs/development-basics.md`](docs/development-basics.md) を参照してください。
 - iOS シミュレーターでアプリを動かすための設定手順は
   [`docs/xcode-emulator-setup.md`](docs/xcode-emulator-setup.md) を参照してください。

## VSCode の設定共有

開発者ごとの VSCode 設定は `.vscode/` ディレクトリに保存しますが、リポジトリでは追跡しません。
共有したい設定を `.vscode.sample` にサンプルとして用意しているので、必要に応じて以下のコマンドでコピーしてください。

```bash
cp -r .vscode.sample .vscode
```

コピー後、環境に合わせて設定内容を調整してから利用してください。
