# MonoKnight を **Xcode の iOS シミュレーター**で起動するための“完全版”手順書（初心者向け）

> 目的：**GitHub の MonoKnight をローカルに用意して、Xcode を使って iPhone シミュレーターで起動**する。
> 想定読者：**Swift / VS Code / Xcode / Mac 初体験**の人。
> ゴールまでの所要時間：30–60分（ネット環境・Macの速度で変動）。

---

## 0. 事前に知っておくと安心な用語（1分でOK）

* **Xcode**：Apple純正の開発アプリ。ビルドやシミュレーター起動を行う。
* **Simulator（シミュレーター）**：Mac 上で iPhone/iPad を再現するアプリ。実機なしで動作確認できる。
* **ターゲット（Target）**：ビルドされる“製品”の単位。**iOSアプリ**のターゲットと、\*\*ライブラリ（Swift Package）\*\*のターゲットがある。
* **Team**：コード署名を行う Apple アカウントのこと。**アプリのターゲット**で設定する。**パッケージ（ライブラリ）には表示されない**。
* **Swift Package**：アプリから利用される再利用部品（ライブラリ）。`Package.swift` があるプロジェクトは**アプリではなくライブラリ**であることが多い。

> 重要：**Team が見つからない**ときは、“アプリ”ではなく**ライブラリのみを開いている**可能性が高い。後半でアプリの入れ物を作る。

---

## 1. 必要なものの確認（5分）

* **macOS 13 以降**の Mac（ストレージ空き 30GB 以上推奨）
* **Apple ID**（無料。App Store と Xcode サインインで使用）
* **安定したインターネット**（Xcode とシミュレーター画像のダウンロード用）

---

## 2. Xcode をインストール（10–20分）

1. Mac の **App Store** を開く → 検索欄に `Xcode` → **入手**。
2. 初回起動時に**ライセンス同意**と**追加コンポーネントのインストール**を許可。
3. **Xcode に Apple ID を追加**：

   * Xcode を起動 → **Settings…（旧Preferences…）** → **Accounts** → `+` → **Apple ID** を追加 → サインイン。

> 補足：後の“Team”選択でこの Apple ID が表示されるようになる。

---

## 3. （任意）コマンドラインツールを入れる（1分）

ターミナルを開いて実行。

```bash
xcode-select --install
```

---

## 4. GitHub からプロジェクトを取得（5分）

1. **ターミナル**を開く → 作業ディレクトリへ移動（例）

   ```bash
   cd ~/work
   ```
2. **クローン**（例）

   ```bash
   git clone https://github.com/example/MonoKnight.git
   cd MonoKnight
   ```

> すでにフォルダがある場合はこの章はスキップ可。

---

## 5. まずは `Package.swift` を Xcode で開いて中身を確認（2分）

1. Finder で `MonoKnight` フォルダを開く。
2. `Package.swift` を**ダブルクリック** → Xcode が起動して **Swift Package** として読み込まれる。
3. 左のナビゲータに **`Game`** などの**ライブラリ用ターゲット**が見えるはず。

> ここでは**アプリ（.app）ターゲットがない**ため、**Team の欄は表示されない**のが正常。次章で“アプリの入れ物”を作る。

---

## 6. “入れ物”となる iOS アプリを新規作成（5–10分）

> ライブラリ `Game` を組み込んで起動するための最小アプリを作る。

1. Xcode メニュー **File > New > Project…**
2. **iOS > App** を選択 → **Next**
3. 入力例：

   * **Product Name**：`MonoKnightApp`
   * **Team**：未選択でもOK（後で設定）
   * **Organization Identifier**：`com.koki` など（仮でOK）
   * **Interface**：SwiftUI / **Language**：Swift
4. 保存先は `MonoKnight` の**親フォルダ**（例：`~/work`）にするのが分かりやすい。

> 既にリポジトリに iOS アプリのターゲットが存在する場合は、この章の作成は不要。**プロジェクトナビゲータでアプリターゲットを選んで先へ**。

---

## 7. アプリにローカルのライブラリ `Game` を組み込む（5分）

### 方法A：ローカルパッケージとして追加（初心者におすすめ）

1. 左ペインの\*\*プロジェクト（青いアイコン）\*\*を選択 → 上部タブ **Package Dependencies**
2. 右下の `+` → **Add Local…**
3. `MonoKnight` フォルダ（`Package.swift` がある場所）を選択 → **Add Package**
4. 依存先のターゲットに **`Game`** を選択し、**アプリのターゲット**（`MonoKnightApp`）にリンクされるよう確認

### 方法B：同一ワークスペースに追加（中級）

* ワークスペース化している場合、`Game` を **Target Dependencies** に直接追加してもOK。

---

## 8. Team（コード署名）の設定（2分）

1. 左ペインで**プロジェクト名** → **Targets** → **`MonoKnightApp`** を選択。
2. **Signing & Capabilities** タブ → **Team** から自分の Apple ID を選ぶ。
3. **Bundle Identifier** は**一意**であること（例：`com.koki.monoknight.app`）。

> メモ：**シミュレーター実行は原則コード署名不要**だが、将来の実機テストやビルドのために設定しておくと良い。

---

## 9. アプリから `Game` を呼び出せるか最小確認（2分）

1. `MonoKnightApp` の `ContentView.swift` を開く。
2. 先頭に `import Game` を追加。
3. ビルドが通るか確認（赤エラーが出なければOK）。必要なら `Game` 側に `public` な型/関数があるか確認。

   * 例：`Text("Hello Game")` の下に、`let _ = /* Game の公開APIを軽く参照 */` のような1行を暫定で置いても良い。

---

## 10. シミュレーターを選んで起動（3分）

1. Xcode 左上の**スキーム**が **`MonoKnightApp`** になっていることを確認。
2. 右隣のデバイス選択から **iPhone 15** などを選ぶ（`iOS Simulator` セクション）。
3. **⌘R**（Run）でビルド＆起動。初回は少し時間がかかる。
4. 画面にアプリが起動すればゴール！

---

## 11. ユニットテストを走らせる（任意）

* Xcode：**Product > Test（⌘U）**
* ターミナル：

  ```bash
  swift test
  ```

> テストターゲットが `GameTests` 等として用意されている場合のみ。

---

## 12. すでに“アプリターゲット”がある場合のショートカット

1. Xcode で **.xcodeproj /.xcworkspace** を開く（あるいは既存のプロジェクトを開く）。
2. 左の **Targets** から既存の **iOS App** を選択。
3. **Signing & Capabilities > Team** を自分の Apple ID に設定。
4. スキームをそのアプリに切り替え → デバイス選択 → **⌘R**。

---

## 13. 困った時のチェックリスト

* **Team が出ない**：アプリのターゲットを選んでいるか？ `Package.swift`（ライブラリ）だけを開いていないか？
* **No such module 'Game'**：

  * `Package Dependencies` にローカル追加できている？
  * 追加先ターゲットが **`MonoKnightApp`** になっている？
* **Bundle Identifier 重複**：ユニークな文字列（例：`com.koki.monoknight.app`）へ変更。
* **ビルドが進まない/失敗**：

  * **Product > Clean Build Folder（⇧⌘K）**
  * Xcode 再起動
  * シミュレーターを **Device > Erase All Content and Settings…** で初期化
* **`Team` に Apple ID が出ない**：Xcode **Settings > Accounts** に Apple ID を追加したか？
* **スキームが `Game` のまま**：左上のスキームを\*\*アプリ名（MonoKnightApp）\*\*に切り替える。

---

## 14. よくある Q\&A

**Q. 実機（iPhone）で動かすには？**
A. 同じプロジェクトでデバイスを接続し、`Signing & Capabilities > Team` を設定。初回は**開発者モード**の有効化が必要。

**Q. VS Code は使わないの？**
A. Swift Package やドキュメント編集では使えるが、**シミュレーター実行は Xcode が必須**。

**Q. `swift test` はどこで使う？**
A. ライブラリ（`Game`）にユニットテストがある場合に、**ターミナルから自動実行**できる。

---

## 15. 片付け・再現のコツ

* この手順書どおりに作成した **`MonoKnightApp`** は「入れ物」です。リポジトリ側に正式なアプリターゲットが追加されたら、そちらへ移行してOK。
* 初回起動までに作った設定（Team、Bundle Identifier）は**メモ**しておくと再現が簡単。

---

### 完了の目安

* Xcode 左上で **`MonoKnightApp` + iPhone 15** を選択し、**⌘R** でシミュレーターが起動してアプリが表示される。

お疲れさまでした！起動できたら次は **UI を当てる／`Game` の API を呼ぶ画面を作る** など、MVP に向けて一歩進めましょう。

---

## 付録A：チーム開発で **個人設定をGitに含めない** 運用（`xcconfig` + `.gitignore`）

> 目的：Expo の `eas.json` のように**個人アカウント情報が衝突**する事態を回避。**共有設定**と**個人設定**を分離します。

### A-1. リポジトリ構成の指針（1リポジトリ=1アプリ）

```
MonoKnight/                 # GitHub 管理ルート
└─ MonoKnightApp/           # iOSアプリ本体
   ├─ MonoKnightApp.xcodeproj
   ├─ Config/
   │  ├─ Default.xcconfig          # 共有設定（追跡）
   │  └─ Local.xcconfig.sample     # 個人設定の雛形（追跡）
   ├─ Sources/
   └─ Info.plist
```

> 各メンバーは `Local.xcconfig.sample` を **Local.xcconfig にコピー**して使う（**Local.xcconfig は非追跡**）。

### A-2. `.gitignore`（ルートに配置）

```gitignore
# macOS
.DS_Store

# Xcode / Derived
DerivedData/
build/

# 個人の Xcode ユーザデータ（衝突の温床）
**/*.xcuserdatad/
**/*.xcuserdata/

# SwiftPM
.swiftpm/
.build/

# 個人設定ファイルは追跡しない
MonoKnightApp/Config/Local.xcconfig
```

> 既に `xcuserdata` がコミット済みなら：
>
> ```bash
> git rm -r --cached '**/*.xcuserdata' '**/*.xcuserdatad'
> git commit -m "remove user-specific xcode data"
> ```

### A-3. `Default.xcconfig`（共有設定）

`MonoKnightApp/Config/Default.xcconfig`

```xcconfig
// 共有してよいベース設定
PRODUCT_NAME = MonoKnight
PRODUCT_BUNDLE_IDENTIFIER = com.koki.monoknight$(BUNDLE_ID_SUFFIX)

// 個人設定（Team ID など）は Local.xcconfig で上書き
DEVELOPMENT_TEAM =
BUNDLE_ID_SUFFIX =

// 表示名などを変数化
APP_DISPLAY_NAME = $(PRODUCT_NAME)

// 個人設定があれば読み込む（無くてもエラーにならない）
#include? "Local.xcconfig"
```

### A-4. `Local.xcconfig.sample`（個人設定の雛形：追跡OK、実体は追跡しない）

`MonoKnightApp/Config/Local.xcconfig.sample`

```xcconfig
// このファイルを Local.xcconfig にコピーして編集（Local は .gitignore 済み）

// 各自の Apple Developer Team ID（例：ABCDE12345）
DEVELOPMENT_TEAM = YOUR_TEAM_ID

// バンドルIDの個人サフィックス（任意）
BUNDLE_ID_SUFFIX = .koki
```

> 実機ビルドが不要なら `DEVELOPMENT_TEAM` は空でもOK（シミュレーター実行は署名不要）。

### A-5. Xcode への紐づけ手順

1. ターゲット **MonoKnightApp** を選択 → **Build Settings** → **Base Configuration**（Debug/Release）を **`Config/Default.xcconfig`** に設定。
2. **Signing & Capabilities**：共有では固定しない。各自が実機ビルド時だけ `Local.xcconfig` に **`DEVELOPMENT_TEAM`** を記入して使用。
3. `PRODUCT_BUNDLE_IDENTIFIER` は `com.koki.monoknight$(BUNDLE_ID_SUFFIX)` 方式にしておくと、各自の `Local.xcconfig` で重複回避が可能。

### A-6. Info.plist の連携（任意）

* `Bundle display name` を `$(APP_DISPLAY_NAME)` に設定 → `Default.xcconfig` で一括管理。

### A-7. スキームの共有ポリシー

* 共有したいスキーム（例：`MonoKnightApp`）は **Manage Schemes… > Shared** にチェック（追跡OK）。
* 個人用スキームは Shared を外す（`.xcuserdata` に保存され、`.gitignore` 済み）。

### A-8. 運用フロー（初回以降）

1. 各メンバーは `Local.xcconfig.sample` をコピーして **`Local.xcconfig`** を作成（必要なら `DEVELOPMENT_TEAM` 設定）。
2. 左上スキーム：**MonoKnightApp**／デバイス：任意の iPhone シミュレーター。
3. **⌘R** で起動。実機ビルドが必要な人だけ署名を有効化。

> これで **個人アカウント設定が Git に混ざらず**、Expo の `eas.json` 的な「編集合戦」を回避できます。
