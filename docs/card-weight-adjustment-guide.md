# カード重み調整ガイド

本ガイドは `Game/Deck.swift` に定義されている重み付き山札の調整手順をまとめたものです。初期状態では全カードが同一重み（1）で扱われますが、デッキごとに `WeightProfile` を用いることで特定カードだけを強調・抑制できます。

## 1. 重みプロファイルの基本構造

- `Deck.WeightProfile`
  - `defaultWeight`: 全カードへ適用する基礎重み。初期値は 1。
  - `overrides`: 特定カードだけ重みを上書きしたい場合に使用する辞書（`[MoveCard: Int]`）。
- `Deck.Configuration`
  - `weightProfile` プロパティから重みプロファイルを参照します。
  - デッキの `allowedMoves` と組み合わせて、抽選対象と重みの両方を管理します。

> **メモ:** 重みは自然数で管理されます。抽選時は重みに比例して当選確率が変動するため、`defaultWeight` を 1 に保ったまま強調したいカードへ `overrides` で加算する運用が推奨です。

## 2. プロファイル調整の手順

1. **対象デッキの特定**
   - `Deck.Configuration` に必要なデッキが定義済みか確認します。
   - 新規デッキを追加する場合は `allowedMoves` を含めた構成を先に確定させます。
2. **重み上書きの設定**
   - 既存デッキを調整する場合は、`Configuration` の初期化ブロックで `WeightProfile(defaultWeight: 1, overrides: [...])` を設定します。
   - 例: 王将型カードの排出率を 2 倍にしたい場合
     ```swift
     // overrides の例（コメントも日本語で統一する）
     let overrides: [MoveCard: Int] = [
         .kingUp: 2,      // 王将上方向を 2 倍に設定
         .kingRight: 2    // 王将右方向を 2 倍に設定
     ]
     let profile = Deck.WeightProfile(defaultWeight: 1, overrides: overrides)
     ```
3. **コードの整合性確認**
   - 調整後は `Deck.Configuration` が想定通りのカード集合と重みを提供しているか、ユニットテストで検証します。
   - `Tests/GameTests/DeckTests.swift` を参考に、必要なアサーションを追加してください。

## 3. テスト観点

- `swift test` を実行し、全テストが成功すること。
- 重み調整に伴う新規テストでは、以下を最低限確認します。
  - `allowedMoves` に対象カードが含まれていること。
  - `weightProfile.weight(for:)` で期待する重みが取得できること。
  - 重み変更によって既存デッキの均一性が崩れていないか（必要であれば別テストで確認）。
- 乱数挙動を確認したい場合は `Deck.makeTestDeck` を活用し、固定シーケンスでの挙動検証を行います。

## 4. リリース前のチェックポイント

- バランス調整の理由を `docs/` 配下の設計資料へ記録し、意図を共有する。
- UI やヘルプテキストでデッキ特徴を説明する場合は、`Configuration.deckSummaryText` の更新を忘れない。
- 重み変更に伴うゲームプレイへの影響を QA で確認し、必要に応じてプレイテストの結果を記録する。

以上の手順を踏むことで、デッキ単位の重み調整を安全に行えます。必要な変更は必ずテストとドキュメントで裏付けてからリリースフローへ進めてください。
