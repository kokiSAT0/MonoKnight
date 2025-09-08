# 開発の基本手順とデバッグビルド

## 前提条件
- macOS 13 以降がインストールされたMac
- Xcode 15 以降
- Gitコマンドが利用可能であること
- 安定したインターネット接続

## 1. リポジトリの取得
```bash
# 作業用ディレクトリに移動（例: ホーム直下の work フォルダ）
cd ~/work

# GitHub から本プロジェクトをクローン（認証が求められる場合があります）
git clone https://github.com/example/MonoKnight.git

# プロジェクトディレクトリへ移動
cd MonoKnight
```

## 2. 依存関係の解決
```bash
# Swift Package の依存関係を取得
swift package resolve
```

## 3. デバッグビルドの実行
```bash
# Debug 設定でビルド（成果物は .build/debug/ 以下に生成されます）
swift build -c debug

# 生成された実行ファイルを確認（任意）
ls .build/debug
```

## 4. テストの実行
```bash
# 事前にビルドが行われた後、ユニットテストが実行されます
swift test
```

## 5. 実行とデバッグの基本
- `swift run` でコマンドライン実行が可能です
- Xcode で `Package.swift` を開き、ブレークポイントを設定して ⌘R でデバッグ実行できます
- `print` 文や `lldb`（Xcode デバッグコンソール）を活用し、変数の値や挙動を確認します

## 6. よくあるトラブルと対処
- **ビルドに失敗する場合**
  - `swift package clean` を実行してキャッシュをクリアし、再度ビルドを試します
- **依存パッケージの取得に失敗する場合**
  - ネットワーク接続やプロキシ設定を見直してください
- **実行時にクラッシュする場合**
  - Xcode のデバッグコンソールでエラーログを確認し、原因を特定します

