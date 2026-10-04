import AVFoundation
import XCTest
@testable import MonoKnightApp

@MainActor
final class GameAudioServiceTests: XCTestCase {
    private var appBundle: Bundle { Bundle(for: GameSettingsStore.self) }

    func testAllBundledAudioDecodesAndLoopEdgesAreSilent() throws {
        let names = GameMusic.allCases.map(\.rawValue) + GameSound.allCases.map(\.rawValue)
        for name in names {
            let url = try XCTUnwrap(appBundle.url(forResource: name, withExtension: "wav"), "同梱音源がありません: \(name)")
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertGreaterThan(player.duration, 0.05)
            XCTAssertEqual(player.numberOfChannels, 1)
            let file = try AVAudioFile(forReading: url)
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 1))
            try file.read(into: buffer, frameCount: 1)
            XCTAssertEqual(try XCTUnwrap(buffer.floatChannelData)[0][0], 0, accuracy: 0.0001)
            file.framePosition = file.length - 1
            try file.read(into: buffer, frameCount: 1)
            XCTAssertEqual(try XCTUnwrap(buffer.floatChannelData)[0][0], 0, accuracy: 0.0001)
        }
    }

    func testIndependentSuspensionsDoNotResumeMusicPrematurely() {
        let service = GameAudioService(bundle: appBundle)
        service.playMusic(.title)
        service.setSuspended(.scene, false)
        XCTAssertTrue(service.isMusicPlaying)
        service.setSuspended(.pauseMenu, true)
        service.setSuspended(.advertisement, true)
        service.setSuspended(.scene, true)
        XCTAssertFalse(service.isMusicPlaying)
        service.setSuspended(.advertisement, false)
        service.setSuspended(.scene, false)
        XCTAssertFalse(service.isMusicPlaying, "ポーズ中に広告終了や前面復帰で再生しない")
        service.setSuspended(.pauseMenu, false)
        XCTAssertTrue(service.isMusicPlaying)
        service.setSuspended(.scene, true)
    }

    func testDisabledOrZeroVolumeMusicStaysSilentAndCanResume() {
        let service = GameAudioService(bundle: appBundle)
        service.playMusic(.growth)
        service.setSuspended(.scene, false)
        service.configure(musicEnabled: false, soundEnabled: true, musicVolume: 0.35, soundVolume: 0.65)
        XCTAssertFalse(service.isMusicPlaying)
        service.configure(musicEnabled: true, soundEnabled: true, musicVolume: 0, soundVolume: 0.65)
        XCTAssertFalse(service.isMusicPlaying)
        service.configure(musicEnabled: true, soundEnabled: true, musicVolume: 0.3, soundVolume: 0.65)
        XCTAssertTrue(service.isMusicPlaying)
        service.playMusic(nil)
        XCTAssertFalse(service.isMusicPlaying)
        XCTAssertNil(service.requestedMusic)
    }

    func testInterruptionWithoutResumePermissionRemainsSilent() {
        let service = GameAudioService(bundle: appBundle)
        service.playMusic(.trial)
        service.setSuspended(.scene, false)
        service.handleInterruption(type: AVAudioSession.InterruptionType.began.rawValue, options: 0)
        XCTAssertFalse(service.isMusicPlaying)
        service.handleInterruption(type: AVAudioSession.InterruptionType.ended.rawValue, options: 0)
        XCTAssertFalse(service.isMusicPlaying)
        service.handleInterruption(type: AVAudioSession.InterruptionType.ended.rawValue,
                                   options: AVAudioSession.InterruptionOptions.shouldResume.rawValue)
        XCTAssertTrue(service.isMusicPlaying)
        service.setSuspended(.scene, true)
    }

    func testHeadphoneRemovalRequiresUserAction() {
        let service = GameAudioService(bundle: appBundle)
        service.playMusic(.tutorial)
        service.setSuspended(.scene, false)
        service.setSuspended(.headphonesDisconnected, true)
        XCTAssertFalse(service.isMusicPlaying)
        service.configure(musicEnabled: true, soundEnabled: true, musicVolume: 0.4, soundVolume: 0.5)
        XCTAssertFalse(service.isMusicPlaying)
        service.resumeAfterUserAction()
        XCTAssertTrue(service.isMusicPlaying)
        service.setSuspended(.scene, true)
    }

    func testMissingResourceDoesNotCrash() {
        let service = GameAudioService(bundle: Bundle(for: Self.self))
        service.setSuspended(.scene, false)
        service.playMusic(.title)
        service.play(.pickup)
        XCTAssertFalse(service.isMusicPlaying)
    }

    func testPlaybackRestoresAmbientCategoryAfterAnotherComponentChangesIt() throws {
        let service = GameAudioService(bundle: appBundle)
        service.playMusic(.title)
        service.setSuspended(.scene, false)
        let session = AVAudioSession.sharedInstance()
        XCTAssertEqual(session.category, .ambient)
        service.setSuspended(.advertisement, true)
        try session.setCategory(.playback)
        service.setSuspended(.advertisement, false)
        XCTAssertEqual(session.category, .ambient, "広告終了後も端末の消音設定を尊重する")
        XCTAssertTrue(service.isMusicPlaying)
        service.setSuspended(.scene, true)
    }

    func testAudioSettingsPersistIndependentlyAndClampInvalidVolumes() {
        let suite = "GameAudioSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = GameSettingsStore(userDefaults: defaults)
        XCTAssertTrue(settings.musicEnabled)
        XCTAssertTrue(settings.soundEnabled)
        settings.musicEnabled = false
        settings.soundEnabled = true
        settings.musicVolume = 0.2
        settings.soundVolume = 0.8
        let restored = GameSettingsStore(userDefaults: defaults)
        XCTAssertFalse(restored.musicEnabled)
        XCTAssertTrue(restored.soundEnabled)
        XCTAssertEqual(restored.musicVolume, 0.2, accuracy: 0.000001)
        XCTAssertEqual(restored.soundVolume, 0.8, accuracy: 0.000001)
        settings.musicVolume = -2
        settings.soundVolume = 5
        XCTAssertEqual(settings.musicVolume, 0)
        XCTAssertEqual(settings.soundVolume, 1)
        settings.musicVolume = .nan
        XCTAssertEqual(settings.musicVolume, 0)
    }
}
