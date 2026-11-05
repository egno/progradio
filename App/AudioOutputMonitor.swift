import CoreAudio
import Foundation

/// Watches the system's default output device, so the player can tell when sound goes to an AirPlay
/// speaker picked in Control Center's Sound menu.
@MainActor
final class AudioOutputMonitor {
    var onChange: (() -> Void)?
    private(set) var isAirPlay = false

    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)

    init() {
        isAirPlay = Self.defaultOutputIsAirPlay()
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let airPlay = Self.defaultOutputIsAirPlay()
                guard airPlay != self.isAirPlay else { return }
                self.isAirPlay = airPlay
                self.onChange?()
            }
        }
    }

    private static func defaultOutputIsAirPlay() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else {
            return false
        }
        var transport = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return false }
        return transport == kAudioDeviceTransportTypeAirPlay
    }
}
