# 開発の基本手順（SPM でのビルド・テスト専用）

本書は **Swift Package Manager** を利用したコマンドラインでのビルド・テスト手順に特化しています。
Xcode でシミュレーターを起動したい場合は [`files.md`](files.md) の「シミュレーターで実行」セクションを参照してください。

## 前提条件

- macOS 13 以降がインストールされた Mac
- Xcode 15 以降（付属の Swift ツールチェーン）
- Git コマンドと安定したインターネット接続

## 1. リポジトリの取得

```bash
# 作業用ディレクトリに移動（例: ホーム直下の work フォルダ）
cd ~/work

# GitHub からリポジトリを取得
git clone https://github.com/kokiSAT0/MonoKnight.git

# プロジェクトディレクトリへ移動
cd MonoKnight
```

## 2. 依存関係の解決

```bash
# Swift Package の依存関係を取得
swift package resolve
```

## 3. デバッグビルド

```bash
# Debug 設定でビルド（成果物は .build/debug/ に生成）
swift build -c debug

# ビルド成果物を確認（任意）
ls .build/debug
```

## 4. テストの実行

```bash
# Codex 経由の通常検証は、低負荷設定の安全スクリプトを優先
Scripts/codex-safe-validate.sh logic
```

手元で直接 SPM テストを実行したい場合は `swift test` でもよいが、開発終盤や Codex に検証を任せる場合は安全スクリプトを使う。
アプリ側の限定テストやシミュレーター build が必要な場合も、PC の安定性を優先して以下を使う。
この開発端末では `iPhone 16 / iOS 18.6` を標準のシミュレーター指定にする。
`OS=latest` は最新ランタイム側に `iPhone 16` がないと失敗するため、直接 `xcodebuild` する場合も `OS=18.6` を指定する。

```bash
# app test 起動確認用の軽い smoke を実行
Scripts/codex-safe-validate.sh app-test

# 必要な app test は明示して実行
Scripts/codex-safe-validate.sh app-test MonoKnightAppTests/GameHandSectionViewAccessibilityTests

# テスト実行なしでシミュレーター向け build だけを確認
Scripts/codex-safe-validate.sh build
```

直接 `xcodebuild` を使う必要がある場合の destination は次を使う。

```bash
-destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'
```

## 5. 実行とデバッグ

- `swift run` でコマンドライン実行が可能
- `print` 文や `lldb` で挙動を確認する
- シミュレーター実行が必要な場合は別ドキュメントを参照

## 6. よくあるトラブルと対処

- **ビルドに失敗する場合**
  - `swift package clean` を実行してキャッシュをクリアし再ビルド
- **依存パッケージ取得に失敗する場合**
  - ネットワーク接続やプロキシ設定を確認
- **実行時にクラッシュする場合**
  - コンソール出力や `lldb` でエラーを追跡
