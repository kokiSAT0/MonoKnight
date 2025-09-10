# MonoKnight プロジェクト開発手順書（完全版）

## 目的

GitHub 上の **MonoKnight** リポジトリを Xcode
で開発・実行できるようにし、チームメンバー間で個人依存設定が衝突しない管理方法を確立する。

------------------------------------------------------------------------

## フォルダ構成（最終版）

    MonoKnight/
    ├─ MonoKnight.xcodeproj      # Xcode プロジェクト
    ├─ MonoKnightApp.swift       # アプリのエントリポイント
    ├─ Info.plist                # アプリ設定
    ├─ Package.swift             # SwiftPM 設定
    ├─ README.md                 # プロジェクト概要
    │
    ├─ Game/                     # ゲームロジック
    │   ├─ GameScene.swift
    │   ├─ GameCore.swift
    │   ├─ Deck.swift
    │   ├─ MoveCard.swift
    │   └─ Models.swift
    │
    ├─ UI/                       # 画面関連
    │   ├─ RootView.swift
    │   ├─ GameView.swift
    │   ├─ ResultView.swift
    │   └─ SettingsView.swift
    │
    ├─ Services/                 # プラットフォーム機能
    │   ├─ StoreService.swift
    │   ├─ AdsService.swift
    │   └─ GameCenterService.swift
    │
    ├─ Tests/                    # テストコード
    │   └─ ...
    │
    ├─ Config/
    │   ├─ Default.xcconfig
    │   └─ Local.xcconfig.sample
    │
    ├─ docs/                     # ドキュメント
    ├─ AGENTS.md
    └─ .gitignore

------------------------------------------------------------------------

## .gitignore（例）

``` gitignore
# macOS
.DS_Store

# Xcode ビルド生成物
DerivedData/
build/

# ユーザ固有の Xcode 設定
**/*.xcuserdata/
**/*.xcuserdatad/

# SwiftPM
.swiftpm/
.build/

# 個人設定ファイル
Config/Local.xcconfig
```

------------------------------------------------------------------------

## Config ファイル

### Default.xcconfig

``` xcconfig
PRODUCT_NAME = MonoKnight
PRODUCT_BUNDLE_IDENTIFIER = com.koki.monoknight$(BUNDLE_ID_SUFFIX)

DEVELOPMENT_TEAM =
BUNDLE_ID_SUFFIX =

APP_DISPLAY_NAME = $(PRODUCT_NAME)

#include? "Local.xcconfig"
```

### Local.xcconfig.sample

``` xcconfig
# このファイルを Local.xcconfig にコピーして使用
# Local.xcconfig は .gitignore 済み

DEVELOPMENT_TEAM = YOUR_TEAM_ID
BUNDLE_ID_SUFFIX = .koki
```

------------------------------------------------------------------------

## 運用ルール

-   **リポジトリは1つ（MonoKnight）**\
    → コード、UI、サービス、リソースをひとまとめ。
-   **個人依存を分離**\
    → `Local.xcconfig` は追跡しない。
-   **衝突しやすいファイルは無視**\
    → `.xcuserdata`, `DerivedData` はコミット禁止。
-   **共有したいスキームだけ Shared にする**\
-   **シミュレーター実行は署名不要**\
    → 実機を使う人だけ `Local.xcconfig` に `DEVELOPMENT_TEAM` を記載。

------------------------------------------------------------------------

## 開発フロー

1.  リポジトリを `git clone`。
2.  Xcode で `MonoKnight.xcodeproj` を開く。
3.  Config を設定：
    -   `Default.xcconfig` は共通\
    -   `Local.xcconfig.sample` をコピーして `Local.xcconfig`
        を作り、必要に応じて編集
4.  スキーム：`MonoKnight` を選択、デバイス：シミュレーター（例: iPhone
    15）。
5.  ⌘R で起動。

------------------------------------------------------------------------

## チェックリスト

-   [ ] `.gitignore` が正しいか？\
-   [ ] `Local.xcconfig` はコミットしていないか？\
-   [ ] スキームは Shared のみ共有されているか？\
-   [ ] シミュレーターで起動できるか？
