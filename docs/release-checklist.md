# MonoKnight Release Checklist

本書は MonoKnight を TestFlight と App Store 提出へ進める前の確認項目を整理したチェックリストである。
仕様判断は [`product-spec.md`](product-spec.md) と [`game-rules-handbook.md`](game-rules-handbook.md) を優先する。

## 1. 前提

- 正式リリース前に TestFlight で通し QA を行う
- シミュレーター確認だけで終えず、必要な項目は実機で確認する
- 仕様や同意フローを変更した場合は関連 docs も同じタイミングで更新する

## 2. ゲーム仕様

- [ ] スタンダードモードで 1 プレイを最後まで完走できる
- [ ] 目的地を 12 個獲得するとクリアになる
- [ ] 表示中の3目的地をどれから踏んでも `capturedTargetCount` が増え、新しい目的地が補充される
- [ ] 盤外・障害物などで使えないカードが正しく選択不可になる
- [ ] フォーカスで手札と先読みが表示中の目的地寄りに再配布される
- [ ] フォーカス使用時に手数は増えず、フォーカス回数が増える
- [ ] 目的地制の手詰まり時に、手数ペナルティではなく自動再配布で回復する
- [ ] リザルト画面のスコアが `移動手数 × 10 + 所要秒数 + フォーカス回数 × 15` と一致する
- [ ] キャンペーンは通常クリアで次ステージ・次章が解放され、スター不足で新章が止まらない
- [ ] キャンペーン内で実験場の全カード群と全特殊マスを最低1回ずつ確認できる
- [ ] キャンペーンの星2/星3条件が進行必須ではなく、やり込み目標として表示・記録される

## 3. Game Center

- [ ] スタンダードモードのクリア時にランキングへスコアが送信される
- [ ] リーダーボード導線が機能する
- [ ] 送信対象スコアがリザルト画面のスコアと一致する
- [ ] `GameMode.targetLab` などランキング対象外モードでは送信されない

## 4. 広告と IAP

- [ ] 広告はゲーム外のみ表示される
- [ ] 広告は結果画面でのみ表示される
- [ ] 短時間で連続表示されない
- [ ] `remove_ads_mk` 購入後に広告が完全に消える
- [ ] 購入後は広告の表示だけでなくロードも停止する
- [ ] 設定画面から購入の復元が成功する

## 5. プライバシー同意

- [ ] 初回起動フローで「説明 → ATT → UMP」が表示される
- [ ] 同意結果に応じてパーソナライズ広告と NPA が切り替わる
- [ ] 設定から UMP の Privacy Options を再表示できる
- [ ] ATT / UMP の主要状態パターンを QA で確認した

## 6. アクセシビリティ

- [ ] VoiceOver ラベルが主要 UI で成立している
- [ ] カード方向、使用可否、残り目的地数が読み上げ可能である
- [ ] iPhone / iPad の両方で UI 崩れがない

## 7. 安定性

- [ ] クラッシュフリーを Xcode Organizer などで確認した
- [ ] 実機の TestFlight で重大な表示崩れや進行不能がない

## 8. 設定ファイル

- [ ] `NSUserTrackingUsageDescription` を確認した
- [ ] `SKAdNetworkItems` を最新 ID で確認した
- [ ] 本番向けの `Info.plist` / `.xcconfig` 値を Xcode 上で最終確認した

詳細なキー管理は [`info-plist-guidelines.md`](info-plist-guidelines.md) を参照する。

## 9. App Store 提出前

- [ ] App Store 審査メタデータを更新した
- [ ] Privacy / Ads 説明が実装内容と一致している
- [ ] リリース時点の external service ID が本番値と一致している

## 10. 関連ドキュメント

- プロダクト仕様: [`product-spec.md`](product-spec.md)
- ゲームルール詳細: [`game-rules-handbook.md`](game-rules-handbook.md)
- 外部連携: [`integrations.md`](integrations.md)
- Info.plist 運用: [`info-plist-guidelines.md`](info-plist-guidelines.md)
