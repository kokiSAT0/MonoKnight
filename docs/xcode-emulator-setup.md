# Xcode で iOS シミュレーターを起動する手順

MonoKnight のライブラリ `Game` を **Xcode** に取り込み、iOS シミュレーターで動かすまでの流れをまとめます。
アプリの Xcode プロジェクトはリポジトリ直下に配置し、Git で共有します（外部に作成する場合は `.gitignore` で除外）。
コマンドラインでのビルドやテストについては [`development-basics.md`](development-basics.md) を参照してください。

## 前提条件
- macOS 13 以降
- Xcode 15 以降（Apple ID を Xcode に追加済み）
- リポジトリをローカルにクローン済みであること

```bash
# 未取得の場合のみリポジトリを取得
git clone https://github.com/example/MonoKnight.git  # プロジェクトを取得
cd MonoKnight                                         # プロジェクトに移動
```

## 1. Package を Xcode で開く
1. Finder で `MonoKnight` フォルダを開き、`Package.swift` をダブルクリック。
2. Xcode が起動し、Swift Package として読み込まれます。

## 2. iOS アプリの入れ物を作成
1. Xcode メニューで **File > New > Project…** を選択。
2. テンプレートから **iOS > App** を選び、例として `MonoKnightApp` という名前で作成。
   - 保存場所はクローンした `MonoKnight` フォルダ直下（`MonoKnight.xcodeproj` の例）。
3. Interface は **SwiftUI**、Language は **Swift** を選択。

## 3. ライブラリ `Game` をアプリに組み込む
1. プロジェクト設定の **Package Dependencies** タブを開く。
2. 右下の `+` から **Add Local…** を選択し、先ほどの `MonoKnight` フォルダを指定。
3. 依存ターゲットに `Game` を選び、アプリターゲットにリンクされていることを確認。

## 4. Team 設定（任意）
- Target の **Signing & Capabilities** で **Team** を選択。
- シミュレーター実行のみなら未設定でも問題ありません。

## 5. シミュレーターで実行
1. 左上の **Scheme** を作成したアプリ（例：`MonoKnightApp`）に設定。
2. デバイスから任意の iPhone シミュレーターを選択。
3. **⌘R** でビルドし、シミュレーターが起動すれば完了です。

以上で Xcode を使ったシミュレーター起動の準備は完了です。

---

## 付録A: プロジェクト構成図

```text
MonoKnight/
├─ MonoKnight.xcodeproj      # アプリ本体の Xcode プロジェクト
├─ MonoKnightApp.swift       # アプリのエントリポイント
├─ Info.plist                # アプリ設定
├─ Package.swift             # SwiftPM 設定
├─ Game/                     # ゲームロジック
├─ UI/                       # 画面関連
├─ Services/                 # プラットフォーム機能
├─ Tests/                    # テストコード
├─ Config/                   # xcconfig など
└─ docs/                     # ドキュメント
```

リポジトリ内にアプリプロジェクトを置くことで、構成が共有されチーム内で同期しやすくなります。

