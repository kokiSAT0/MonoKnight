# MonoKnight Release Checklist

本書は MonoKnight を TestFlight と App Store 提出へ進める前の確認項目を整理したチェックリストである。`docs/agents_legacy.md` のリリース前チェック項目を土台に、カテゴリ別に読みやすく再編している。

## 1. 前提

- 正式リリース前に TestFlight で通し QA を行う
- シミュレーター確認だけで終えず、必要な項目は実機で確認する
- 仕様や同意フローを変更した場合は関連 docs も同じタイミングで更新する

## 2. ゲーム仕様

- [ ] 1 プレイを最後まで完走できる
- [ ] 盤外カードが選択不可として正しく薄表示される
- [ ] ペナルティ挙動が仕様通りである
- [ ] 手詰まり時に `+3 手` と全引き直しが発生する
- [ ] 任意の引き直しで `+2 手` が発生する
- [ ] リザルト画面のスコアが仕様通りに計算される

## 3. Game Center

- [ ] ランキングにスコアが送信される
- [ ] リーダーボード導線が機能する
- [ ] 送信対象スコアが `手数 × 10 + 所要秒数` と一致する

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
- [ ] カード方向、使用可否、残り踏破数が読み上げ可能である
- [ ] iPhone / iPad の両方で UI 崩れがない

## 7. 安定性

- [ ] クラッシュフリーを Xcode Organizer などで確認した
- [ ] 実機の TestFlight で重大な表示崩れや進行不能がない

## 8. 設定ファイル

- [ ] `NSUserTrackingUsageDescription` を確認した
- [ ] `SKAdNetworkItems` を最新 ID で確認した
- [ ] 本番向けの `Info.plist` / `.xcconfig` 値を Xcode 上で最終確認した

詳細なキー管理は [info-plist-guidelines.md](info-plist-guidelines.md) を参照する。

## 9. App Store 提出前

- [ ] App Store 審査メタデータを更新した
- [ ] Privacy / Ads 説明が実装内容と一致している
- [ ] リリース時点の external service ID が本番値と一致している

## 10. 関連ドキュメント

- プロダクト仕様: [product-spec.md](product-spec.md)
- 外部連携: [integrations.md](integrations.md)
- Info.plist 運用: [info-plist-guidelines.md](info-plist-guidelines.md)
