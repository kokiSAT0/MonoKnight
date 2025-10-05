# GameMode パラメータ仕様

MonoKnight の各モードは `GameMode` 構造体を通じて盤面サイズやペナルティ設定などをまとめて定義している。本ドキュメントでは、`GameMode.Regulation` が保持するパラメータ群と、フリーモード（ユーザーカスタム）との整合性要件を整理する。

## 1. `GameMode.Regulation` のフィールド一覧

| 項目 | 型 | 役割 | メモ |
|------|----|------|------|
| `boardSize` | `Int` | 盤面の一辺の長さ。盤面は常に正方形となる。 | 既定値は 5。`BoardGeometry` と連携して初期スポーン座標を算出する。 |
| `handSize` | `Int` | 手札スロットの最大種類数。カードの枚数ではなく種類数で管理する。 | `allowsStacking` が `true` の場合、同種カードは 1 スロット内に積み重なる。 |
| `nextPreviewCount` | `Int` | 先読みで画面下部に表示するカード枚数。 | UI での先読みスロット数と一致している必要がある。 |
| `allowsStacking` | `Bool` | 同種カードを同じスロットに積み重ねられるか。 | `false` の場合、同一カードでも別スロットを消費する。 |
| `deckPreset` | `GameDeckPreset` | 利用する山札構成プリセット。 | `Deck.Configuration` と 1 対 1 で対応し、UI の説明文でも利用される。 |
| `spawnRule` | `GameMode.SpawnRule` | 初期スポーンの扱い。中央固定 or 任意選択を切り替える。 | `chooseAnyAfterPreview` の場合は初手で任意マスを選んで開始。 |
| `penalties` | `GameMode.PenaltySettings` | 手詰まり/再訪などのペナルティ設定一式。 | 個別のフィールド詳細は後述。 |

### 1-1. `PenaltySettings`

| 項目 | 型 | 役割 | メモ |
|------|----|------|------|
| `deadlockPenaltyCost` | `Int` | 手札 5 種類すべてが使用不可となった際の自動ペナルティ。 | 既定値は +3 手。 |
| `manualRedrawPenaltyCost` | `Int` | プレイヤーが任意に引き直しを実行した際に加算される手数。 | 既定値は +2 手。 |
| `manualDiscardPenaltyCost` | `Int` | 任意のカード 1 種を捨て札にする操作時のペナルティ。 | 既定値は +1 手。 |
| `revisitPenaltyCost` | `Int` | 既踏マスへ再訪した際に加算される手数。 | 既定値は 0 手（スタンダードの場合）。 |

## 2. ビルトインモードの定義

| モード | `identifier` | 主な設定 | 備考 |
|--------|--------------|----------|------|
| スタンダード | `.standard5x5` | `boardSize=5`, `spawnRule=.fixed(中央)`, `deckPreset=.standard`, `deadlockPenaltyCost=3` など | 初期スポーンは常に中央。フリーモード初期値としても利用。 |
| クラシカルチャレンジ | `.classicalChallenge` | `boardSize=8`, `spawnRule=.chooseAnyAfterPreview`, `deckPreset=.classicalChallenge`, `deadlockPenaltyCost=2` など | 盤面が 8×8 に拡張され、桂馬カードのみで構成される。 |

## 3. フリーモードとの整合性要件

フリーモード (`GameMode.Identifier.freeCustom`) はユーザーがカスタマイズした `GameMode.Regulation` を `UserDefaults` に保存し、必要に応じて `GameMode` を再構築して利用する。実装上のチェックポイントは次の通り。

1. **既定値の整合性**: 保存データが存在しない場合は `GameMode.standard.regulationSnapshot` を初期値とし、ビルトインモードと同じ挙動になること。特にペナルティは `deadlock=+3` / `manualRedraw=+2` / `manualDiscard=+1` / `revisit=0` を初期値として共有する。
2. **シリアライズ互換性**: `GameMode.Regulation` / `PenaltySettings` / `SpawnRule` は `Codable` であり、`FreeModeRegulationStore` での JSON 保存・読み込みが破綻しないこと。
3. **GameMode の識別子運用**: フリーモードとして生成した `GameMode` は常に `.freeCustom` を識別子とし、`regulationSnapshot` の内容で差分を判定できること。
4. **プリセット適用時の同期**: `applyPreset(from:)` でビルトインモードの `regulationSnapshot` を適用することで、ユーザーがいつでも既定モードへ戻せること。

## 4. 自動テスト方針

- `MonoKnightAppTests/FreeModeRegulationStoreTests.swift` にて、以下を検証する。
  - 保存データが無い状態で `FreeModeRegulationStore` を初期化すると、フリーモードのレギュレーションがスタンダードモードと一致する。
  - カスタム設定へ更新すると、`UserDefaults` に永続化され、再生成時も同じ設定が復元される。
  - プリセット適用が `GameMode.standard` などビルトインモードと一致すること。
- これらにより、`GameMode` のパラメータ仕様とフリーモードの挙動が乖離しないことを継続的に保証する。

---

本ドキュメントはモード定義を変更する際のチェックリストとして活用し、値追加や仕様変更時には必ず更新すること。
