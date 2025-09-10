# 開発の基本手順（SPM でのビルド・テスト専用）

本書は **Swift Package Manager** を利用したコマンドラインでのビルド・テスト手順に特化しています。
Xcode でシミュレーターを起動したい場合は [`xcode-emulator-setup.md`](xcode-emulator-setup.md) を参照してください。

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
# ビルド済みターゲットに対してユニットテストを実行
swift test
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

