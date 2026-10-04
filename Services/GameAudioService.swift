import AVFoundation
import Foundation
import SharedSupport

enum GameMusic: String, CaseIterable {
    case title = "bgm_title"
    case tutorial = "bgm_tutorial"
    case growth = "bgm_growth"
    case trial = "bgm_trial"
}

enum GameSound: String, CaseIterable {
    case select = "se_select"
    case move = "se_move"
    case pickup = "se_pickup"
    case damage = "se_damage"
    case heal = "se_heal"
    case clear = "se_clear"
    case defeat = "se_defeat"
    case victory = "se_victory"
    case warning = "se_warning"
    case relic = "se_relic"
}

/// 再生はアプリ層で完結させ、Game の判定や保存データへ音の依存を持ち込まない。
@MainActor
final class GameAudioService {
    static let shared = GameAudioService()

    enum Suspension: Hashable {
        case scene, pauseMenu, advertisement, interruption, headphonesDisconnected
    }

    private let bundle: Bundle
    private let notificationCenter: NotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var musicPlayer: AVAudioPlayer?
    private var soundPlayers: [AVAudioPlayer] = []
    private(set) var requestedMusic: GameMusic?
    private(set) var suspensions: Set<Suspension> = [.scene]
    private(set) var musicVolume: Float = 0.35
    private(set) var soundVolume: Float = 0.65
    private(set) var musicEnabled = true
    private(set) var soundEnabled = true
    private var isSessionConfigured = false
    private var lastSoundTimes: [GameSound: TimeInterval] = [:]

    var isMusicPlaying: Bool { musicPlayer?.isPlaying == true }

    init(bundle: Bundle = .main, notificationCenter: NotificationCenter = .default) {
        self.bundle = bundle
        self.notificationCenter = notificationCenter
        observers.append(notificationCenter.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                self?.handleInterruption(type: type, options: options)
            }
        })
        observers.append(notificationCenter.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor [weak self] in
                self?.setSuspended(.headphonesDisconnected, true)
            }
        })
        observers.append(notificationCenter.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isSessionConfigured = false
                self.musicPlayer = nil
                self.stopSounds()
                self.updatePlayback()
            }
        })
    }

    deinit {
        observers.forEach(notificationCenter.removeObserver)
    }

    func configure(musicEnabled: Bool, soundEnabled: Bool, musicVolume: Double, soundVolume: Double) {
        self.musicEnabled = musicEnabled
        self.soundEnabled = soundEnabled
        self.musicVolume = Self.clampedVolume(musicVolume)
        self.soundVolume = Self.clampedVolume(soundVolume)
        if !soundEnabled || self.soundVolume == 0 { stopSounds() }
        soundPlayers.forEach { $0.volume = self.soundVolume }
        updatePlayback()
    }

    static func clampedVolume(_ value: Double) -> Float {
        value.isFinite ? Float(min(max(value, 0), 1)) : 0
    }

    func playMusic(_ music: GameMusic?) {
        if requestedMusic != music {
            musicPlayer?.stop()
            musicPlayer = nil
            requestedMusic = music
        }
        updatePlayback()
    }

    func setSuspended(_ reason: Suspension, _ isSuspended: Bool) {
        if isSuspended { suspensions.insert(reason) } else { suspensions.remove(reason) }
        updatePlayback()
    }

    /// ヘッドホンを外した直後にスピーカーから突然鳴らさず、次の明示操作で再開する。
    func resumeAfterUserAction() {
        setSuspended(.headphonesDisconnected, false)
    }

    func play(_ sound: GameSound) {
        guard soundEnabled, soundVolume > 0, suspensions.isEmpty else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let previous = lastSoundTimes[sound], now - previous < 0.07 { return }
        lastSoundTimes[sound] = now
        do {
            try configureSessionIfNeeded()
            soundPlayers.removeAll { !$0.isPlaying }
            // 連打でもメモリと音量が際限なく増えないよう、同時再生数を制限する。
            if soundPlayers.count >= 4 { soundPlayers.removeFirst().stop() }
            guard let url = resourceURL(sound.rawValue) else { return }
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = soundVolume
            player.prepareToPlay()
            player.play()
            soundPlayers.append(player)
        } catch {
            debugError(error, message: "効果音を再生できませんでした")
        }
    }

    func handleInterruption(type: UInt?, options: UInt) {
        if type == AVAudioSession.InterruptionType.began.rawValue {
            setSuspended(.interruption, true)
        } else if type == AVAudioSession.InterruptionType.ended.rawValue,
                  AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
            setSuspended(.interruption, false)
        }
    }

    func resourceURL(_ name: String) -> URL? {
        bundle.url(forResource: name, withExtension: "wav")
    }

    private func updatePlayback() {
        guard suspensions.isEmpty else {
            musicPlayer?.pause()
            stopSounds()
            return
        }
        guard musicEnabled, musicVolume > 0, let requestedMusic else {
            musicPlayer?.pause()
            return
        }
        do {
            try configureSessionIfNeeded()
            if musicPlayer == nil, let url = resourceURL(requestedMusic.rawValue) {
                musicPlayer = try AVAudioPlayer(contentsOf: url)
                musicPlayer?.numberOfLoops = -1
                musicPlayer?.prepareToPlay()
            }
            guard let musicPlayer else { return }
            if !musicPlayer.isPlaying {
                musicPlayer.volume = 0
                musicPlayer.play()
            }
            musicPlayer.setVolume(musicVolume, fadeDuration: 0.2)
        } catch {
            debugError(error, message: "BGMを再生できませんでした")
        }
    }

    private func configureSessionIfNeeded() throws {
        let session = AVAudioSession.sharedInstance()
        if !isSessionConfigured || session.category != .ambient || session.mode != .default {
            // 消音スイッチを尊重し、ユーザーが再生している音楽を止めない。
            // 広告SDKがカテゴリを変更した場合も、ゲーム音の再開時に戻す。
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            isSessionConfigured = true
        }
        try session.setActive(true)
    }

    private func stopSounds() {
        soundPlayers.forEach { $0.stop() }
        soundPlayers.removeAll()
    }
}
