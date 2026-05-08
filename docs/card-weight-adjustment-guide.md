# 塔カード候補調整ガイド

MonoKnight の現行メインコンテンツは塔ダンジョンのみである。
カードの出現調整は、旧山札の重み付き抽選ではなく、塔フロアごとの拾得カードとクリア報酬カードの候補を調整して行う。

## 1. 正本

- 塔の定義は `Game/DungeonDefinition.swift` を正本とする。
- 通常プレイで選べる塔は `tutorial-tower`、`growth-tower`、`rogue-tower` の3本のみとする。
- フロア内の拾得カードは `DungeonFloorDefinition.cardPickups` で定義する。
- フロアクリア後の移動カード報酬は `rewardMoveCardsAfterClear` で定義する。
- フロアクリア後の補助カード報酬は `rewardSupportCardsAfterClear` で定義する。

## 2. 候補変化の仕組み

塔の拾得/報酬カードは、同じフロア構成を保ちながらカード候補だけを軽く変化させられる。

- `DungeonDefinition.resolvedPickups` はフロア内の拾得カード候補を解決する。
- `DungeonDefinition.resolvedRewardCards` はクリア報酬カード候補を解決する。
- `variedCards` と `cardAlternatives` は、基準カードから置き換え候補を選ぶ。
- `DungeonRunState.cardVariationSeed` により、同じラン内では候補変化が安定する。

この仕組みは「排出率」そのものではなく、塔フロアに置くカード候補の揺らぎを作るためのものと考える。

## 3. 配置調整

拾得カードの置き場所は `pickupPositions` と `safePickupPoints` を使う。

- 出口、開始地点、障害物、敵、罠、回復マスなどと競合しない位置を選ぶ。
- フロアの主要ギミックを壊す位置には置かない。
- 序盤は基本移動を補うカードを近めに置き、中盤以降はリスクを取る導線に報酬カードを置く。

## 4. `Deck.Configuration` の扱い

`Deck.Configuration` は塔本編のカード排出率の正本ではない。
現在残す用途は次の最小範囲に限る。

- 塔外の補助的なカード候補セット。
- テスト用の固定ドロー。
- 旧手札/NEXT処理が必要な検証の互換支援。

新しい塔カードの出現調整は、まず `DungeonDefinition.swift` のフロア定義側へ入れる。

## 5. テスト観点

- `swift test` を実行し、Game パッケージ全体が成功すること。
- `DungeonModeTests` で通常ライブラリが3塔のみを返すことを確認する。
- `patrol-tower`、`key-door-tower`、`warp-tower`、`trap-tower` が取得できないことを確認する。
- フロア内の拾得カード、報酬カード、所持カードの使用回数が塔の進行で破綻しないことを確認する。
- 旧モード名、旧目的地制、旧デッキプリセットの文言が通常 UI と docs に戻っていないことを検索で確認する。
