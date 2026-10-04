# サウンド実装と再生成

## 音源

作者の `Kurohyou3/bgm_creater` と `Kurohyou3/game_se_creater` の生成関数を直接利用した。外部楽曲、サンプル、MIDIは読み込んでいない。使用したソースのコミット、seed、設定、編集可能な音符情報、WAVのSHA-256は `audio/manifest.json` と `audio/*.song.json` に保存する。

| 場面 | 音源 |
| --- | --- |
| タイトル・塔選択 | `bgm_title.wav` |
| 基礎塔 | `bgm_tutorial.wav` |
| 成長塔 | `bgm_growth.wav` |
| 試練塔 | `bgm_trial.wav` |
| カード選択・行動確定 | `se_select.wav` / `se_move.wav` |
| カード拾得・遺物取得 | `se_pickup.wav` / `se_relic.wav` |
| 被ダメージ・HP回復 | `se_damage.wav` / `se_heal.wav` |
| フロアクリア・登頂・敗北 | `se_clear.wav` / `se_victory.wav` / `se_defeat.wav` |
| 無効な操作・施錠階段の警告 | `se_warning.wav` |

BGMは16小節、44.1kHz / 16bit / モノラルでループする。全音源の先頭・末尾は0、最大振幅はクリッピング上限未満にする。初期音量はBGM 35%、効果音65%。ユーザーは個別に無効化または音量変更できる。設定はUserDefaultsへ保存する。

## 責務と停止条件

- `Services/GameAudioService.swift`: AVAudioPlayer、音量、同時効果音4音まで、70ms以内の同種連打抑制、通話などの割り込み処理。
- `UI/GameAudioModifiers.swift`: 表示に反映されたHP・取得・結果の変化と画面遷移を観測する。Gameパッケージは音に依存しない。
- 音源は `MonoKnightApp/Audio` に置き、既存の同期グループ経由でアプリへ同梱する。ビルド時に生成しない。
- 消音スイッチを尊重するambientカテゴリを使用し、ほかの音楽を止めない。バックグラウンド再生権限は追加しない。
- 非アクティブ、バックグラウンド、ポーズ、広告、割り込みの停止理由を独立して管理する。一つの理由が解除されても別の停止理由が残れば再生しない。
- 広告SDKが音のカテゴリを変更した場合は、ゲーム音を再開する時点で消音を尊重するambientへ戻す。
- 結果画面ではBGMを止め、結果音だけを再生する。結果を再表示した場合にも結果音を出す。
- ヘッドホンが外れたら停止する。次のカード操作・行動確定・設定の試聴で再開する。
- 中断中の効果音は停止・破棄する。復帰時にまとめて再生しない。

## 再生成

Python環境にnumpyとscipyを用意し、記録されたコミットの作者アプリをチェックアウトして実行する。作者アプリのソース自体はこの公開リポジトリへコピーしない。

```bash
python3 Scripts/generate-audio.py --bgm-source /path/to/bgm_creater --se-source /path/to/game_se_creater
python3 Scripts/check-release-assets.py
```

音源追加・再生成後はmanifestも同時に更新し、同梱デコード・境界・停止条件・音量永続化テストを実行する。実機では消音スイッチ、Bluetooth/ヘッドホン抜去、着信、ロック、広告再生中の音を確認する。

## プライバシー

アプリ本体の `PrivacyInfo.xcprivacy` は、端末内の設定・進行保存をUserDefaultsの理由 `CA92.1`、連打抑制の経過時間測定をSystemBootTimeの理由 `35F9.1` として申告する。音やこの時刻値は送信しない。Google広告SDKの収集内容はSDK自身のマニフェストと別途合算して確認する。アプリ全体を「データ収集なし」としてストアへ回答しない。

理由コードは[Appleの説明](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)、SDKの収集項目は[Googleの開示資料](https://developers.google.com/admob/ios/privacy/data-disclosure)を参照した（2026年10月4日）。
