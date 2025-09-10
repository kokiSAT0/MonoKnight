# MonoKnight プロジェクト開発手順書（完全版）

## 目的

GitHub 上の **MonoKnight** リポジトリを Xcode
で開発・実行できるようにし、チームメンバー間で個人依存設定が衝突しない管理方法を確立する。

> **方針**：iOS アプリ用の Xcode プロジェクトはリポジトリ内（`MonoKnight/MonoKnightApp`）に配置し、個人設定ファイルは `.gitignore` で除外する。

------------------------------------------------------------------------

## フォルダ構成（最終版）

    MonoKnight/
    ├─ Game/                       # ルール・山札などのライブラリ
    ├─ UI/                         # 画面表示用コンポーネント
    ├─ Services/                   # 課金・広告・GameCenter
    ├─ Resources/                  # 画像や文字列
    └─ MonoKnightApp/              # iOS アプリ本体（Xcode プロジェクト）
        ├─ MonoKnightApp.xcodeproj
        ├─ Sources/
        │   └─ MonoKnightApp.swift # エントリポイント
        ├─ Config/
        │   ├─ Default.xcconfig
        │   └─ Local.xcconfig.sample
        └─ Info.plist

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
MonoKnightApp/Config/Local.xcconfig
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
    → `MonoKnightApp/Config/Local.xcconfig` は追跡しない。
-   **衝突しやすいファイルは無視**\
    → `.xcuserdata`, `DerivedData` はコミット禁止。
-   **共有したいスキームだけ Shared にする**\
-   **シミュレーター実行は署名不要**\
    → 実機を使う人だけ `Local.xcconfig` に `DEVELOPMENT_TEAM` を記載。

------------------------------------------------------------------------

## 開発フロー

1.  リポジトリを `git clone`。
2.  Xcode で `MonoKnightApp/MonoKnightApp.xcodeproj` を開く。
3.  Config を設定：
    -   `MonoKnightApp/Config/Default.xcconfig` は共通\
    -   `MonoKnightApp/Config/Local.xcconfig.sample` をコピーして `Local.xcconfig`
        を作り、必要に応じて編集
4.  スキーム：`MonoKnight` を選択、デバイス：シミュレーター（例: iPhone
    15）。
5.  ⌘R で起動。

------------------------------------------------------------------------

## チェックリスト

-   [ ] `.gitignore` が正しいか？\
-   [ ] `MonoKnightApp/Config/Local.xcconfig` はコミットしていないか？\
-   [ ] スキームは Shared のみ共有されているか？\
-   [ ] シミュレーターで起動できるか？
