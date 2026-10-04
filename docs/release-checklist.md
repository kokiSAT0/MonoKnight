# MonoKnight Release Checklist

本書は MonoKnight を TestFlight と App Store 提出へ進める前の確認項目を整理したチェックリストである。
仕様判断は [`product-spec.md`](product-spec.md) と [`game-rules-handbook.md`](game-rules-handbook.md) を優先する。

## 1. 前提

- 正式リリース前に TestFlight で通し QA を行う
- シミュレーター確認だけで終えず、必要な項目は実機で確認する
- 仕様や同意フローを変更した場合は関連 docs も同じタイミングで更新する
- 内部テスター向けの初回配布手順は [`testflight-internal-distribution.md`](testflight-internal-distribution.md) を参照する

## 1.1 内部 TestFlight 配布準備

- [x] ローカルの `MonoKnight` scheme 実効値が Bundle ID `com.kokisato.MonoKnightApp` / Version `1.0` / Build `1` / Team `5TAKV37ZM4` / Automatic signing と一致している
- [x] 署名なしの Release iPhoneOS build が成功している
- [ ] App Store Connect の Bundle ID が `com.kokisato.MonoKnightApp` と一致している
- [ ] Xcode Organizer で `MonoKnight` scheme の Archive を作成できる
- [ ] TestFlight の Beta App Description / What to Test / Feedback Email を入力した
- [ ] 内部テスターグループを作成し、対象ビルドを追加した
- [ ] 内部テスターの端末で TestFlight からインストールできる

## 2. ゲーム仕様

- [ ] タイトルの通常プレイ導線が塔ダンジョンのみになっている
- [ ] タイトルから塔選択を開き、各塔を1Fから開始できる
- [ ] 塔フロア開始時は塔名と階数だけの短い開始演出が出て、自動またはタップで盤面へ移る
- [ ] ハイスコア、デイリーチャレンジ、Target Lab、クラシカル、旧目的地制キャンペーンが通常導線や設定/リザルトから出ていない
- [ ] 削除済み旧コンテンツの保存データ移行や互換 UI が新規に復活していない
- [ ] 塔ダンジョンで 1 ランを最後まで完走、または失敗から再挑戦できる
- [ ] フロア出口へ到達すると次フロアへ進む
- [ ] HP 0 で失敗になり、残り手数 0 後は上限超過1手目と以後3手ごとに疲労ダメージを受ける
- [ ] 失敗リザルトから「盤面を見る」で敗因確認用の盤面へ戻れ、結果へ戻る/ホームへ戻る導線が使える
- [ ] フロア間で HP と所持カード残り回数だけが引き継がれる
- [ ] 拾得カードはクリア時に未使用分が残っていれば、残り回数つきで次フロアへ自動持ち越しされる
- [ ] 基本移動が許可された塔では上下左右1マス移動がカードを消費せず、1手として処理される
- [ ] 敵の危険範囲、床ギミック、出口表示が実際の判定と一致している
- [ ] レイ型など移動途中も踏むカードでは、踏むマス全体が薄い水色塗り、タップ可能な終点だけが水色枠で表示される
- [ ] 盤外・障害物などで使えないカードが正しく選択不可になる

## 3. Game Center

- [ ] Game Center 導線が通常プレイ導線として露出していない
- [ ] 旧モード用 leaderboard ID が Info.plist / xcconfig に残っていない
- [ ] 現行塔プレイから Game Center の自動サインイン促しやスコア送信が発生しない

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
- [ ] カード方向、使用可否、残りHP/手数が読み上げ可能である
- [ ] iPhone / iPad Portrait の両方でタイトル、塔選択、ゲーム中、リザルトに UI 崩れがない

## 7. 安定性

- [ ] クラッシュフリーを Xcode Organizer などで確認した
- [ ] 実機の TestFlight で重大な表示崩れや進行不能がない

## 8. 設定ファイル

- [x] 生成済み Release app の `NSUserTrackingUsageDescription` を確認した
- [x] 生成済み Release app の `SKAdNetworkItems` が空でないことを確認した
- [x] 本番向けの `Info.plist` / `.xcconfig` 実効値をローカル Release build で確認した
- [ ] App Store Connect / AdMob 側の本番 ID と一致していることを手動確認した

詳細なキー管理は [`info-plist-guidelines.md`](info-plist-guidelines.md) を参照する。

## 9. App Store 提出前

- [ ] App Store 審査メタデータを更新した
- [ ] Privacy / Ads 説明が実装内容と一致している
- [ ] リリース時点の external service ID が本番値と一致している

## 9.1 サウンド追加後の確認

2026年10月4日のローカル検証と実機検証は区別する。提出原稿は [`store-submission-draft.md`](store-submission-draft.md)、音源仕様は [`audio-integration.md`](audio-integration.md) を参照する。

- [x] BGM4曲・効果音10点を作者の生成アプリから作成し、生成条件とSHA-256を記録した
- [x] 同梱音源のデコード・波形端点・クリッピング・音量保存・複数停止条件のテストが通った
- [x] iPhoneシミュレーターで音設定、基礎塔開始、ポーズ/再開、プライバシー説明を操作確認した
- [x] iPadシミュレーターでも同じ操作と縦画面の表示を確認した
- [x] アプリ本体とGoogle SDKのPrivacyInfo.xcprivacyがビルド済みアプリに含まれる
- [x] 音源追加後の署名なしRelease Archiveを作成し、同梱リソースと提出用設定を確認した
- [x] ストア説明文、TestFlightの確認事項、プライバシー原稿を作成した
- [ ] 実機で消音、Bluetooth/ヘッドホン抜去、着信、ロック、広告中の音を確認した
- [ ] 公開サポートページとプライバシーポリシーURLを確定し、問い合わせ窓口を入力した
- [ ] 本番広告IDを設定し、静的確認スクリプトの `--strict` が合格した
- [ ] 本番サービスの同意・広告・購入・復元と配布署名を実機/TestFlightで確認した

## 10. 関連ドキュメント

- プロダクト仕様: [`product-spec.md`](product-spec.md)
- ゲームルール詳細: [`game-rules-handbook.md`](game-rules-handbook.md)
- 外部連携: [`integrations.md`](integrations.md)
- Info.plist 運用: [`info-plist-guidelines.md`](info-plist-guidelines.md)
