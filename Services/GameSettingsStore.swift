import AVFoundation
import Foundation
import Game
import SwiftUI

/// アプリ全体で共有するユーザー設定を読み書きするストア
/// - Note: UI 層が `@AppStorage` へ直接依存しないようにし、設定の参照経路を 1 箇所へ集約する。
@MainActor
final class GameSettingsStore: ObservableObject {
    /// 設定の永続化先
    private let userDefaults: UserDefaults

    /// テーマ設定
    @Published var preferredColorScheme: ThemePreference {
        didSet {
            guard oldValue != preferredColorScheme else { return }
            userDefaults.set(
                preferredColorScheme.rawValue,
                forKey: StorageKey.AppStorage.preferredColorScheme
            )
        }
    }

    /// ハプティクス設定
    @Published var hapticsEnabled: Bool {
        didSet {
            guard oldValue != hapticsEnabled else { return }
            userDefaults.set(hapticsEnabled, forKey: StorageKey.AppStorage.hapticsEnabled)
        }
    }

    /// BGMの再生設定。
    @Published var bgmEnabled: Bool {
        didSet {
            guard oldValue != bgmEnabled else { return }
            userDefaults.set(bgmEnabled, forKey: StorageKey.AppStorage.bgmEnabled)
            syncAudioSettings()
        }
    }

    /// 効果音の再生設定。
    @Published var soundEffectsEnabled: Bool {
        didSet {
            guard oldValue != soundEffectsEnabled else { return }
            userDefaults.set(soundEffectsEnabled, forKey: StorageKey.AppStorage.soundEffectsEnabled)
            syncAudioSettings()
        }
    }

    /// BGM音量。0から1で保持する。
    @Published var bgmVolume: Double {
        didSet {
            bgmVolume = min(max(bgmVolume, 0), 1)
            guard oldValue != bgmVolume else { return }
            userDefaults.set(bgmVolume, forKey: StorageKey.AppStorage.bgmVolume)
            syncAudioSettings()
        }
    }

    /// 効果音音量。0から1で保持する。
    @Published var soundEffectsVolume: Double {
        didSet {
            soundEffectsVolume = min(max(soundEffectsVolume, 0), 1)
            guard oldValue != soundEffectsVolume else { return }
            userDefaults.set(soundEffectsVolume, forKey: StorageKey.AppStorage.soundEffectsVolume)
            syncAudioSettings()
        }
    }

    /// 盤面ガイド表示設定
    @Published var guideModeEnabled: Bool {
        didSet {
            guard oldValue != guideModeEnabled else { return }
            userDefaults.set(guideModeEnabled, forKey: StorageKey.AppStorage.guideModeEnabled)
        }
    }

    /// 開発者向けに遊び方辞典の未発見項目もすべて表示する設定
    @Published var showsAllEncyclopediaEntriesForDeveloper: Bool {
        didSet {
            guard oldValue != showsAllEncyclopediaEntriesForDeveloper else { return }
            userDefaults.set(
                showsAllEncyclopediaEntriesForDeveloper,
                forKey: StorageKey.AppStorage.showsAllEncyclopediaEntriesForDeveloper
            )
        }
    }

    /// 開発者向けに跳躍騎士を未解放でも選べるようにする設定
    @Published var unlocksKnightMovementStyleForDeveloper: Bool {
        didSet {
            guard oldValue != unlocksKnightMovementStyleForDeveloper else { return }
            userDefaults.set(
                unlocksKnightMovementStyleForDeveloper,
                forKey: StorageKey.AppStorage.unlocksKnightMovementStyleForDeveloper
            )
        }
    }

    /// 開発者向けに通常遺物と呪い遺物の効果だけを無効化する設定
    @Published var disablesDungeonRelicEffectsForDeveloper: Bool {
        didSet {
            guard oldValue != disablesDungeonRelicEffectsForDeveloper else { return }
            userDefaults.set(
                disablesDungeonRelicEffectsForDeveloper,
                forKey: StorageKey.AppStorage.disablesDungeonRelicEffectsForDeveloper
            )
        }
    }

    /// 開発者向けに検証中の星図測量塔テーマを有効化する設定
    @Published var usesStarChartSurveyTowerTheme: Bool {
        didSet {
            guard oldValue != usesStarChartSurveyTowerTheme else { return }
            userDefaults.set(
                usesStarChartSurveyTowerTheme,
                forKey: StorageKey.AppStorage.usesStarChartSurveyTowerTheme
            )
        }
    }

    var appThemeVisualStyle: AppThemeVisualStyle {
        usesStarChartSurveyTowerTheme ? .starChartSurveyTower : .classic
    }

    /// 手札並び順設定
    @Published var handOrderingStrategy: HandOrderingStrategy {
        didSet {
            guard oldValue != handOrderingStrategy else { return }
            userDefaults.set(handOrderingStrategy.rawValue, forKey: HandOrderingStrategy.storageKey)
        }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.preferredColorScheme =
            ThemePreference(
                rawValue: userDefaults.string(forKey: StorageKey.AppStorage.preferredColorScheme)
                    ?? ThemePreference.system.rawValue
            ) ?? .system
        self.hapticsEnabled =
            userDefaults.object(forKey: StorageKey.AppStorage.hapticsEnabled) as? Bool ?? true
        self.bgmEnabled =
            userDefaults.object(forKey: StorageKey.AppStorage.bgmEnabled) as? Bool ?? true
        self.soundEffectsEnabled =
            userDefaults.object(forKey: StorageKey.AppStorage.soundEffectsEnabled) as? Bool ?? true
        self.bgmVolume = userDefaults.object(forKey: StorageKey.AppStorage.bgmVolume) == nil
            ? 0.42
            : userDefaults.double(forKey: StorageKey.AppStorage.bgmVolume)
        self.soundEffectsVolume = userDefaults.object(forKey: StorageKey.AppStorage.soundEffectsVolume) == nil
            ? 0.68
            : userDefaults.double(forKey: StorageKey.AppStorage.soundEffectsVolume)
        self.guideModeEnabled =
            userDefaults.object(forKey: StorageKey.AppStorage.guideModeEnabled) as? Bool ?? true
        self.showsAllEncyclopediaEntriesForDeveloper =
            userDefaults.object(forKey: StorageKey.AppStorage.showsAllEncyclopediaEntriesForDeveloper) as? Bool ?? false
        self.unlocksKnightMovementStyleForDeveloper =
            userDefaults.object(forKey: StorageKey.AppStorage.unlocksKnightMovementStyleForDeveloper) as? Bool ?? false
        self.disablesDungeonRelicEffectsForDeveloper =
            userDefaults.object(forKey: StorageKey.AppStorage.disablesDungeonRelicEffectsForDeveloper) as? Bool ?? false
        self.usesStarChartSurveyTowerTheme =
            userDefaults.object(forKey: StorageKey.AppStorage.usesStarChartSurveyTowerTheme) as? Bool ?? false
        self.handOrderingStrategy =
            HandOrderingStrategy(
                rawValue: userDefaults.string(forKey: HandOrderingStrategy.storageKey)
                    ?? HandOrderingStrategy.insertionOrder.rawValue
            ) ?? .insertionOrder
        syncAudioSettings()
    }

    private func syncAudioSettings() {
        GameAudioService.shared.configure(
            isBGMEnabled: bgmEnabled,
            isSoundEffectsEnabled: soundEffectsEnabled,
            bgmVolume: Float(bgmVolume),
            soundEffectsVolume: Float(soundEffectsVolume)
        )
    }

}

/// BGMとSEを一元管理し、設定・広告・アプリライフサイクルをまたいで安全に停止復帰する。
@MainActor
final class GameAudioService {
    enum BGMTrack: String {
        case title = "bgm_title"
        case tower = "bgm_tower"
        case deepTower = "bgm_deep_tower"
    }

    enum SoundEffect: String {
        case waddle = "se_waddle"
        case bellySlide = "se_belly_slide"
        case flutterJump = "se_flutter_jump"
        case warp = "se_warp"
        case fall = "se_fall"
        case damage = "se_damage"
        case pickup = "se_pickup"
        case warning = "se_orca_warning"
        case decision = "se_decision"
        case invalid = "se_invalid"
        case heal = "se_heal"
    }

    enum PauseReason: Hashable {
        case background
        case advertisement
        case interruption
    }

    static let shared = GameAudioService()

    private var bgmPlayer: AVAudioPlayer?
    private var soundEffectPlayers: [AVAudioPlayer] = []
    private var currentTrack: BGMTrack?
    private var pauseReasons: Set<PauseReason> = []
    private var isBGMEnabled = true
    private var isSoundEffectsEnabled = true
    private var bgmVolume: Float = 0.42
    private var soundEffectsVolume: Float = 0.68

    private init() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { notification in
            Task { @MainActor in
                guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue)
                else { return }
                if type == .began {
                    GameAudioService.shared.pause(for: .interruption)
                } else {
                    GameAudioService.shared.resume(after: .interruption)
                }
            }
        }
    }

    func configure(
        isBGMEnabled: Bool,
        isSoundEffectsEnabled: Bool,
        bgmVolume: Float,
        soundEffectsVolume: Float
    ) {
        self.isBGMEnabled = isBGMEnabled
        self.isSoundEffectsEnabled = isSoundEffectsEnabled
        self.bgmVolume = min(max(bgmVolume, 0), 1)
        self.soundEffectsVolume = min(max(soundEffectsVolume, 0), 1)
        bgmPlayer?.volume = self.bgmVolume
        if !isBGMEnabled {
            bgmPlayer?.stop()
        } else if pauseReasons.isEmpty, let currentTrack {
            playBGM(currentTrack)
        }
        if !isSoundEffectsEnabled {
            soundEffectPlayers.forEach { $0.stop() }
            soundEffectPlayers.removeAll()
        }
    }

    func playBGM(_ track: BGMTrack) {
        currentTrack = track
        guard isBGMEnabled, pauseReasons.isEmpty else { return }
        if bgmPlayer?.isPlaying == true,
           bgmPlayer?.url?.deletingPathExtension().lastPathComponent == track.rawValue {
            return
        }
        guard let url = Bundle.main.url(forResource: track.rawValue, withExtension: "wav", subdirectory: "Audio")
                ?? Bundle.main.url(forResource: track.rawValue, withExtension: "wav")
        else { return }
        do {
            try configureAudioSession()
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = bgmVolume
            player.prepareToPlay()
            player.play()
            bgmPlayer = player
        } catch {
            bgmPlayer = nil
        }
    }

    func play(_ effect: SoundEffect) {
        guard isSoundEffectsEnabled, pauseReasons.isEmpty else { return }
        soundEffectPlayers.removeAll { !$0.isPlaying }
        guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav", subdirectory: "Audio")
                ?? Bundle.main.url(forResource: effect.rawValue, withExtension: "wav")
        else { return }
        do {
            try configureAudioSession()
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = soundEffectsVolume
            player.prepareToPlay()
            player.play()
            soundEffectPlayers.append(player)
        } catch {
            return
        }
    }

    func pause(for reason: PauseReason) {
        pauseReasons.insert(reason)
        bgmPlayer?.pause()
        soundEffectPlayers.forEach { $0.stop() }
        soundEffectPlayers.removeAll()
    }

    func resume(after reason: PauseReason) {
        pauseReasons.remove(reason)
        guard pauseReasons.isEmpty, isBGMEnabled else { return }
        if let bgmPlayer, bgmPlayer.currentTime > 0 {
            bgmPlayer.play()
        } else if let currentTrack {
            playBGM(currentTrack)
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }
}

/// 遊び方辞典の発見済み項目を保存するストア
@MainActor
final class EncyclopediaDiscoveryStore: ObservableObject {
    private let userDefaults: UserDefaults
    private let storageKey: String

    @Published private(set) var discoveredRawIDs: Set<String>

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = StorageKey.UserDefaults.encyclopediaDiscovery
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        self.discoveredRawIDs = Set(userDefaults.stringArray(forKey: storageKey) ?? [])
    }

    var discoveredIDs: Set<EncyclopediaDiscoveryID> {
        Set(discoveredRawIDs.compactMap(EncyclopediaDiscoveryID.init(rawValue:)))
    }

    func isDiscovered(_ id: EncyclopediaDiscoveryID) -> Bool {
        discoveredRawIDs.contains(id.rawValue)
    }

    func discover(_ id: EncyclopediaDiscoveryID) {
        discover([id])
    }

    func discover(_ ids: some Sequence<EncyclopediaDiscoveryID>) {
        var updatedIDs = discoveredRawIDs
        for id in ids {
            updatedIDs.insert(id.rawValue)
        }
        saveIfChanged(updatedIDs)
    }

    func reset() {
        saveIfChanged([])
    }

    func discoveredCount(in ids: some Sequence<EncyclopediaDiscoveryID>) -> Int {
        ids.reduce(0) { count, id in
            count + (isDiscovered(id) ? 1 : 0)
        }
    }

    private func saveIfChanged(_ updatedIDs: Set<String>) {
        guard updatedIDs != discoveredRawIDs else { return }
        discoveredRawIDs = updatedIDs
        userDefaults.set(Array(updatedIDs).sorted(), forKey: storageKey)
    }
}
