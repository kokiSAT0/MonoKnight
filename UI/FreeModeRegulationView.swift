import SwiftUI
import Game

/// フリーモードのレギュレーションを編集するためのビュー
/// - Note: Stepper や Picker を用いて、主要なパラメータを直感的に調整できるようにする
struct FreeModeRegulationView: View {
    /// 編集中のドラフト値
    @State private var draft: GameMode.Regulation
    /// 読み込み可能なプリセット一覧（スタンダードやクラシカルなど）
    private let presets: [GameMode]
    /// キャンセル操作時のハンドラ
    private let onCancel: () -> Void
    /// 保存操作時のハンドラ
    private let onSave: (GameMode.Regulation) -> Void

    /// スポーン方式を Picker で扱いやすくするための内部列挙体
    private enum SpawnOption: String, CaseIterable, Identifiable {
        case fixedCenter
        case chooseAny

        var id: String { rawValue }

        /// 表示名（日本語ラベル）
        var label: String {
            switch self {
            case .fixedCenter:
                return "中央固定"
            case .chooseAny:
                return "先読み後に任意選択"
            }
        }
    }

    /// カスタムイニシャライザでドラフト値とコールバックを受け取る
    /// - Parameters:
    ///   - initialRegulation: シート表示時点のレギュレーション
    ///   - presets: 読み込み可能なプリセット一覧
    ///   - onCancel: キャンセルボタン押下時に呼び出すクロージャ
    ///   - onSave: 保存ボタン押下時に呼び出すクロージャ
    init(
        initialRegulation: GameMode.Regulation,
        presets: [GameMode],
        onCancel: @escaping () -> Void,
        onSave: @escaping (GameMode.Regulation) -> Void
    ) {
        _draft = State(initialValue: initialRegulation)
        self.presets = presets
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        Form {
            presetSection
            boardSection
            handSection
            penaltySection
            previewSection
        }
        .navigationTitle("フリーモード設定")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("キャンセル") {
                    onCancel()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    onSave(draft)
                }
                .disabled(!isDraftValid)
            }
        }
        // 盤面サイズが変わった際に固定スポーンも中心へ更新し、矛盾を防ぐ
        .onChange(of: draft.boardSize) { _, newValue in
            if currentSpawnOption == .fixedCenter {
                draft.spawnRule = .fixed(GridPoint.center(of: newValue))
            }
        }
    }
}

private extension FreeModeRegulationView {
    /// プリセット読込セクション
    var presetSection: some View {
        Section {
            ForEach(presets) { mode in
                Button {
                    // 選択したプリセットの内容をドラフトへ反映
                    draft = mode.regulationSnapshot
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(mode.displayName)
                            .font(.headline)
                        Text(mode.primarySummaryText)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("プリセット読込")
        } footer: {
            Text("プリセットを読み込んでから個別の数値を微調整できます。")
        }
    }

    /// 盤面サイズや山札プリセットを調整するセクション
    var boardSection: some View {
        Section {
            Stepper(value: $draft.boardSize, in: 5...9, step: 1) {
                Text("盤面サイズ: \(draft.boardSize) × \(draft.boardSize)")
            }
            Picker("初期スポーン", selection: spawnOptionBinding) {
                ForEach(SpawnOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            Picker("山札構成", selection: $draft.deckPreset) {
                ForEach(GameDeckPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }
            Text(draft.deckPreset.summaryText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            Text("盤面と山札")
        } footer: {
            Text("盤面サイズを変更すると中央固定スポーンも自動的に中心へ移動します。")
        }
    }

    /// 手札スロットや先読み枚数を調整するセクション
    var handSection: some View {
        Section {
            Stepper(value: $draft.handSize, in: 1...7, step: 1) {
                Text("手札スロット: 最大 \(draft.handSize) 種類")
            }
            Stepper(value: $draft.nextPreviewCount, in: 0...5, step: 1) {
                Text("先読み表示: \(draft.nextPreviewCount) 枚")
            }
            Toggle(isOn: $draft.allowsStacking) {
                Text("同種カードのスタックを許可する")
            }
        } header: {
            Text("手札と先読み")
        } footer: {
            Text("スタックを無効にすると同じカードは別スロットを占有します。")
        }
    }

    /// ペナルティ関連の設定をまとめたセクション
    var penaltySection: some View {
        Section {
            Stepper(value: $draft.penalties.deadlockPenaltyCost, in: 0...10, step: 1) {
                Text("手詰まり自動ペナルティ: +\(draft.penalties.deadlockPenaltyCost)")
            }
            Stepper(value: $draft.penalties.manualRedrawPenaltyCost, in: 0...10, step: 1) {
                Text("手動引き直しペナルティ: +\(draft.penalties.manualRedrawPenaltyCost)")
            }
            Stepper(value: $draft.penalties.revisitPenaltyCost, in: 0...10, step: 1) {
                if draft.penalties.revisitPenaltyCost > 0 {
                    Text("再訪ペナルティ: +\(draft.penalties.revisitPenaltyCost)")
                } else {
                    Text("再訪ペナルティなし")
                }
            }
        } header: {
            Text("ペナルティ")
        } footer: {
            Text("0 を指定すると該当ペナルティは無効になります。")
        }
    }

    /// 現在のドラフト設定がどのようなモードかを簡易表示するセクション
    var previewSection: some View {
        Section {
            let previewMode = GameMode(identifier: .freeCustom, displayName: "フリーモード", regulation: draft)
            VStack(alignment: .leading, spacing: 6) {
                Text(previewMode.primarySummaryText)
                Text(previewMode.secondarySummaryText)
                Text(previewMode.stackingRuleDetailText)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } header: {
            Text("サマリー")
        }
    }

    /// 現在のスポーン設定を Picker 用のオプションへ変換する
    /// Picker の現在値を内部のスポーン設定へ変換した結果を返す
    private var currentSpawnOption: SpawnOption {
        switch draft.spawnRule {
        case .fixed:
            return .fixedCenter
        case .chooseAnyAfterPreview:
            return .chooseAny
        }
    }

    /// Picker と `draft.spawnRule` を結び付けるバインディング
    private var spawnOptionBinding: Binding<SpawnOption> {
        Binding {
            currentSpawnOption
        } set: { newValue in
            switch newValue {
            case .fixedCenter:
                draft.spawnRule = .fixed(GridPoint.center(of: draft.boardSize))
            case .chooseAny:
                draft.spawnRule = .chooseAnyAfterPreview
            }
        }
    }

    /// 入力されたドラフト値が妥当かどうかを簡易判定する
    var isDraftValid: Bool {
        draft.boardSize >= 3 && draft.handSize >= 1
    }
}
